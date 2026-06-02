# TradingAgent

An autonomous trading agent framework built on top of `ollama_agent`.

## Features
- **Reasoning Layer**: Uses Ollama models (via `ollama_agent`) to analyze market data and plan trades.
- **Deterministic Risk Engine**: Enforces leverage, position size, and drawdown limits.
- **Event-Driven**: Built on `dry-events` and `async` for high-concurrency market processing.
- **Exchange Agnostic**: Pluggable exchange adapter (currently supporting Binance Futures).

## Getting Started

### Installation
Add to your Gemfile:
```ruby
gem 'trading_agent', path: './trading_agent'
```

### Basic Usage

```ruby
require 'trading_agent'

exchange = TradingAgent::Exchanges::BinanceFutures.new(
  api_key: ENV['BINANCE_API_KEY'],
  secret_key: ENV['BINANCE_SECRET_KEY'],
  testnet: true
)

runner = TradingAgent::Runner.new(
  exchange: exchange,
  model: "qwen2.5:14b",
  symbols: ["BTCUSDT", "ETHUSDT"]
)

runner.start
```

## Architecture
See `docs/TRADING_AGENT_PLAN.md` in the root repository for detailed architectural overview.
