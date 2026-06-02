# frozen_string_literal: true

require "dry-validation"

module TradingAgent
  module Validation
    module Schemas
      VALID_INTERVALS = %w[1m 3m 5m 15m 30m 1h 2h 4h 6h 8h 12h 1d].freeze

      class TradeIntent < Dry::Validation::Contract
        params do
          required(:action).filled(:string)
          required(:symbol).filled(:string)
          required(:leverage).filled(:integer)
          required(:risk_percent).filled(:float)
          required(:stop_loss).filled(:float)
          required(:take_profit).filled(:float)
          optional(:reasoning).array(:string)
        end

        rule(:action)       { key.failure("must be BUY, SELL or HOLD") unless %w[BUY SELL HOLD].include?(value.upcase) }
        rule(:leverage)     { key.failure("must be 1..20")    unless (1..20).cover?(value) }
        rule(:risk_percent) { key.failure("must be 0.1..5.0") unless value.between?(0.1, 5.0) }
      end

      class FetchCandles < Dry::Validation::Contract
        params do
          required(:symbol).filled(:string)
          required(:interval).filled(:string)
          optional(:limit).filled(:integer)
        end

        rule(:interval) { key.failure("invalid (valid: #{VALID_INTERVALS.join(', ')})") unless VALID_INTERVALS.include?(value) }
        rule(:limit)    { key.failure("must be 1..1500") if key? && !value.between?(1, 1500) }
      end

      class BacktestStrategy < Dry::Validation::Contract
        params do
          required(:symbol).filled(:string)
          required(:direction).filled(:string)
          required(:stop_loss_atr_multiplier).filled(:float)
          required(:take_profit_rr).filled(:float)
          required(:leverage).filled(:integer)
          required(:risk_percent).filled(:float)
          optional(:entry_condition).hash
        end

        rule(:direction)                { key.failure("must be LONG or SHORT") unless %w[LONG SHORT].include?(value.upcase) }
        rule(:stop_loss_atr_multiplier) { key.failure("must be 0.5..5.0")  unless value.between?(0.5, 5.0) }
        rule(:take_profit_rr)           { key.failure("must be 1.0..10.0") unless value.between?(1.0, 10.0) }
      end
    end
  end
end
