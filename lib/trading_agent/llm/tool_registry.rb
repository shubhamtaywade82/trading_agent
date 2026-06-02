# frozen_string_literal: true

module TradingAgent
  module Llm
    class ToolRegistry
      VALID_INTERVALS = %w[1m 3m 5m 15m 30m 1h 2h 4h 6h 8h 12h 1d].freeze

      def self.register_all(state, exchange)
        analytics = Analytics::Engine.new
        patterns  = Analytics::PatternDetector.new

        # ── 1. fetch_market_context (legacy single-TF — kept for backward compat) ──
        OllamaAgent::Tools.register(
          :fetch_market_context,
          schema: {
            description: "Retrieve current price, 1h indicators (RSI, EMA, SMA, ATR), account balances, and open position for a symbol.",
            parameters:  {
              type:       "object",
              properties: { symbol: { type: "string", description: "e.g. BTCUSDT" } },
              required:   ["symbol"]
            }
          }
        ) do |args, _context|
          symbol = resolve_symbol(args)
          price  = fetch_price(state, exchange, symbol)
          candles = fetch_candles_cached(state, exchange, symbol, "1h", 100)

          {
            symbol:          symbol,
            price:           price,
            indicators_1h:   compute_indicators(candles),
            position:        state.get_position(symbol),
            balances:        state.get_balances,
            daily_drawdown_pct: state.current_drawdown_pct
          }.to_json
        end

        # ── 2. fetch_multi_timeframe_context ────────────────────────────────
        OllamaAgent::Tools.register(
          :fetch_multi_timeframe_context,
          schema: {
            description: "Fetch price and technical indicators across 4h (macro trend), 1h (swing), 15m (entry structure), and 1m (microstructure) timeframes. Use this first before any analysis.",
            parameters:  {
              type:       "object",
              properties: { symbol: { type: "string", description: "e.g. BTCUSDT" } },
              required:   ["symbol"]
            }
          }
        ) do |args, _context|
          symbol = resolve_symbol(args)
          price  = fetch_price(state, exchange, symbol)

          tf_data = %w[4h 1h 15m 1m].each_with_object({}) do |tf, acc|
            limit   = tf == "1m" ? 200 : 100
            candles = fetch_candles_cached(state, exchange, symbol, tf, limit)
            acc[tf] = compute_indicators(candles).merge(candle_count: candles.size)
          end

          {
            symbol:    symbol,
            price:     price,
            timeframes: tf_data,
            position:  state.get_position(symbol),
            account:   {
              equity:        state.total_equity,
              drawdown_pct:  state.current_drawdown_pct,
              open_positions: state.open_positions_count
            }
          }.to_json
        end

        # ── 3. check_indicators (single timeframe — kept for compat) ────────
        OllamaAgent::Tools.register(
          :check_indicators,
          schema: {
            description: "Check technical indicators for a symbol on a specific timeframe.",
            parameters:  {
              type:       "object",
              properties: {
                symbol:   { type: "string" },
                interval: { type: "string", description: "e.g. 15m, 1h, 4h" }
              },
              required:   ["symbol", "interval"]
            }
          }
        ) do |args, _context|
          symbol   = resolve_symbol(args)
          interval = sanitize_interval(args[:interval] || args["interval"] || "1h")
          candles  = fetch_candles_cached(state, exchange, symbol, interval, 100)

          compute_indicators(candles).merge(
            symbol:       symbol,
            interval:     interval,
            candle_count: candles.size
          ).to_json
        end

        # ── 4. analyze_microstructure ────────────────────────────────────────
        OllamaAgent::Tools.register(
          :analyze_microstructure,
          schema: {
            description: "Analyze 1-minute microstructure: volume delta (buy vs sell pressure), volume/price absorption ratio, volume spike detection, and volatility compression. Call after fetch_multi_timeframe_context.",
            parameters:  {
              type:       "object",
              properties: {
                symbol: { type: "string" },
                limit:  { type: "integer", description: "Number of 1m candles (default 200, max 500)" }
              },
              required:   ["symbol"]
            }
          }
        ) do |args, _context|
          symbol  = resolve_symbol(args)
          limit   = [[args[:limit].to_i, args["limit"].to_i].max, 500].min
          limit   = 200 if limit < 1
          candles = fetch_candles_cached(state, exchange, symbol, "1m", limit)

          if candles.size < 20
            { error: "Insufficient candle data", symbol: symbol }.to_json
          else
            deltas    = analytics.cumulative_delta(candles)
            last_5    = deltas.last(5)
            vp_ratio  = analytics.volume_price_ratio(candles)
            vol_spike = analytics.volume_spike(candles)
            volatility = analytics.volatility_metrics(candles)

            {
              symbol:           symbol,
              cumulative_delta: {
                last_5_bars:  last_5,
                trend:        delta_trend(last_5)
              },
              absorption:      vp_ratio,
              volume_spike:    vol_spike,
              volatility:      volatility
            }.to_json
          end
        end

        # ── 5. detect_patterns ───────────────────────────────────────────────
        OllamaAgent::Tools.register(
          :detect_patterns,
          schema: {
            description: "Detect structural patterns: order blocks (institutional entry zones), liquidity sweeps (stop hunts), and premium/discount zone positioning. Call after analyze_microstructure.",
            parameters:  {
              type:       "object",
              properties: {
                symbol:   { type: "string" },
                interval: { type: "string", description: "Timeframe to scan (default 1h)" }
              },
              required:   ["symbol"]
            }
          }
        ) do |args, _context|
          symbol   = resolve_symbol(args)
          interval = sanitize_interval(args[:interval] || args["interval"] || "1h")
          candles  = fetch_candles_cached(state, exchange, symbol, interval, 200)

          if candles.size < 50
            { error: "Insufficient candle data", symbol: symbol }.to_json
          else
            {
              symbol:       symbol,
              interval:     interval,
              order_blocks: patterns.detect_order_blocks(candles),
              sweeps:       patterns.detect_liquidity_sweeps(candles),
              zones:        patterns.detect_premium_discount_zones(candles)
            }.to_json
          end
        end

        # ── 6. rank_symbols ───────────────────────────────────────────────────
        OllamaAgent::Tools.register(
          :rank_symbols,
          schema: {
            description: "Score and rank multiple symbols by momentum (RSI deviation from 50), ATR volatility, and volume spike ratio. Use to identify the highest-conviction setup.",
            parameters:  {
              type:       "object",
              properties: {
                symbols: {
                  type:        "array",
                  items:       { type: "string" },
                  description: "List of symbols, e.g. [\"BTCUSDT\", \"ETHUSDT\"]"
                }
              },
              required:   ["symbols"]
            }
          }
        ) do |args, _context|
          raw_syms = args[:symbols] || args["symbols"] || []
          syms     = Array(raw_syms).map(&:upcase).first(10)

          scored = syms.filter_map do |sym|
            candles = fetch_candles_cached(state, exchange, sym, "1h", 100)
            next nil if candles.size < 20

            rsi       = Market::Indicators.rsi(candles, 14).to_f
            atr       = Market::Indicators.atr(candles, 14).to_f
            price     = candles.last[4].to_f
            vol_spike = analytics.volume_spike(candles)
            momentum  = (rsi - 50.0).abs   # distance from neutral

            {
              symbol:       sym,
              rsi:          rsi.round(2),
              atr:          atr.round(4),
              atr_pct:      price.positive? ? (atr / price * 100).round(3) : 0,
              spike_ratio:  vol_spike[:spike_ratio],
              momentum:     momentum.round(2),
              score:        (momentum * vol_spike[:spike_ratio]).round(3)
            }
          end.sort_by { |s| -s[:score] }

          { ranked: scored }.to_json
        end
      end

      # ── Private helpers ─────────────────────────────────────────────────────
      class << self
        private

        def resolve_symbol(args)
          (args[:symbol] || args["symbol"] || "BTCUSDT").upcase
        end

        def sanitize_interval(interval)
          VALID_INTERVALS.include?(interval) ? interval : "1h"
        end

        def fetch_price(state, exchange, symbol)
          price = state.get_price(symbol)
          if price.nil? || price.zero?
            ticker = exchange.fetch_ticker(symbol)
            price  = ticker[:price]
            state.update_price(symbol, price)
          end
          price
        rescue StandardError
          0.0
        end

        def fetch_candles_cached(state, exchange, symbol, interval, limit)
          candles = state.get_candles(symbol, interval)
          if candles.empty?
            candles = exchange.fetch_candles(symbol, interval, limit: limit)
            state.update_candles(symbol, interval, candles) unless candles.empty?
          end
          candles
        rescue StandardError
          []
        end

        def compute_indicators(candles)
          return { error: "no_data" } if candles.size < 2

          rsi  = Market::Indicators.rsi(candles, 14)
          ema  = Market::Indicators.ema(candles, 20)
          sma  = Market::Indicators.sma(candles, 20)
          atr  = Market::Indicators.atr(candles, 14)
          bb   = Market::Indicators.bollinger_bands(candles)

          {
            rsi_14:       rsi&.round(2),
            ema_20:       ema&.round(4),
            sma_20:       sma&.round(4),
            atr_14:       atr&.round(4),
            bb_upper:     bb&.dig(:upper)&.round(4),
            bb_lower:     bb&.dig(:lower)&.round(4),
            bb_width:     bb&.dig(:width)&.round(6)
          }
        end

        def delta_trend(last_5)
          return :neutral if last_5.empty?

          first = last_5.first[:cumulative_delta]
          last  = last_5.last[:cumulative_delta]
          diff  = last - first
          if diff > 0
            :bullish
          elsif diff < 0
            :bearish
          else
            :neutral
          end
        end
      end
    end
  end
end
