# frozen_string_literal: true

require "concurrent-ruby"

module TradingAgent
  module Market
    class State
      attr_reader :daily_peak_equity, :last_peak_reset

      def initialize
        @prices = Concurrent::Map.new
        @candles = Concurrent::Map.new
        @positions = Concurrent::Map.new
        @balances = []
        @daily_peak_equity = nil
        @last_peak_reset = Time.now.utc.to_date
      end

      def update_price(symbol, price)
        @prices[symbol] = price
        EventBus.publish("market.tick", symbol: symbol, price: price)
      end

      def get_price(symbol)
        @prices[symbol]
      end

      def update_candles(symbol, interval, data)
        @candles["#{symbol}_#{interval}"] = data
        EventBus.publish("market.candle_closed", symbol: symbol, interval: interval)
      end

      def get_candles(symbol, interval)
        @candles["#{symbol}_#{interval}"] || []
      end

      def update_position(symbol, data)
        @positions[symbol] = data
        update_equity_metrics
        EventBus.publish("position.updated", symbol: symbol, data: data)
      end

      def get_position(symbol)
        @positions[symbol]
      end

      def update_balances(data)
        @balances = data
        update_equity_metrics
      end

      def get_balances
        @balances
      end

      def total_equity
        # Default to 0 if balances are empty
        return 0.0 if @balances.empty?

        # Try to find USDT balance, fallback to summing all asset balances
        usdt_bal = @balances.find { |b| b[:asset] == "USDT" }
        bal_amount = usdt_bal ? usdt_bal[:balance].to_f : @balances.sum { |b| b[:balance].to_f }

        # Add unrealized PnL of all open positions
        unrealized_pnl = @positions.values.sum { |pos| pos[:unrealized_profit].to_f }

        bal_amount + unrealized_pnl
      end

      def update_equity_metrics
        current_date = Time.now.utc.to_date
        current_equity = total_equity

        if @daily_peak_equity.nil? || current_date > @last_peak_reset
          @daily_peak_equity = current_equity
          @last_peak_reset = current_date
        elsif current_equity > @daily_peak_equity
          @daily_peak_equity = current_equity
        end
      end

      def current_drawdown_pct
        update_equity_metrics
        return 0.0 if @daily_peak_equity.nil? || @daily_peak_equity.zero?

        equity = total_equity
        return 0.0 if equity >= @daily_peak_equity

        (@daily_peak_equity - equity) / @daily_peak_equity
      end

      def open_positions_count
        @positions.values.count { |pos| pos[:position_amt].to_f.abs > 0.0 }
      end
    end
  end
end
