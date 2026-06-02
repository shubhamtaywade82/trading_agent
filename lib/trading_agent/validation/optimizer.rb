# frozen_string_literal: true

module TradingAgent
  module Validation
    class Optimizer
      include SemanticLogger::Loggable

      def initialize(backtest_engine)
        @backtest = backtest_engine
      end

      # Grid search over SL/TP multiplier ranges.
      # param_ranges example:
      #   { stop_loss_atr_multiplier: [1.5, 2.0, 2.5, 3.0], take_profit_rr: [1.5, 2.0, 2.5, 3.0] }
      def grid_search(base_strategy, param_ranges:, period:, min_pf: 1.5, min_trades: 10)
        combos = cartesian(param_ranges)
        logger.info("Optimizer grid search", combinations: combos.size, symbol: base_strategy[:symbol])

        results = combos.filter_map do |params|
          r = @backtest.run(base_strategy.merge(params), period: period)
          next if r.nil? || r.total_trades < min_trades

          {
            params:           params,
            profit_factor:    r.profit_factor,
            win_rate:         r.win_rate,
            max_drawdown_pct: r.max_drawdown_pct,
            total_return_pct: r.total_return_pct,
            sharpe_ratio:     r.sharpe_ratio,
            total_trades:     r.total_trades
          }
        end

        # Score = pf × sharpe bonus, penalised by drawdown
        scored = results.map do |r|
          dd_penalty = [r[:max_drawdown_pct] / 10.0, 1.0].min
          sharpe_mul = r[:sharpe_ratio].positive? ? r[:sharpe_ratio] : 0.1
          score      = r[:profit_factor] * (1.0 - dd_penalty) * sharpe_mul
          r.merge(score: score.round(3))
        end

        viable = scored
                   .select  { |r| r[:profit_factor] >= min_pf }
                   .sort_by { |r| -r[:score] }

        {
          best_params:  viable.first&.dig(:params),
          top_results:  viable.first(5),
          tested:       scored.size,
          viable_count: viable.size
        }
      end

      private

      def cartesian(ranges)
        keys   = ranges.keys
        values = ranges.values
        values[0].product(*values[1..]).map { |combo| keys.zip(combo).to_h }
      end
    end
  end
end
