# frozen_string_literal: true

require "semantic_logger"
require "dry-events"
require "dry-validation"
require "async"
require "ollama_agent"

require_relative "trading_agent/version"
require_relative "trading_agent/event_bus"
require_relative "trading_agent/exchanges/base"
require_relative "trading_agent/exchanges/binance_spot"
require_relative "trading_agent/exchanges/binance_futures"
require_relative "trading_agent/market/state"
require_relative "trading_agent/market/indicators"
require_relative "trading_agent/market/ws_listener"
require_relative "trading_agent/analytics/engine"
require_relative "trading_agent/analytics/pattern_detector"
require_relative "trading_agent/validation/schemas"
require_relative "trading_agent/validation/backtest_engine"
require_relative "trading_agent/validation/optimizer"
require_relative "trading_agent/coordinator/prop_desk"
require_relative "trading_agent/risk/engine"
require_relative "trading_agent/execution/manager"
require_relative "trading_agent/llm/tool_registry"
require_relative "trading_agent/llm/orchestrator"
require_relative "trading_agent/runner"
require_relative "trading_agent/cli/shell"

module TradingAgent
  include SemanticLogger::Loggable

  class Error < StandardError; end

  def self.logger
    SemanticLogger["TradingAgent"]
  end
end
