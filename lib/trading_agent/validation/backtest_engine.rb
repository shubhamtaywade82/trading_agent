# frozen_string_literal: true

module TradingAgent
  module Validation
    class BacktestEngine
      include SemanticLogger::Loggable

      TAKER_FEE    = 0.0004   # 0.04 % per side
      FUNDING_RATE = 0.0001   # 0.01 % per 8 h

      Result = Struct.new(
        :trades, :win_rate, :profit_factor, :total_return_pct,
        :max_drawdown_pct, :avg_rr, :total_trades, :sharpe_ratio,
        :period, keyword_init: true
      )

      def initialize(exchange)
        @exchange  = exchange
        @analytics = Analytics::Engine.new
        @patterns  = Analytics::PatternDetector.new
      end

      # strategy keys (all required):
      #   symbol, direction ("LONG"|"SHORT"),
      #   stop_loss_atr_multiplier, take_profit_rr,
      #   leverage, risk_percent,
      #   entry_condition (optional hash with keys below)
      #
      # entry_condition keys (all optional):
      #   rsi_below, rsi_above, volume_spike_ratio,
      #   require_discount_zone, require_premium_zone
      #
      # period: { start_time: epoch_ms, end_time: epoch_ms }
      def run(strategy, period:, initial_capital: 10_000.0)
        candles = fetch_period_candles(strategy[:symbol], period)
        return nil if candles.nil? || candles.size < 60

        logger.info("Backtest started", symbol: strategy[:symbol],
                    candles: candles.size, period: period)

        equity      = initial_capital
        peak_equity = equity
        max_dd      = 0.0
        trades      = []
        i           = 50

        while i < candles.size - 1
          window         = candles[0..i]
          entry_signal   = evaluate_entry(strategy, window)

          if entry_signal[:triggered]
            entry_price = candles[i][4].to_f
            atr         = Market::Indicators.atr(window, 14).to_f
            sl_dist     = atr * strategy[:stop_loss_atr_multiplier].to_f
            tp_dist     = sl_dist * strategy[:take_profit_rr].to_f

            stop_loss   = strategy[:direction] == "LONG" ? entry_price - sl_dist : entry_price + sl_dist
            take_profit = strategy[:direction] == "LONG" ? entry_price + tp_dist : entry_price - tp_dist

            risk_amount = equity * (strategy[:risk_percent].to_f / 100.0)
            qty         = sl_dist.positive? ? risk_amount / sl_dist : 0.0

            trade_res = simulate_trade(
              candles:     candles[(i + 1)..],
              direction:   strategy[:direction],
              entry_price: entry_price,
              stop_loss:   stop_loss,
              take_profit: take_profit,
              qty:         qty,
              leverage:    strategy[:leverage].to_i
            )

            if trade_res
              fee      = entry_price * qty * TAKER_FEE * 2
              funding  = entry_price * qty * FUNDING_RATE * (trade_res[:bars] / (8.0 * 60))
              net_pnl  = trade_res[:gross_pnl] - fee - funding
              pnl_pct  = equity.positive? ? net_pnl / equity * 100.0 : 0.0

              equity      += net_pnl
              peak_equity  = [peak_equity, equity].max
              drawdown     = peak_equity.positive? ? (peak_equity - equity) / peak_equity * 100.0 : 0.0
              max_dd       = [max_dd, drawdown].max

              trades << {
                entry_time:   candles[i][0],
                entry_price:  entry_price.round(4),
                exit_price:   trade_res[:exit_price].round(4),
                direction:    strategy[:direction],
                outcome:      trade_res[:outcome],
                gross_pnl:    trade_res[:gross_pnl].round(4),
                net_pnl:      net_pnl.round(4),
                pnl_pct:      pnl_pct.round(3),
                bars:         trade_res[:bars],
                rr:           trade_res[:rr].round(2)
              }

              i += trade_res[:bars]
            end
          end

          i += 1
        end

        build_result(trades, initial_capital, equity, max_dd, period)
      end

      private

      def evaluate_entry(strategy, candles)
        cond      = strategy[:entry_condition] || {}
        rsi       = Market::Indicators.rsi(candles, 14).to_f
        vol_spike = @analytics.volume_spike(candles)
        zones     = @patterns.detect_premium_discount_zones(candles)
        direction = strategy[:direction]

        ok = true
        ok &&= rsi < cond[:rsi_below].to_f          if cond[:rsi_below]   && direction == "LONG"
        ok &&= rsi > cond[:rsi_above].to_f          if cond[:rsi_above]   && direction == "SHORT"
        ok &&= vol_spike[:spike_ratio] >= cond[:volume_spike_ratio].to_f if cond[:volume_spike_ratio]
        ok &&= zones[:zone] == :discount             if cond[:require_discount_zone] && direction == "LONG"
        ok &&= zones[:zone] == :premium              if cond[:require_premium_zone]  && direction == "SHORT"

        { triggered: ok, rsi: rsi, vol_spike: vol_spike }
      end

      def simulate_trade(candles:, direction:, entry_price:, stop_loss:, take_profit:, qty:, leverage:)
        sl_dist = (entry_price - stop_loss).abs
        tp_dist = (entry_price - take_profit).abs

        candles.each_with_index do |c, idx|
          high = c[2].to_f
          low  = c[3].to_f

          if direction == "LONG"
            if low <= stop_loss
              gross = (stop_loss - entry_price) * qty * leverage
              return { outcome: :loss, exit_price: stop_loss, gross_pnl: gross, bars: idx + 1, rr: -1.0 }
            end
            if high >= take_profit
              gross = (take_profit - entry_price) * qty * leverage
              return { outcome: :win, exit_price: take_profit, gross_pnl: gross, bars: idx + 1,
                       rr: sl_dist.positive? ? tp_dist / sl_dist : 0.0 }
            end
          else
            if high >= stop_loss
              gross = (entry_price - stop_loss) * qty * leverage
              return { outcome: :loss, exit_price: stop_loss, gross_pnl: -gross, bars: idx + 1, rr: -1.0 }
            end
            if low <= take_profit
              gross = (entry_price - take_profit) * qty * leverage
              return { outcome: :win, exit_price: take_profit, gross_pnl: gross, bars: idx + 1,
                       rr: sl_dist.positive? ? tp_dist / sl_dist : 0.0 }
            end
          end
        end

        nil
      end

      def build_result(trades, initial_capital, final_equity, max_dd, period)
        return nil if trades.empty?

        wins  = trades.select { |t| t[:outcome] == :win }
        losses = trades.select { |t| t[:outcome] == :loss }

        gross_profit = wins.sum  { |t| t[:gross_pnl] }
        gross_loss   = losses.sum { |t| t[:gross_pnl].abs }
        pf           = gross_loss.positive? ? (gross_profit / gross_loss).round(2) : 99.0
        wr           = (wins.size.to_f / trades.size * 100).round(1)
        total_ret    = ((final_equity - initial_capital) / initial_capital * 100).round(2)
        avg_rr       = wins.any? ? (wins.sum { |t| t[:rr] } / wins.size).round(2) : 0.0

        rets     = trades.map { |t| t[:pnl_pct] }
        avg_r    = rets.sum / rets.size
        std_r    = Math.sqrt(rets.sum { |r| (r - avg_r)**2 } / rets.size)
        sharpe   = std_r.positive? ? (avg_r / std_r * Math.sqrt(252)).round(2) : 0.0

        Result.new(
          trades:           trades,
          win_rate:         wr,
          profit_factor:    pf,
          total_return_pct: total_ret,
          max_drawdown_pct: max_dd.round(2),
          avg_rr:           avg_rr,
          total_trades:     trades.size,
          sharpe_ratio:     sharpe,
          period:           period
        )
      end

      def fetch_period_candles(symbol, period)
        all       = []
        cursor    = period[:start_time]
        end_time  = period[:end_time]

        loop do
          batch = @exchange.fetch_candles(symbol, "1m", limit: 1500,
                                          start_time: cursor, end_time: end_time)
          break if batch.nil? || batch.empty?

          all.concat(batch)
          last_t = batch.last[0].to_i
          break if last_t >= end_time || batch.size < 1500

          cursor = last_t + 60_000
          sleep 0.12  # stay under Binance rate limit
        end

        all.select { |c| c[0].to_i <= end_time }
      rescue StandardError => e
        logger.error("Failed to fetch historical candles", error: e.message)
        nil
      end
    end
  end
end
