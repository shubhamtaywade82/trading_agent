# frozen_string_literal: true

module TradingAgent
  module Coordinator
    # Implements the five-stage prop-desk validation pipeline:
    #   Build → Verify (in-sample) → Validate (out-of-sample) → Fine-Tune → Re-Verify
    # A trade intent is only approved when all five stages pass.
    class PropDesk
      include SemanticLogger::Loggable

      # Rolling windows (in seconds)
      IN_SAMPLE_SECS     = 6 * 30 * 24 * 3600   # ~6 months
      OUT_SAMPLE_SECS    = 6 * 30 * 24 * 3600   # prior 6 months

      # Pass/fail thresholds per stage
      THRESHOLDS = {
        verify:    { min_pf: 1.5, max_dd: 20.0, min_trades: 10 },
        validate:  { min_pf: 1.3, max_dd: 25.0, min_trades: 10 },
        re_verify: { min_pf: 1.4, max_dd: 20.0, min_trades: 10 }
      }.freeze

      # SL/TP grid for fine-tuning
      PARAM_GRID = {
        stop_loss_atr_multiplier: [1.5, 2.0, 2.5, 3.0],
        take_profit_rr:           [1.5, 2.0, 2.5, 3.0]
      }.freeze

      def initialize(llm_orchestrator:, backtest_engine:, optimizer:, state:)
        @llm       = llm_orchestrator
        @backtest  = backtest_engine
        @optimizer = optimizer
        @state     = state
      end

      # Returns an approved intent hash, or nil if any stage rejects the hypothesis.
      def run_pipeline(symbol)
        logger.info("PropDesk pipeline starting", symbol: symbol)

        # ── Stage 1: Build ─────────────────────────────────────────────────
        intent = build_hypothesis(symbol)
        return nil unless tradeable?(intent)

        logger.info("Hypothesis built", action: intent[:action], symbol: intent[:symbol])

        strategy = intent_to_strategy(intent)

        # ── Stage 2: Verify (in-sample) ────────────────────────────────────
        is_period = in_sample_period
        is_result = @backtest.run(strategy, period: is_period)
        unless passes?(is_result, :verify)
          logger.warn("In-sample backtest FAILED",
                      pf: is_result&.profit_factor, trades: is_result&.total_trades)
          return nil
        end
        logger.info("In-sample PASSED", pf: is_result.profit_factor, wr: is_result.win_rate)

        # ── Stage 3: Validate (out-of-sample) ──────────────────────────────
        oos_period = out_sample_period
        oos_result = @backtest.run(strategy, period: oos_period)
        unless passes?(oos_result, :validate)
          logger.warn("Out-of-sample FAILED — possible overfit",
                      pf: oos_result&.profit_factor)
          return nil
        end

        degradation = is_result.profit_factor - oos_result.profit_factor
        if degradation > 0.5
          logger.warn("Performance degradation too high — rejecting", delta: degradation)
          return nil
        end
        logger.info("Out-of-sample PASSED", pf: oos_result.profit_factor, degradation: degradation)

        # ── Stage 4: Fine-Tune ─────────────────────────────────────────────
        opt = @optimizer.grid_search(strategy, param_ranges: PARAM_GRID, period: is_period)
        if opt[:best_params]
          strategy = strategy.merge(opt[:best_params])
          logger.info("Parameters optimised", params: opt[:best_params])
        end

        # ── Stage 5: Re-Verify ─────────────────────────────────────────────
        final = @backtest.run(strategy, period: oos_period)
        unless passes?(final, :re_verify)
          logger.warn("Re-verification FAILED after optimisation")
          return nil
        end
        logger.info("PropDesk pipeline APPROVED",
                    symbol: symbol,
                    is_pf: is_result.profit_factor,
                    oos_pf: oos_result.profit_factor,
                    final_pf: final.profit_factor)

        EventBus.publish("strategy.signal",
                         symbol: symbol, strategy: strategy,
                         in_sample_pf: is_result.profit_factor,
                         out_sample_pf: oos_result.profit_factor,
                         final_pf: final.profit_factor)

        intent.merge(
          validated_strategy: strategy,
          in_sample_pf:  is_result.profit_factor,
          out_sample_pf: oos_result.profit_factor,
          final_pf:      final.profit_factor
        )
      end

      private

      def build_hypothesis(symbol)
        context = {
          symbol:   symbol,
          price:    @state.get_price(symbol),
          account:  {
            equity:        @state.total_equity,
            drawdown_pct:  (@state.current_drawdown_pct * 100).round(2),
            open_positions: @state.open_positions_count
          },
          instructions: "Use fetch_multi_timeframe_context, then analyze_microstructure, " \
                        "then detect_patterns for #{symbol}. Confirm all timeframes align " \
                        "before proposing a trade. Respond in JSON."
        }
        @llm.analyze_and_plan(context)
      end

      def intent_to_strategy(intent)
        direction = intent[:action]&.upcase == "BUY" ? "LONG" : "SHORT"
        {
          symbol:                    (intent[:symbol] || "BTCUSDT").upcase,
          direction:                 direction,
          stop_loss_atr_multiplier:  2.0,
          take_profit_rr:            2.0,
          leverage:                  [[intent[:leverage].to_i, 1].max, 5].min,
          risk_percent:              intent[:risk_percent].to_f.clamp(0.1, 2.0),
          entry_condition: {
            volume_spike_ratio:  2.0,
            require_discount_zone: direction == "LONG",
            require_premium_zone:  direction == "SHORT"
          }
        }
      end

      def tradeable?(intent)
        return false if intent.nil?
        return false if intent[:action].nil?

        intent[:action].upcase != "HOLD"
      end

      def passes?(result, stage)
        return false if result.nil?

        t = THRESHOLDS[stage]
        result.profit_factor   >= t[:min_pf]    &&
          result.max_drawdown_pct <= t[:max_dd] &&
          result.total_trades     >= t[:min_trades]
      end

      def in_sample_period
        now       = Time.now.utc.to_i * 1000
        end_time  = now - OUT_SAMPLE_SECS * 1000
        start_time = end_time - IN_SAMPLE_SECS * 1000
        { start_time: start_time, end_time: end_time }
      end

      def out_sample_period
        now       = Time.now.utc.to_i * 1000
        end_time  = now
        start_time = now - OUT_SAMPLE_SECS * 1000
        { start_time: start_time, end_time: end_time }
      end
    end
  end
end
