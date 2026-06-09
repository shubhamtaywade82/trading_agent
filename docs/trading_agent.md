how can we create a trading agent using this ollama_agent implementation
Direct answer:
Do not directly embed Binance connector calls inside the current ollama_agent loop.

Build a layered event-driven trading runtime around the Ollama agent.

The LLM should:

analyze

plan

select tools

validate

explain


The deterministic Ruby runtime should:

fetch market data

manage positions

calculate risk

place/cancel orders

maintain state

enforce guardrails


Otherwise the agent will eventually hallucinate trades, violate leverage/risk constraints, or deadlock on websocket state.


---

Recommended Architecture

┌─────────────────────┐
                    │     Ollama LLM      │
                    │  qwen3.5 / deepseek │
                    └──────────┬──────────┘
                               │
                    Tool Calling / JSON
                               │
                ┌──────────────▼──────────────┐
                │        Agent Runtime         │
                │      (Ruby Orchestrator)     │
                └──────────────┬──────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
         ▼                     ▼                     ▼
┌────────────────┐   ┌────────────────┐   ┌────────────────┐
│ Market Service │   │ Strategy Engine│   │ Risk Engine    │
│ Binance WS     │   │ Indicators     │   │ Position rules │
│ OHLCV Cache    │   │ SMC/Trend      │   │ SL/TP sizing   │
└────────────────┘   └────────────────┘   └────────────────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               ▼
                    ┌─────────────────────┐
                    │ Execution Service   │
                    │ Binance Connector   │
                    │ Orders/Positions    │
                    └─────────────────────┘


---

What Each Repo Should Do

1. Binance Connector Ruby

Use for:

REST API

orders

positions

balances

leverage

account info

websocket user stream

futures endpoints


This becomes your deterministic exchange adapter.

Use:

UM Futures

Spot

websocket streams


Repo: [binance-connector-ruby](https://github.com/binance/binance-connector-ruby?utm_source=chatgpt.com)


---

2. Binance Toolbox

Do not use as production runtime.

Use it as:

reference implementation

latency validation

local order book management

websocket sequencing

reconciliation examples


Repo: [binance-toolbox-python](https://github.com/binance/binance-toolbox-python?utm_source=chatgpt.com)

Especially important:

local order book sync

websocket recovery

sequence validation


The toolbox examples solve real exchange consistency problems.


---

3. Ollama Agent

Repo: [ollama_agent](https://github.com/shubhamtaywade82/ollama_agent?utm_source=chatgpt.com)

This should become:

planner

reasoning layer

signal evaluator

tool caller

strategy explainer


NOT:

execution authority

direct exchange writer

state source of truth



---

Correct Production Design

Core Principle

LLM NEVER TOUCHES BINANCE DIRECTLY

LLM emits:

{
  "action": "LONG",
  "symbol": "BTCUSDT",
  "confidence": 0.82,
  "reasoning": [
    "4H bullish BOS",
    "1H demand reclaim",
    "5m momentum expansion"
  ]
}

Runtime validates:

balance

max risk

max exposure

cooldown

spread

slippage

volatility

open positions


Then runtime decides whether order placement is allowed.


---

Recommended Ruby Project Structure

crypto_trader/
├── app/
│   ├── agents/
│   │   ├── trading_agent.rb
│   │   ├── planner_agent.rb
│   │   └── validator_agent.rb
│   │
│   ├── exchanges/
│   │   ├── binance/
│   │   │   ├── client.rb
│   │   │   ├── futures_client.rb
│   │   │   ├── websocket_client.rb
│   │   │   ├── execution_service.rb
│   │   │   └── orderbook_manager.rb
│   │
│   ├── market/
│   │   ├── candle_store.rb
│   │   ├── indicators/
│   │   ├── orderflow/
│   │   └── scanners/
│   │
│   ├── strategies/
│   │   ├── smc_strategy.rb
│   │   ├── trend_strategy.rb
│   │   └── volatility_strategy.rb
│   │
│   ├── risk/
│   │   ├── position_sizer.rb
│   │   ├── exposure_manager.rb
│   │   ├── liquidation_guard.rb
│   │   └── leverage_manager.rb
│   │
│   ├── execution/
│   │   ├── order_manager.rb
│   │   ├── position_manager.rb
│   │   ├── trailing_manager.rb
│   │   └── emergency_exit.rb
│   │
│   └── llm/
│       ├── ollama_client.rb
│       ├── tool_registry.rb
│       ├── prompt_builder.rb
│       └── response_validator.rb


---

Best Integration Model

Tool Calling Architecture

The agent should not generate free text.

Force structured tool calls.

Example:

TOOLS = [
  "fetch_market_context",
  "analyze_structure",
  "calculate_risk",
  "place_trade",
  "close_position"
]


---

Example Runtime Loop

loop do
  market_context = Market::ContextBuilder.call

  response = Llm::TradingAgent.call(
    context: market_context
  )

  validated = Llm::ResponseValidator.call(response)

  next unless validated.valid?

  Risk::TradeGuard.validate!(validated)

  Execution::OrderManager.execute(validated)

  sleep 2
end


---

Critical Missing Piece

The current ollama_agent repo likely lacks:

1. Deterministic State Engine

You need:

active positions cache

websocket synchronized state

order lifecycle state machine

reconciliation engine


Without this:

duplicate orders happen

stale position state occurs

SL/TP desync happens



---

2. Structured Tool Calling

Do NOT rely on prompt parsing.

Use JSON schema enforced outputs.

Example:

{
  "decision": "BUY",
  "symbol": "ETHUSDT",
  "entry_type": "MARKET",
  "risk_percent": 1,
  "stop_loss": 2450,
  "take_profit": 2525
}

Reject malformed outputs.


---

3. Market Data Layer

You need:

websocket streaming

local candle aggregation

orderbook cache

funding rate cache

OI cache


LLM should never directly query Binance repeatedly.

The runtime feeds compressed context.


---

Recommended Models

Local Ollama

Best balance

[Qwen3.5 Models](https://ollama.com/library/qwen3.5?utm_source=chatgpt.com)

qwen3.5:14b

qwen3.5:32b


Good:

structured outputs

tool calling

reasoning

coding



---

Fast planner

deepseek-r1:14b



---

Heavy analysis

deepseek-v4-pro

qwen3.5:72b


Use cloud fallback.


---

Best Strategy

Hybrid Agent System

Local agent

Handles:

live trading

low latency

execution

websocket state


Cloud agent

Handles:

deep analysis

market regime detection

multi-symbol ranking

narrative reasoning



---

Recommended Tool Interface

Example

class FetchMarketContextTool
  def self.call(symbol:)
    {
      symbol: symbol,
      price: cache.price(symbol),
      trend: trend(symbol),
      rsi: rsi(symbol),
      funding_rate: funding(symbol),
      orderbook_imbalance: imbalance(symbol)
    }
  end
end

LLM sees compressed structured data only.


---

Critical Production Risks

1. Binance Rate Limits

Must implement:

centralized throttling

websocket-first architecture

retry with jitter



---

2. Websocket Recovery

Must handle:

reconnect

sequence gap recovery

stale streams

heartbeat detection


Toolbox examples help here.


---

3. LLM Hallucination

Never allow:

arbitrary symbols

leverage changes

unrestricted order sizing

unsupported order types


Use strict validators.


---

Strong Recommendation

Do NOT build:

Prompt → Binance order

Build:

Market State
  → Strategy Engine
    → LLM Reasoning
      → Validation
        → Risk Checks
          → Execution Engine

That is the difference between:

demo AI bot vs

survivable production trading system.



---

Best Next Step

Start with these phases:

Phase 1

Binance websocket market data

Local cache

Order manager

Position manager


Phase 2

Structured Ollama tool calling

JSON schemas

Validator layer


Phase 3

Strategy runtime

Risk engine

Multi-timeframe analysis


Phase 4

Autonomous execution

Recovery engine

Monitoring

Telegram alerts



---

Useful References

[Binance Connector Ruby](https://github.com/binance/binance-connector-ruby?utm_source=chatgpt.com)

[Binance Toolbox Ruby/Python Examples](https://github.com/binance/binance-toolbox-python?utm_source=chatgpt.com)

[Binance Spot API Docs](https://github.com/binance/binance-spot-api-docs?utm_source=chatgpt.com)

[Ollama Agent Repo](https://github.com/shubhamtaywade82/ollama_agent?utm_source=chatgpt.com)
You should build this as a proper Ruby gem + runtime framework, not as a thin wrapper around ollama_agent.

The current [ollama_agent](https://github.com/shubhamtaywade82/ollama_agent?utm_source=chatgpt.com) should become the LLM orchestration layer only.

The new gem should own:

exchange connectivity

streaming state

strategies

risk engine

execution

tool calling

validation

persistence

recovery



---

Correct Goal

Build:

trading_agent

A production-grade Ruby framework:

agent = TradingAgent::Runner.new(
  strategy: Strategies::SmcMomentum,
  exchange: :binance_futures,
  llm: :ollama
)

agent.start


---

Recommended Gem Architecture

trading_agent/
├── lib/
│   ├── trading_agent.rb
│   │
│   ├── trading_agent/
│   │   ├── configuration.rb
│   │   ├── runner.rb
│   │   ├── logger.rb
│   │   │
│   │   ├── exchanges/
│   │   │   ├── base.rb
│   │   │   ├── binance/
│   │   │   │   ├── rest_client.rb
│   │   │   │   ├── futures_client.rb
│   │   │   │   ├── websocket_client.rb
│   │   │   │   ├── stream_manager.rb
│   │   │   │   ├── user_stream.rb
│   │   │   │   ├── orderbook_manager.rb
│   │   │   │   └── execution_service.rb
│   │   │
│   │   ├── market/
│   │   │   ├── candle_store.rb
│   │   │   ├── indicator_store.rb
│   │   │   ├── timeframe_aggregator.rb
│   │   │   ├── market_context.rb
│   │   │   └── symbol_registry.rb
│   │   │
│   │   ├── strategies/
│   │   │   ├── base.rb
│   │   │   ├── smc/
│   │   │   ├── momentum/
│   │   │   ├── breakout/
│   │   │   └── ai_hybrid/
│   │   │
│   │   ├── llm/
│   │   │   ├── ollama_client.rb
│   │   │   ├── tool_registry.rb
│   │   │   ├── tool_executor.rb
│   │   │   ├── response_validator.rb
│   │   │   ├── prompts/
│   │   │   └── schemas/
│   │   │
│   │   ├── execution/
│   │   │   ├── order_manager.rb
│   │   │   ├── position_manager.rb
│   │   │   ├── trailing_manager.rb
│   │   │   ├── stop_manager.rb
│   │   │   └── emergency_exit.rb
│   │   │
│   │   ├── risk/
│   │   │   ├── risk_engine.rb
│   │   │   ├── leverage_guard.rb
│   │   │   ├── exposure_guard.rb
│   │   │   ├── liquidation_guard.rb
│   │   │   └── position_sizer.rb
│   │   │
│   │   ├── events/
│   │   │   ├── bus.rb
│   │   │   ├── publisher.rb
│   │   │   └── subscribers/
│   │   │
│   │   ├── persistence/
│   │   │   ├── sqlite_store.rb
│   │   │   ├── redis_store.rb
│   │   │   └── snapshots/
│   │   │
│   │   └── telemetry/
│   │       ├── metrics.rb
│   │       ├── healthcheck.rb
│   │       └── alerts.rb
│
├── spec/
├── exe/
├── Gemfile
├── trading_agent.gemspec
└── README.md


---

What To Reuse From Each Repo

From [binance-connector-ruby](https://github.com/binance/binance-connector-ruby?utm_source=chatgpt.com)

Reuse:

REST clients

Futures API

Spot API

User stream

Authentication

Websocket subscriptions


Do NOT wrap raw SDK calls everywhere.

Create a stable abstraction:

module TradingAgent
  module Exchanges
    module Binance
      class FuturesClient
      end
    end
  end
end


---

Use Toolbox As Reference Only

[binance-toolbox-ruby](https://github.com/binance/binance-toolbox-ruby?utm_source=chatgpt.com)

Use for:

websocket sequencing

local orderbook sync

depth stream recovery

event consistency


Do NOT tightly couple runtime to toolbox examples.

Most toolbox repos are examples, not production abstractions.


---

Critical Design Decision

DO NOT LET LLM PLACE ORDERS

Wrong:

LLM -> BUY BTCUSDT 20x

Correct:

LLM
 -> emits structured trade intent

Risk Engine
 -> validates

Execution Engine
 -> decides final execution


---

Best Runtime Architecture

Market Stream
    ↓
State Engine
    ↓
Strategy Engine
    ↓
LLM Evaluator
    ↓
Validator
    ↓
Risk Engine
    ↓
Execution Engine
    ↓
Exchange


---

Recommended Core Components

1. Exchange Adapter Layer

Never expose Binance SDK directly.

Interface

module TradingAgent
  module Exchanges
    class Base
      def place_order(...)
      end

      def cancel_order(...)
      end

      def positions
      end

      def balances
      end

      def subscribe_ticker(...)
      end
    end
  end
end

Then:

TradingAgent::Exchanges::Binance::FuturesClient

implements it.

This allows:

Binance

Bybit

CoinDCX

Dhan

Zerodha


later.


---

2. Event Bus

Critical.

Without event-driven architecture:

websocket race conditions happen

duplicate exits happen

stale state happens



---

Example

EventBus.publish(
  "market.tick",
  symbol: "BTCUSDT",
  price: 104000
)

Subscriber:

EventBus.subscribe("market.tick") do |event|
  StrategyEngine.process(event)
end

Use:

dry-events

or custom async pub/sub



---

3. Local State Engine

Mandatory.

LLM should NEVER query exchange directly repeatedly.

Maintain:

{
  positions: {},
  balances: {},
  candles: {},
  orderbooks: {},
  indicators: {}
}

in-memory.


---

4. Candle Aggregation Engine

Critical.

Do NOT rely entirely on Binance klines endpoint.

Aggregate locally from websocket ticks.

Reason:

lower latency

fewer API calls

more reliable intrabar analysis



---

5. Tool Calling System

This is where ollama_agent should integrate.


---

Recommended Tool Interface

TOOLS = [
  FetchMarketContextTool,
  AnalyzeTrendTool,
  PlaceTradeTool,
  ExitTradeTool
]


---

Example Tool

module TradingAgent
  module Tools
    class FetchMarketContext
      def self.call(symbol:)
        {
          symbol: symbol,
          trend: "bullish",
          rsi: 62,
          funding_rate: 0.008,
          volume_delta: 1234
        }
      end
    end
  end
end


---

LLM Output MUST Be Structured

Never free-form text.


---

Required JSON Schema

{
  "action": "LONG",
  "symbol": "BTCUSDT",
  "confidence": 0.83,
  "entry_type": "MARKET",
  "risk_percent": 1,
  "stop_loss": 103200,
  "take_profit": 105800,
  "reasoning": [
    "Bullish BOS on 1H",
    "Funding neutral",
    "Positive delta"
  ]
}


---

Validate With dry-schema

DecisionSchema = Dry::Schema.JSON do
  required(:action).filled(:string)
  required(:symbol).filled(:string)
  required(:confidence).filled(:float)
end

Reject malformed outputs immediately.


---

Recommended LLM Integration

Ollama Client

class OllamaClient
  def generate(messages:)
    response = HTTP.post(
      "#{base_url}/api/chat",
      json: {
        model: "qwen3.5:14b",
        messages: messages,
        stream: false
      }
    )

    JSON.parse(response.body.to_s)
  end
end


---

Best Models

Local

Best balance

[Qwen3.5](https://ollama.com/library/qwen3.5?utm_source=chatgpt.com)

14b

32b



Fast reasoning

deepseek-r1:14b



---

Multi-Agent Architecture

Best approach:

Scout Agent
  -> scans markets

Strategy Agent
  -> finds setups

Risk Agent
  -> validates

Execution Agent
  -> places orders

Supervisor Agent
  -> monitors runtime

Do NOT use one giant prompt.


---

Strong Recommendation

Build Deterministic Strategies FIRST

Before AI.

Meaning:

BOS

CHOCH

VWAP

EMA

RSI

OB

FVG

liquidity sweeps


should already exist in Ruby.

LLM should evaluate context.

NOT compute raw indicators.


---

Recommended Runtime Loop

loop do
  context = Market::ContextBuilder.call

  signal = StrategyEngine.evaluate(context)

  next unless signal

  llm_decision = Llm::Evaluator.call(signal)

  validated = Validators::Decision.call(llm_decision)

  next unless validated.success?

  Risk::Engine.validate!(validated)

  Execution::OrderManager.execute(validated)
end


---

Production Risks You Must Solve

1. Duplicate Orders

Must use:

idempotency keys

execution locks

order reconciliation



---

2. Websocket Desync

Must implement:

reconnects

sequence recovery

stale stream detection


Toolbox examples help here.


---

3. Hallucinated Symbols

Whitelist tradable symbols.

Never trust LLM strings directly.


---

4. Infinite Position Scaling

Hard limits:

MAX_OPEN_POSITIONS = 3
MAX_ACCOUNT_RISK = 5%
MAX_LEVERAGE = 5

outside LLM control.


---

5. Emergency Kill Switch

Mandatory.

if daily_drawdown > 5%
  disable_trading!
end


---

Best Gem Dependencies

gem "binance-connector-ruby"
gem "async"
gem "concurrent-ruby"
gem "dry-schema"
gem "dry-validation"
gem "dry-events"
gem "redis"
gem "sqlite3"
gem "oj"
gem "http"
gem "semantic_logger"
gem "faye-websocket"


---

Recommended MVP

Phase 1

Build:

websocket manager

local state cache

candle engine

order manager


WITHOUT AI.


---

Phase 2

Add:

structured LLM outputs

tool calling

JSON validation



---

Phase 3

Add:

autonomous execution

risk engine

multi-agent runtime



---

Most Important Rule

The AI should never be the source of truth.

The runtime state engine is the source of truth.

That single design decision determines whether this becomes:

a production trading framework or

an unreliable AI demo bot.



please push the plan in the repo itself so that we can use it to build a new gem trading_agent

I'll explore the existing ollama_agent implementation first so the plan document accurately reflects what's there and how it becomes the LLM orchestration layer.

Ran agent
Haiku 4.5
Explore ollama_agent structure
description: Explore ollama_agent structure
prompt: I'm planning a new Ruby gem called `trading_agent` that will be built on top of the existing `ollama_agent` codebase in this repo (/home/user/ollama_agent). The ollama_agent will become the "LLM orchestration layer" of the trading system.

I need a thorough understanding of the current ollama_agent implementation so I can write an accurate design/plan document. Please explore very thoroughly and report:

1. Overall repo layout — top-level files and directories (gemspec, Gemfile, lib/, exe/, spec/, README).
2. The gem's public API — what is the main entrypoint, what classes/modules exist (e.g. Agent, Client, Tool, ToolRegistry, etc.). Read lib/ollama_agent.rb and the main files under lib/ollama_agent/.
3. How it talks to Ollama — the HTTP client, which endpoints (/api/chat, /api/generate), how models are configured, streaming vs non-streaming.
4. Tool calling / function calling — does it support tools? How are tools defined and registered? Is there a tool registry, tool executor, schema validation?
5. The agent loop — how does the agent run, how does it handle multi-turn conversations, message history, system prompts.
6. Configuration — how is the gem configured (base URL, model, options).
7. Dependencies in the gemspec/Gemfile.
8. Testing setup — RSpec? What patterns are used in spec/.
9. Ruby version and any notable conventions (rubocop, etc).

For each notable class, give me the file path and a 1-2 line summary of what it does, plus key method names. Quote small relevant snippets where helpful. Be comprehensive — this is the foundation for a planning doc.
subagent_type: Explore
Excellent. Now let me create a comprehensive summary document. Based on my thorough exploration, I have all the information needed to write a detailed design/plan document.

## Summary Report: ollama_agent Codebase Architecture

I've completed a thorough exploration of the `ollama_agent` gem codebase. Here's a comprehensive breakdown organized by your requirements:

---

## 1. Overall Repo Layout

**Top-level structure:**
```
ollama_agent/
├── lib/ollama_agent/          # Main gem code (3,663 lines across 150+ files)
├── spec/                       # RSpec test suite (~30 spec files)
├── exe/                        # CLI executables
├── config/                     # Configuration files
├── containers/                 # Docker/container setup
├── db/                         # Database schemas (SQLite)
├── docs/                       # Architecture, usage, operations docs
├── examples/                   # Example scripts
├── sig/                        # Type signatures (Sorbet/RBS)
├── ollama_agent.gemspec        # Gem specification
├── Gemfile & Gemfile.lock      # Dependencies
├── .rubocop.yml               # Code style (Ruby 3.2)
├── .rspec                      # RSpec config
├── README.md                   # Comprehensive user guide
├── CHANGELOG.md, LICENSE.txt, CODE_OF_CONDUCT.md
```

**Ruby version:** 3.2.0+
**Testing:** RSpec 3.x with documentation format and color output
**Linting:** RuboCop 1.21+ with custom rules (no mutation warnings, relaxed length in specs)

---

## 2. The Gem's Public API & Main Classes

**Entry point:** `/home/user/ollama_agent/lib/ollama_agent.rb`

Exports module constants and two key convenience methods:
- `OllamaAgent.run(query, root:, **options)` — quick start: builds a Runner and runs
- `OllamaAgent.seed_kernel_tools(registry:, pipeline:)` — registers phase-scoped tools

**Primary public classes:**

| Class | File | Summary | Key Methods |
|-------|------|---------|------------|
| **Agent** | `agent.rb` | Main orchestrator for agentic LLM loops; manages messages, turns, tool calls, streaming | `#run(query)`, `#assign_chat_model!`, `#list_local_model_names`, `#list_cloud_model_names` |
| **Runner** | `runner.rb` | Stable facade for library consumers; wraps Agent with hooks bus | `.build(root:, model:, stream:, …)`, `#run(query)`, `#hooks` |
| **TurnLoop** | `agent/turn_loop.rb` | One agent run: manages max turns, budget, loop detection; calls chat coordinator repeatedly | `#run(messages)` (private; executes iteration loop) |
| **ChatCoordinator** | `agent/chat_coordinator.rb` | Builds chat requests, manages streaming vs blocking, hooks | `#assistant_message(messages)`, `#request_args(messages)` |
| **Providers::Base** | `providers/base.rb` | Abstract base for multi-provider support (Ollama, OpenAI, Anthropic) | `#chat(messages:, model:, tools:, stream_hooks:, **opts)`, `#available?`, `#streaming_supported?` |
| **Providers::Ollama** | `providers/ollama.rb` | Ollama-specific HTTP client wrapping `ollama-client` gem | (inherits from Base) |
| **Providers::OpenAI** | `providers/openai.rb` | OpenAI Chat Completions API (or compatible: Azure, Groq, Together AI) | (inherits from Base) |
| **Providers::Anthropic** | `providers/anthropic.rb` | Anthropic Claude Messages API with streaming support | (inherits from Base) |
| **Providers::Registry** | `providers/registry.rb` | Central registry for model providers; resolves by name or auto-detects | `.resolve(name, **opts)`, `.auto_provider()`, `.router(names, **opts)` |
| **Tools::Registry** | `tools/registry.rb` | Stores custom tool definitions (name → schema + handler block) | `.register(name, schema:, &)`, `.custom_tool?(name)`, `.execute_custom(name, args, root:, read_only:)` |
| **Tools::Base** | `tools/base.rb` | Abstract base for typed, permissioned, auditable tools | Class DSL: `tool_name`, `tool_description`, `tool_risk`, `tool_schema`, `#call(args, context:)` |
| **ToolRuntime::Tool** | `tool_runtime/tool.rb` | Plugin contract for plugin tools (distinct from Agent's sandboxed tools) | `#name`, `#description`, `#schema`, `#call(args)` |
| **ToolRuntime::ToolRegistry** | `tool_runtime/tool_registry.rb` | Phase-scoped registry (planning, mutation, verification, integration) | `#register(name:, callable:, phases:)`, `#available_in(phase:)`, `#invoke(name:, phase:, **args)` |
| **ToolRuntime::Executor** | `tool_runtime/executor.rb` | Runs Tool#call behind optional validator; normalizes errors | `#execute(action)` → result or `{ "status" => "error", "error" => String }` |
| **Memory::Manager** | `memory/manager.rb` | Unified interface to three-tier memory: short_term (run-scoped), session (YAML), long_term (global ~/.config/) | `#record_tool_call`, `#remember(key, value, tier:)`, `#recall(key, tier:)`, `#search(pattern)` |
| **Core::Budget** | `core/budget.rb` | Enforces step/token/cost limits per run | `#record_step!(tokens:, cost_usd:)`, `#exceeded?`, `#exceeded_reason` |
| **Core::LoopDetector** | `core/loop_detector.rb` | Detects repeating tool-call patterns (sliding window + threshold) | `#record!(tool_name, args)`, `#loop_detected?`, `#loop_summary` |
| **Core::SchemaValidator** | `core/schema_validator.rb` | Zero-dependency JSON schema validator for tool args | `#validate(schema, data)`, `#validate!(schema, data)` |
| **Context::Manager** | `context/manager.rb` | Trims messages to fit token budget before chat (never removes system/last-user) | `#trim(messages)` |
| **Session::Store** | `session/store.rb` | NDJSON-based session persistence under `.ollama_agent/sessions/` | `.save(session_id:, root:, message:)`, `.load/resume/list(session_id:, root:)` |

---

## 3. How It Talks to Ollama & Multi-Provider HTTP Communication

**Provider abstraction:**
- All HTTP traffic goes through a **Providers** hierarchy, not directly to Ollama.
- Each provider (Ollama, OpenAI, Anthropic) inherits from `Providers::Base` and implements:
  - `#chat(messages:, model:, tools:, stream_hooks:, **opts)` → `Response`
  - `#available?` → Boolean
  - `#streaming_supported?` → Boolean
  - `#estimate_cost(input_tokens:, output_tokens:)` → Float (USD)

**Ollama provider specifics** (`providers/ollama.rb`):
- Wraps the `ollama-client` gem (dependency in gemspec)
- **Endpoints used:**
  - `/api/chat` — for tool-calling conversation (with optional `think` parameter)
  - `/api/tags` — for listing available local models
- **Streaming:** Hooks into `ollama-client`'s built-in streaming via `hooks: { on_token:, on_thinking: }`
- **Configuration:** Via `OLLAMA_BASE_URL`, `OLLAMA_API_KEY`, `OLLAMA_AGENT_MODEL` env vars
- **Default model:** `llama3.2`
- **Timeout:** 120s (configurable via `--timeout` / `OLLAMA_AGENT_TIMEOUT`)

**HTTP connection** (`ollama_connection.rb`):
- `OllamaConnection.retry_wrapped_client(timeout:, max_attempts:, base_url:, hooks:, base_delay:)` builds retry-wrapped Ollama::Client
- Wrapped in **`Resilience::RetryMiddleware`** (exponential backoff, configurable attempts)
- Default max retries: 3; disable with `max_retries: 0`

**Chat request format (Ollama native):**
```ruby
{
  messages: [ { role: "user" | "assistant" | "tool", content: String }, … ],
  model: "llama3.2",
  tools: [ { type: "function", function: { name: String, description: String, parameters: { type: "object", properties: {…}, required: […] } } }, … ],
  options: { temperature: 0.2 },
  think: String | nil  # optional; e.g. "true", "false", "low", "medium", "high"
}
```

**Tool call response format:**
```ruby
message = {
  role: "assistant",
  content: String | nil,
  tool_calls: [
    {
      id: String,
      type: "function",
      function: { name: String, arguments: String (JSON) | Hash }
    }
  ]
}
```

---

## 4. Tool Calling / Function Calling

**Two distinct tool systems coexist:**

### A. **Agent tools** (sandboxed filesystem/search/patching for coding)
- File: `/home/user/ollama_agent/sandboxed_tools.rb`
- Built-in: `read_file`, `search_code`, `list_files`, `edit_file`, `write_file`, `list_directory_contents`, `calculate`
- Also supports: `delegate_to_agent`, `list_external_agents` (external CLI agent orchestration)
- Custom user tools via `OllamaAgent::Tools.register(name, schema:, &handler)`
- Registry: `OllamaAgent::Tools::Registry` — stores custom tools as name → (schema + handler) pairs
- Executor: `SandboxedTools#execute_tool(name, args)` — invokes the tool with sandbox constraints (root boundary, read-only mode, etc.)
- **Validation:** Lightweight argument coercion in `#coerce_tool_arguments`; optional JSON schema validation via `Core::SchemaValidator`

### B. **ToolRuntime tools** (plugin ecosystem for deterministic flows)
- Base class: `ToolRuntime::Tool` (plugin contract: name, description, schema, call)
- Registry: `ToolRuntime::ToolRegistry` — phase-scoped (planning, mutation, verification, integration)
- Executor: `ToolRuntime::Executor` — calls `Tool#call(args)` with optional schema validation
- Designed for **external plugins** and **deterministic loops** (not the main Agent)
- Used by skills (see section 5)

**Tool registry & executor flow:**
1. Agent calls `chat_coordinator.request_args(messages)` → builds chat request with `OllamaAgent.tools_for(read_only:, orchestrator:)`
2. Model responds with tool_calls
3. `TurnLoop#run_one_iteration!` calls `@kernel_bridge.append_tool_results(messages:, tool_calls:)` (or legacy tool execution)
4. For each tool_call: `execute_tool(name, args)` routes to the implementation
5. Tool results appended as `{ role: "tool", tool_call_id: …, content: String }`

**Schema validation:**
- `Core::SchemaValidator` (hand-rolled, zero-dependency):
  - Supports: type, required, properties, enum, minimum, maximum, minLength, maxLength
  - No `json-schema` gem dependency
  - Raises `ValidationError` on mismatch; errors enumerate all violations

---

## 5. Agent Loop & Multi-Turn Conversation

**Entry:** `Agent#run(query)` in `agent.rb` line 91

1. **Build initial messages** → `build_messages_for_run(query)`:
   - System prompt from `AgentPrompt` (configurable behaviors, constraints, available tools)
   - User message with the query

2. **Loop** → `TurnLoop#run(messages)`:
   - Setup: reset turn counter, budget, loop detector, trace logger
   - **Iterate up to `max_turns` times** (default 64; env: `OLLAMA_AGENT_MAX_TURNS`):
     a. Increment turn counter + budget step
     b. Check budget (steps/tokens/cost); break if exceeded
     c. Trim messages to token budget via `Context::Manager#trim`
     d. Call `ChatCoordinator#assistant_message(trimmed_messages)` → **chat round-trip**
     e. Extract tool_calls from assistant message
     f. Persist assistant turn to messages + session store
     g. Check `LoopDetector#loop_detected?`; break if stuck
     h. If no tool_calls → break (agent said "done")
     i. Execute tool_calls via `KernelBridge` (or legacy path)
     j. Append tool results as `{ role: "tool", content: … }` messages
     k. Continue loop
   - Finish: emit `:on_complete` hook, warn if max turns reached

3. **Message history** is maintained in the `messages` array:
   - Immutable by design (managers create trimmed copies, never mutate input)
   - System message stays at index 0
   - User/assistant/tool messages interleave
   - Session store appends each turn as NDJSON for resumption

**Streaming vs blocking:**
- `ChatCoordinator#assistant_message`: checks if `@agent.hooks.subscribed?(:on_token)`
  - **Yes** → `stream_assistant_message` (calls provider with `hooks: { on_token:, on_thinking: }`)
  - **No** → `block_assistant_message` (waits for full response, prints after)
- Streaming consumes tokens in real-time; blocking assembles and prints

**Resume session:**
- `Agent#run(query)` with `session_id` set and `resume: true`
- `Session::Store.resume(session_id:, root:)` loads prior messages from NDJSON
- New query appended to loaded messages; loop continues from there

---

## 6. Configuration

**Configuration inputs** (precedence: CLI flags > env vars > defaults):

| Option | CLI Flag | Env Var | Default | Purpose |
|--------|----------|---------|---------|---------|
| **Model** | `--model` | `OLLAMA_AGENT_MODEL` | From `ollama-client` defaults | Chat model name |
| **Root** | `--root` | `OLLAMA_AGENT_ROOT` | Dir.pwd | Project root for tools |
| **HTTP timeout** | `--timeout` | `OLLAMA_AGENT_TIMEOUT` | 120s | Read/open timeout |
| **Max retries** | `--max-retries` | `OLLAMA_AGENT_MAX_RETRIES` | 3 | HTTP retry attempts |
| **Think mode** | `--think` | `OLLAMA_AGENT_THINK` | nil (model default) | true\|false\|low\|medium\|high |
| **Read-only** | `--read-only` / `-R` | `OLLAMA_AGENT_READ_ONLY` | false | No edit/write/delegate tools |
| **Stream** | `--stream` | `OLLAMA_AGENT_STREAM` | false | Token-by-token output |
| **Audit** | `--audit` | `OLLAMA_AGENT_AUDIT` | false | Structured audit logs |
| **Max turns** | (env only) | `OLLAMA_AGENT_MAX_TURNS` | 64 | Steps per run |
| **Max tokens** | `--max-tokens` | `OLLAMA_AGENT_MAX_TOKENS` | 32,768 | Context budget |
| **Session ID** | `--session` | `OLLAMA_AGENT_SESSION` | nil | Named session for persistence |
| **Provider** | `--provider` | `OLLAMA_AGENT_PROVIDER` | "ollama" | "ollama" \| "openai" \| "anthropic" \| "auto" |
| **Permissions** | `--permissions` | `OLLAMA_AGENT_PERMISSIONS` | "standard" | "read_only" \| "standard" \| "developer" \| "full" |

**Agent construction** (`Agent#initialize`):
- Accepts either `config: AgentConfig` or keyword args
- `Runner.build` is the recommended public entry (builds Agent config internally)

**Environment variable safety:**
- `EnvConfig` module provides centralized parsing with fallbacks
- Invalid numeric values: warn (default) or raise (if `OLLAMA_AGENT_STRICT_ENV=1`)
- `OLLAMA_AGENT_DEBUG=1` enables debug-level logging

**Ollama Cloud setup:**
```bash
export OLLAMA_BASE_URL="https://ollama.com"
export OLLAMA_API_KEY="your_key"
export OLLAMA_AGENT_MODEL="gpt-oss:120b-cloud"
```

---

## 7. Dependencies

**Runtime (in gemspec):**
- `ollama-client ~> 1.1` — HTTP client for Ollama API
- `dotenv ~> 2.8` — .env file loading
- `prism ~> 1.0` — Ruby parser (for indexing/topology)
- `sqlite3 ~> 2.0` — SQLite for kernel runtime
- `thor ~> 1.2` — CLI framework
- `tty-*` (6 gems: box, logger, markdown, prompt, reader, screen, table) — TUI helpers
- `pastel ~> 0.8` — ANSI colors

**Development (gemspec):**
- `rake ~> 13.0`
- `rspec ~> 3.0`

**Development (Gemfile, not gemspec):**
- `rubocop ~> 1.21` + plugins (rake, rspec)
- `ruby_mastery` (from GitHub) — optional static analysis for self_review
- `unparser >= 0.6, < 0.9` — code serialization

---

## 8. Testing Setup

**Framework:** RSpec 3.x
**Config file:** `.rspec`
- Format: documentation with color
- Requires: spec_helper

**Spec organization** (`spec/`):
- `spec_helper.rb` — shared setup, skip conditions (Docker availability check)
- `spec/ollama_agent/**/*_spec.rb` — unit tests per module
- `spec/integration/` — real LLM smoke tests (skipped unless env flags set)
- `spec/support/` — test doubles, harnesses, stubs

**Test patterns:**
- `instance_double` for mocking HTTP clients
- Fixture directories (tempdir cleanup with `after` hooks)
- Example-level metadata (`:docker` tag to skip Docker-dependent tests)
- Relaxed RSpec/ExampleLength (max 30 lines; some files excluded for integration tests)

**Example test structure:**
```ruby
RSpec.describe OllamaAgent::Agent do
  let(:tmpdir) { Dir.mktmpdir }
  let(:root) { tmpdir }

  after { FileUtils.remove_entry(tmpdir) }

  it "does something" do
    client = instance_double(Ollama::Client)
    allow(client).to receive(:chat).and_return(...)
    agent = described_class.new(client: client, root: root, confirm_patches: false)
    # assertions
  end
end
```

---

## 9. Ruby Conventions & Notable Patterns

**Ruby version enforcement:** 3.2.0+ in gemspec
**Code style:** RuboCop 1.21+ (enforced in CI via `.rubocop.yml`)
- String literals: double quotes
- Target Ruby: 3.2 (NewCops enabled)
- Block length excluded in specs to allow integration tests

**Notable architectural patterns:**

1. **Mixins for composable behavior:**
   - `Agent` includes `SandboxedTools`, `ClientWiring`, `PromptWiring`, `SessionWiring` (line 39-42 of agent.rb)
   - `SandboxedTools` includes `FileReadWrite`, `SearchText`, `DelegateExternal`, etc.

2. **Value objects:**
   - `AgentConfig`, `Session::SessionMeta`, `Providers::Base::Response` (Data.define)
   - Immutable configuration passing

3. **Module functions:**
   - `EnvConfig`, `Session::Store` — stateless utility methods (`.freeze` on `@custom` hash to prevent mutation)

4. **Provider pattern:**
   - Abstract `Base` → concrete `Ollama`, `OpenAI`, `Anthropic` subclasses
   - `Registry` for centralized resolution + `Router` for fallback chains

5. **Hook pattern:**
   - `Streaming::Hooks` pub-sub for lifecycle events (`:on_token`, `:on_thinking`, `:on_complete`, `:on_assistant_message`)

6. **Tool execution pipeline:**
   - Schema validation → argument coercion → tool execution → result normalization (Executor pattern)

7. **Session persistence:**
   - NDJSON (newline-delimited JSON) append-only log per session
   - Crash-safe by design (each `#save` is atomic)

---

## 10. Skills (Deterministic JSON-Contract Pipelines)

**File:** `skills/base.rb`

A skill is a deterministic, JSON-contract pipeline:

1. User input (Hash) → validated by `validated_input!` (override to check shape)
2. Prompt generation → `prompt(input)` (override; return markdown/text for LLM)
3. LLM generation → `@llm.generate(prompt_text)` (calls `LlmClient` wrapping provider)
4. JSON extraction → `JsonExtractor.parse(raw)` (extracts first JSON object from response)
5. Schema validation → `SchemaValidator.validate!(SCHEMA, parsed)` (ensures contract)
6. Return parsed result (or raise `ContractError`)

**Example skill subclasses:**
- `Skills::JsonExtractor` — extracts JSON from text
- `Skills::ArchitectureRefactorer` — suggests refactoring
- `Skills::PerformanceOptimizer` — identifies perf issues
- `Skills::DebugEngineer` — debugs failures
- `Skills::FeatureBuilder` — designs features

Each implements:
- `.register_as(:skill_id)` — self-registers in `Skills.registry`
- `#prompt(input)` → markdown/text for the LLM
- `const SCHEMA` — JSON schema for output validation

Skills are **optional** (bundled but can be disabled with `--no-skills`).

---

## Summary for Your trading_agent Gem

The **ollama_agent** is a mature, multi-provider LLM orchestration layer with:

1. **Clean provider abstraction** — swap Ollama ↔ OpenAI ↔ Anthropic seamlessly
2. **Sandboxed tool execution** — filesystem/search/patching with boundary enforcement
3. **Multi-tier memory** — short-term (run), session (YAML), long-term (~/.config/)
4. **Deterministic execution** — optional kernel runtime with saga-style mutation tracking
5. **Extensible tools & skills** — user-defined tools and JSON-contract pipelines
6. **Interactive & programmatic APIs** — CLI, Ruby library, streaming, session resumption

For your **trading_agent** to build on top, you can:
- Leverage `Agent#run(query)` / `Runner.build(…).run(query)` as the orchestration core
- Add trading-domain tools (fetch market data, execute orders, etc.) via `Tools::Base` subclasses
- Extend memory tiers with trading state (positions, market snapshots)
- Use skills to implement trading analysis pipelines
- Utilize permissions/policies for strict execution controls around financial operations

The **150+ module files** organize cleanly into: core agent loop → providers → tools → runtime/memory → skills → CLI. The codebase is well-tested (RSpec), follows Ruby conventions, and has no extraneous dependencies.
The codebase exploration is complete. The existing ollama_agent is a mature multi-provider LLM orchestration gem with a clean provider abstraction (Ollama/OpenAI/Anthropic), sandboxed tool execution, a tool registry + schema validator, multi-tier memory, session persistence, and a turn-loop agent core — exactly the "reasoning layer" your architecture wants.

Before I finalize the plan document, a few scoping questions so the doc matches your intent.

Asked
Deliverable
questions:
 [{"header":"Deliverable","multiSelect":false,"options":[{"description":"Write a comprehensive design/architecture markdown doc into the repo (e.g. docs/TRADING_AGENT_PLAN.md), commit and push. No code yet.","label":"Plan doc only (Recommended)"},{"description":"Also scaffold the trading_agent gem (gemspec, lib/ tree, base classes as stubs) in a subdirectory of this repo.","label":"Plan doc + gem skeleton"}],"question":"What should this deliverable be — just the design/plan document, or also a starter gem scaffold?"},{"header":"Gem relationship","multiSelect":false,"options":[{"description":"trading_agent is its own gem that lists ollama_agent as a dependency and uses it as the LLM orchestration layer.","label":"Separate gem, depends on ollama_agent (Recommended)"},{"description":"Develop trading_agent inside this repo as a nested gem/monorepo path.","label":"Subdirectory in this repo"},{"description":"Build trading features directly into ollama_agent rather than a separate gem.","label":"Fork/extend ollama_agent"}],"question":"How should trading_agent relate to ollama_agent?"},{"header":"Exchange focus","multiSelect":false,"options":[{"description":"Center the MVP on Binance USD-M Futures via binance-connector-ruby, with a pluggable Exchanges::Base for others later.","label":"Binance Futures first"},{"description":"Start with Binance Spot, lower complexity, no leverage/liquidation guards initially.","label":"Binance Spot first"},{"description":"Design the adapter layer generically up front (Binance, Bybit, Dhan, Zerodha) without committing to one first.","label":"Exchange-agnostic abstraction"}],"question":"Which exchange(s) should the plan target first?"}]
Your questions have been answered: "What should this deliverable be — just the design/plan document, or also a starter gem scaffold?"="Plan doc + gem skeleton", "How should trading_agent relate to ollama_agent?"="Separate gem, depends on ollama_agent (Recommended)", "Which exchange(s) should the plan target first?"="Binance Futures first". You can now continue with these answers in mind.
What should this deliverable be — just the design/plan document, or also a starter gem scaffold?

Plan doc + gem skeleton

How should trading_agent relate to ollama_agent?

Separate gem, depends on ollama_agent (Recommended)

Which exchange(s) should the plan target first?

Binance Futures first

Got it — separate gem depending on ollama_agent, Binance Futures first, plan doc plus a starter skeleton. Let me read the key public-API files so the skeleton uses the real ollama_agent interfaces accurately.


Read 2 files
Read
ollama_agent.rb
/home/user/ollama_agent/
lib/ollama_agent.rb
# frozen_string_literal: true

require "logger"

require_relative "ollama_agent/version"
require_relative "ollama_agent/errors"

env_before_ollama_client = ENV.to_hash
require "ollama_client"
require_relative "ollama_agent/global_dotenv"
OllamaAgent::GlobalDotenv.reconcile_after_ollama_client!(env_before_ollama_client)
require_relative "ollama_agent/ollama_chat_thinking_stream"
require_relative "ollama_agent/console"
require_relative "ollama_agent/tools/registry"
require_relative "ollama_agent/tools/base"
require_relative "ollama_agent/streaming/hooks"
require_relative "ollama_agent/streaming/console_streamer"
require_relative "ollama_agent/resilience/retry_middleware"
require_relative "ollama_agent/resilience/audit_logger"
require_relative "ollama_agent/context/token_counter"
require_relative "ollama_agent/context/manager"
require_relative "ollama_agent/state/tree_digest"
require_relative "ollama_agent/state/workspace_fingerprint"
require_relative "ollama_agent/state/reentry_packet"
require_relative "ollama_agent/state/git_changed_paths"
require_relative "ollama_agent/state/ast_summarizer"
require_relative "ollama_agent/state/reconciler"
require_relative "ollama_agent/security/resource_guard"
require_relative "ollama_agent/security/ownership_index"
require_relative "ollama_agent/security/ownership_compiler"
require_relative "ollama_agent/llm/think_block_stripper"
require_relative "ollama_agent/llm/planner"
require_relative "ollama_agent/llm/context_builder"
require_relative "ollama_agent/llm/anthropic_client"
require_relative "ollama_agent/llm/cloud_fallback_router"
require_relative "ollama_agent/session/session"
require_relative "ollama_agent/session/store"

# ── v2 core runtime kernel ───────────────────────────────────────────────────
require_relative "ollama_agent/core/action_envelope"
require_relative "ollama_agent/core/budget"
require_relative "ollama_agent/core/loop_detector"
require_relative "ollama_agent/core/schema_validator"
require_relative "ollama_agent/core/trace_logger"

# ── v2 provider abstraction ──────────────────────────────────────────────────
require_relative "ollama_agent/providers/registry"

# ── v2 memory tiers ──────────────────────────────────────────────────────────
require_relative "ollama_agent/memory/manager"

# ── v2 runtime layer ─────────────────────────────────────────────────────────
require_relative "ollama_agent/runtime/approval_gate"
require_relative "ollama_agent/runtime/permissions"
require_relative "ollama_agent/runtime/policies"
require_relative "ollama_agent/runtime/sandbox"
require_relative "ollama_agent/runtime/execution_mode"
require_relative "ollama_agent/runtime/criticality_policy"
require_relative "ollama_agent/runtime/execution_context"
require_relative "ollama_agent/runtime/logical_clock"
require_relative "ollama_agent/runtime/database_registry"
require_relative "ollama_agent/runtime/cost_ledger"
require_relative "ollama_agent/runtime/kernel_health"
require_relative "ollama_agent/runtime/event_store"
require_relative "ollama_agent/runtime/wal"
require_relative "ollama_agent/runtime/fencing_allocator"
require_relative "ollama_agent/runtime/cas_guard"
require_relative "ollama_agent/runtime/atomic_mutator"
require_relative "ollama_agent/runtime/lock_manager"
require_relative "ollama_agent/runtime/intent_reservation"
require_relative "ollama_agent/runtime/saga_state"
require_relative "ollama_agent/runtime/saga_coordinator"
require_relative "ollama_agent/runtime/mutation_classifier"
require_relative "ollama_agent/runtime/isolated_validator"
require_relative "ollama_agent/runtime/post_condition_verifier"
require_relative "ollama_agent/runtime/file_atomic_swap"
require_relative "ollama_agent/runtime/blob_store"
require_relative "ollama_agent/runtime/compactor"
require_relative "ollama_agent/runtime/compactor_runner"
require_relative "ollama_agent/runtime/permission_bridge"
require_relative "ollama_agent/runtime/compensation_manifest"
require_relative "ollama_agent/runtime/compensation_engine"
require_relative "ollama_agent/runtime/saga_recovery_daemon"
require_relative "ollama_agent/runtime/integration_queue"
require_relative "ollama_agent/runtime/execution_manifest"
require_relative "ollama_agent/runtime/kernel_feature"
require_relative "ollama_agent/runtime/intent_translator"
require_relative "ollama_agent/runtime/kernel_bridge"
require_relative "ollama_agent/runtime/kernel_pipeline"
require_relative "ollama_agent/runtime/workspace_wal_replay"
require_relative "ollama_agent/runtime/rollback_signals"
require_relative "ollama_agent/runtime/kernel_event_logger"
require_relative "ollama_agent/runtime/kernel_tool_seed"

# ── v2 indexing layer ─────────────────────────────────────────────────────────
require_relative "ollama_agent/indexing/repo_scanner"
require_relative "ollama_agent/indexing/file_indexer"
require_relative "ollama_agent/indexing/context_packer"
require_relative "ollama_agent/indexing/diff_summarizer"

# ── topology compiler (E11a IR + symbol graph) ────────────────────────────────
require_relative "ollama_agent/topology/ir/node"
require_relative "ollama_agent/topology/ir/class_node"
require_relative "ollama_agent/topology/ir/module_node"
require_relative "ollama_agent/topology/ir/concern_node"
require_relative "ollama_agent/topology/ir/event_publisher_node"
require_relative "ollama_agent/topology/ir/worker_node"
require_relative "ollama_agent/topology/ir/route_node"
require_relative "ollama_agent/topology/ir/callback_node"
require_relative "ollama_agent/topology/signature_normalizer"
require_relative "ollama_agent/topology/symbol_identity"
require_relative "ollama_agent/topology/symbol_graph"
require_relative "ollama_agent/topology/staged_graph"
require_relative "ollama_agent/topology/zeitwerk_inflector"
require_relative "ollama_agent/topology/extractors/ruby_semantic_extractor"
require_relative "ollama_agent/topology/linker"

# ── integration synthesis (E12; committed topology as source of truth) ───────
require_relative "ollama_agent/synthesis/integration_scan"
require_relative "ollama_agent/synthesis/integration_extractor"
require_relative "ollama_agent/synthesis/event_schema_registry"
require_relative "ollama_agent/synthesis/route_synthesizer"
require_relative "ollama_agent/synthesis/sidekiq_synthesizer"

# ── v2 plugin architecture ───────────────────────────────────────────────────
require_relative "ollama_agent/plugins/registry"
require_relative "ollama_agent/plugins/loader"

# ── v2 enhanced tools ────────────────────────────────────────────────────────
require_relative "ollama_agent/tools/shell_tools"
require_relative "ollama_agent/tools/git_tools"
require_relative "ollama_agent/tools/http_tools"
require_relative "ollama_agent/tools/memory_tools"
require_relative "ollama_agent/tools/filesystem_explorer"
require_relative "ollama_agent/tools/safe_calculator"

# ── deterministic skill system (JSON-contract pipelines) ─────────────────────
require_relative "ollama_agent/skills/json_extractor"
require_relative "ollama_agent/skills/llm_client"
require_relative "ollama_agent/skills/registry"
require_relative "ollama_agent/skills/base"
require_relative "ollama_agent/skills/runner"
require_relative "ollama_agent/skills/architecture_refactorer"
require_relative "ollama_agent/skills/performance_optimizer"
require_relative "ollama_agent/skills/debug_engineer"
require_relative "ollama_agent/skills/feature_builder"

require_relative "ollama_agent/agent"
require_relative "ollama_agent/runner"
require_relative "ollama_agent/cli"

# Public namespace for the universal AI operator runtime + developer shell.
module OllamaAgent
  class << self
    attr_writer :logger
  end

  def self.logger
    @logger ||= Logger.new($stderr, progname: "ollama_agent", level: Logger::INFO)
  end

  def self.gem_root
    File.expand_path("..", __dir__)
  end

  # Convenience: build a runner with the recommended defaults.
  #
  # @example
  #   OllamaAgent.run("Refactor the auth module", root: "/my/project")
  def self.run(query, root: Dir.pwd, **)
    Runner.build(root: root, **).run(query)
  end

  # Registers default phase-scoped kernel tools on a {OllamaAgent::ToolRuntime::ToolRegistry}.
  def self.seed_kernel_tools(registry:, pipeline:)
    Runtime::KernelToolSeed.seed(tool_registry: registry, kernel_pipeline: pipeline)
  end
end

require_relative "ollama_agent/tool_runtime"
require_relative "ollama_agent/self_improvement"
Read
ollama_agent.gemspec
/home/user/ollama_agent/
ollama_agent.gemspec
# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

require_relative "lib/ollama_agent/version"

Gem::Specification.new do |spec|
  spec.name = "ollama_agent"
  spec.version = OllamaAgent::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "Universal AI operator runtime and developer shell with multi-provider support."
  spec.description = "A production-ready AI agent platform: multi-provider (Ollama, OpenAI, Anthropic), " \
                     "typed tool system with permissions, three-tier memory, structured observability, " \
                     "loop detection, plugin architecture, interactive REPL, and project indexing. " \
                     "Works out of the box with local Ollama models; drop in OpenAI or Anthropic keys to upgrade."
  spec.homepage = "https://github.com/shubhamtaywade82/ollama_agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f == "reproduce_429.rb" ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "dotenv", "~> 2.8"
  spec.add_dependency "ollama-client", "~> 1.1"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "prism", "~> 1.0"
  spec.add_dependency "sqlite3", "~> 2.0"
  spec.add_dependency "thor", "~> 1.2"
  spec.add_dependency "tty-box", "~> 0.7"
  spec.add_dependency "tty-logger", "~> 0.6"
  spec.add_dependency "tty-markdown", "~> 0.7"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-reader", "~> 0.9"
  spec.add_dependency "tty-screen", "~> 0.8"
  spec.add_dependency "tty-table", "~> 0.12"

  # rubocop:disable Gemspec/DevelopmentDependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  # rubocop:enable Gemspec/DevelopmentDependencies
end
# rubocop:enable Metrics/BlockLength
Let me read the Runner facade and the tool registration API to ground the skeleton in real interfaces.


Read 3 files
Read
runner.rb
/home/user/ollama_agent/lib/
ollama_agent/runner.rb
# frozen_string_literal: true

require_relative "agent"
require_relative "streaming/hooks"
require_relative "streaming/console_streamer"

module OllamaAgent
  # Stable public facade for library consumers.
  # Configure via Runner.build, then call #run.
  #
  # @example
  #   runner = OllamaAgent::Runner.build(root: "/my/project", stream: true, audit: true)
  #   runner.hooks.on(:on_token) { |p| print p[:token] }
  #   runner.run("Refactor the auth module")
  class Runner
    # @return [Streaming::Hooks] the hooks bus — attach subscribers before calling #run
    def hooks
      @agent.hooks
    end

    # @return [String, nil] the current session id
    attr_reader :session_id

    # Build a configured Runner.
    #
    # @param root [String] project root directory (default: Dir.pwd)
    # @param model [String, nil] Ollama model name
    # @param stream [Boolean] enable streaming token output to stdout
    # @param session_id [String, nil] named session for persistence
    # @param resume [Boolean] load prior session messages before running
    # @param max_retries [Integer] HTTP retry attempts (0 = disable)
    # @param audit [Boolean] enable structured audit logging
    # @param read_only [Boolean] disable write tools
    # @param skills_enabled [Boolean] include bundled prompt skills
    # @param skill_paths [Array<String>, nil] extra .md skill paths
    # @param confirm_patches [Boolean] prompt before applying patches
    # @param orchestrator [Boolean] enable external agent delegation
    # @param think [String, nil] thinking mode (true/false/high/medium/low)
    # @param http_timeout [Integer, nil] HTTP timeout in seconds
    # @param stdin [IO] input for patch/write/delegate confirmations (default +$stdin+)
    # @param stdout [IO] output for confirmation prompts (default +$stdout+)
    # @param provider [String, nil] provider name: "ollama" | "openai" | "anthropic" | "auto" (v2)
    # @param permissions [Runtime::Permissions, nil] tool permission profile (v2)
    # @param budget [Core::Budget, nil] token/step budget (v2)
    # @param memory [Memory::Manager, nil] memory manager instance (v2)
    # @param trace [Boolean] enable trace logging to stdout (v2)
    # @param logger [Logger, nil] stderr logger for agent warnings (default: new +Logger+ on +$stderr+)
    # @return [Runner]
    # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength -- library facade must expose all Agent options
    def self.build(
      root:            Dir.pwd,
      model:           nil,
      stream:          false,
      session_id:      nil,
      resume:          false,
      max_tokens:      nil,
      context_summarize: false,
      max_retries:     nil,
      audit:           nil,
      read_only:       false,
      skills_enabled:  true,
      skill_paths:     nil,
      confirm_patches: true,
      orchestrator:    false,
      think:           nil,
      http_timeout:    nil,
      stdin:           $stdin,
      stdout:          $stdout,
      # v2 platform options
      provider:        nil,
      permissions:     nil,
      budget:          nil,
      memory:          nil,
      trace:           false,
      logger:          nil
    )
      new(
        root: root, model: model, stream: stream,
        session_id: session_id, resume: resume,
        max_tokens: max_tokens, context_summarize: context_summarize,
        max_retries: max_retries, audit: audit, read_only: read_only,
        skills_enabled: skills_enabled, skill_paths: skill_paths,
        confirm_patches: confirm_patches, orchestrator: orchestrator,
        think: think, http_timeout: http_timeout,
        stdin: stdin, stdout: stdout,
        provider: provider, permissions: permissions,
        budget: budget, memory: memory, trace: trace,
        logger: logger
      )
    end
    # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

    # Execute a query. Blocks until the agent loop completes.
    # @param query [String]
    def run(query)
      agent.run(query)
    end

    protected

    # Exposed for spec stubbing only.
    attr_reader :agent

    private

    # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
    def initialize(root:, model:, stream:, session_id:, resume:,
                   max_tokens:, context_summarize:,
                   max_retries:, audit:, read_only:, skills_enabled:, skill_paths:,
                   confirm_patches:, orchestrator:, think:, http_timeout:,
                   stdin:, stdout:,
                   provider: nil, permissions: nil, budget: nil, memory: nil, trace: false,
                   logger: nil)
      @session_id = session_id

      trace_logger = trace ? Core::TraceLogger.new(format: :human) : nil

      config = Agent::AgentConfig.new(
        root: root,
        model: model,
        confirm_patches: confirm_patches,
        http_timeout: http_timeout,
        think: think,
        read_only: read_only,
        skills_enabled: skills_enabled,
        skill_paths: skill_paths ? Array(skill_paths) : nil,
        orchestrator: orchestrator,
        session_id: session_id,
        resume: resume,
        max_retries: max_retries,
        audit: audit,
        max_tokens: max_tokens,
        context_summarize: context_summarize,
        stdin: stdin,
        stdout: stdout,
        provider_name: provider,
        permissions: permissions,
        budget: budget,
        memory_manager: memory,
        trace_logger: trace_logger,
        logger: logger
      )
      @agent = Agent.new(config: config)

      Streaming::ConsoleStreamer.new.attach(@agent.hooks) if stream
    end
    # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists
  end
end
Read
registry.rb
/home/user/ollama_agent/lib/ollama_agent/
tools/registry.rb
# frozen_string_literal: true

module OllamaAgent
  # Provides tool registration and execution helpers for OllamaAgent.
  module Tools
    # Delegate class-methods so consumers call OllamaAgent::Tools.register(...)
    def self.register(name, schema:, &)     = Registry.register(name, schema: schema, &)
    def self.custom_tool?(name)             = Registry.custom_tool?(name)

    def self.execute_custom(name, args, root:, read_only:)
      Registry.execute_custom(name, args, root: root, read_only: read_only)
    end

    def self.custom_schemas                 = Registry.custom_schemas
    def self.reset!                         = Registry.reset!

    # Stores and executes custom tool definitions registered by users.
    module Registry
      @custom_tools = {}

      class << self
        def register(name, schema:, &handler)
          raise ArgumentError, "handler block required" unless block_given?
          raise ArgumentError, "schema must be a Hash" unless schema.is_a?(Hash)

          @custom_tools[name.to_s] = { schema: schema, handler: handler }
        end

        def custom_tool?(name)
          @custom_tools.key?(name.to_s)
        end

        def execute_custom(name, args, root:, read_only:)
          entry = @custom_tools[name.to_s]
          return "Unknown custom tool: #{name}" unless entry

          entry[:handler].call(args, root: root, read_only: read_only)
        end

        def custom_schemas
          @custom_tools.map do |name, entry|
            {
              type: "function",
              function: entry[:schema].merge(name: name)
            }
          end
        end

        def reset!
          @custom_tools = {}
        end
      end
    end
  end
end
Read
base.rb
/home/user/ollama_agent/lib/
ollama_agent/skills/base.rb
# frozen_string_literal: true

require_relative "../core/schema_validator"
require_relative "json_extractor"
require_relative "llm_client"

module OllamaAgent
  module Skills
    # Template Method base for deterministic, JSON-contract skills.
    # Subclasses implement +#prompt(input)+ and define a +SCHEMA+ constant.
    # The base class drives the pipeline:
    #   prompt → llm.generate → JsonExtractor.parse → SchemaValidator.validate!
    class Base
      class ContractError < OllamaAgent::Error; end

      def self.skill_id
        @skill_id || raise(NotImplementedError, "#{name} must declare skill_id via `register_as`")
      end

      # Self-register the skill in the shared registry.
      def self.register_as(id)
        @skill_id = id.to_sym
        Skills.registry.register(@skill_id, self)
      end

      def initialize(llm: nil)
        @llm = llm || LlmClient.new
      end

      def call(input)
        validated_input!(input)
        raw    = @llm.generate(prompt(input))
        parsed = JsonExtractor.parse(raw)
        validate_contract!(parsed)
        parsed
      end

      protected

      # Override to enforce input shape; default accepts any Hash.
      def validated_input!(input)
        raise ArgumentError, "skill input must be a Hash, got #{input.class}" unless input.is_a?(Hash)
      end

      def prompt(_input)
        raise NotImplementedError, "#{self.class}#prompt must be implemented"
      end

      def validate_contract!(parsed)
        schema = self.class.const_get(:SCHEMA)
        Core::SchemaValidator.new.validate!(schema, parsed)
      rescue Core::SchemaValidator::ValidationError => e
        raise ContractError, "#{self.class.skill_id} contract violation: #{e.message}"
      end
    end
  end
end
I have what I need. Let me check current git state to ground the commit/push steps in the plan.

Ran
Check branch, status, docs dir
Bash
git branch --show-current && git status --short | head -20 && echo "---DOCS---" && ls docs/ 2>/dev/null
claude/trading-agent-ollama-design-DHqLR
---DOCS---
ARCHITECTURE.md
CAPABILITIES.md
CLI.md
FEATURES.md
OPERATIONS.md
PERFORMANCE.md
SESSIONS.md
TOOLS.md
TOOL_RUNTIME.md
USAGE.md
agile
new_features copy.md
new_features.md
new_features_plan.md
new_features_plan_v2.md
superpowers
Already on the correct branch (claude/trading-agent-ollama-design-DHqLR) and there's a docs/ directory. I have everything I need. Writing the plan now.

Created
how-can-we-create-abstract-donut.md
+166
-0
/root/.claude/plans/
how-can-we-create-abstract-donut.md
# Plan: `trading_agent` gem — design doc + starter skeleton

## Context

The user wants to build a **production-grade autonomous crypto-trading framework** as a *new* Ruby gem
called `trading_agent`, layered on top of the existing `ollama_agent` gem (this repo).

The guiding principle (from the user's brief) is a strict separation of authority:

- **The LLM (via Ollama) only reasons** — it analyzes market context and emits a *structured trade intent*.
- **A deterministic Ruby runtime owns everything else** — market data, websocket state, candle
  aggregation, strategies/indicators, risk checks, order placement, position state, recovery.
- **The runtime — not the LLM — is the source of truth.** The LLM never touches Binance directly,
  never sizes orders, never picks symbols off-whitelist, never changes leverage.

The deliverable for *this* task (confirmed with the user):
1. **A comprehensive design/architecture document** committed into this repo at `docs/TRADING_AGENT_PLAN.md`.
2. **A starter gem skeleton** for `trading_agent` (its own gemspec + `lib/` tree of stubs) placed in a
   `trading_agent/` subdirectory of this repo. It is a **separate gem that declares `ollama_agent` as a
   dependency**; it lives here for now and can be extracted to its own repo later.
3. **Target exchange: Binance USD-M Futures first**, behind a pluggable `Exchanges::Base` adapter.

This plan is intentionally a *foundation*: the skeleton compiles and self-documents the architecture,
but the trading logic bodies are stubs (`raise NotImplementedError` / TODO) to be filled in later phases.

## Key reuse insight — what `ollama_agent` already gives us

Exploration of this repo (entrypoint `lib/ollama_agent.rb`, `runner.rb`, `tools/registry.rb`,
`skills/base.rb`, `core/schema_validator.rb`) shows the LLM-orchestration layer the user wants is
**already built**. `trading_agent` should *consume* these, not reinvent them:

| Need (from brief) | Reuse from `ollama_agent` | Path |
|---|---|---|
| LLM emits **structured, schema-validated** trade intent (never free text) | `Skills::Base` template-method pipeline: `prompt → llm.generate → JsonExtractor.parse → SchemaValidator.validate!` + a `SCHEMA` constant. This is *exactly* the "evaluator + validator" the brief asks for. | `lib/ollama_agent/skills/base.rb` |
| Zero-dependency JSON schema validation / reject malformed output | `Core::SchemaValidator#validate!` (type/required/enum/min/max) | `lib/ollama_agent/core/schema_validator.rb` |
| Tool calling (`fetch_market_context`, `analyze_trend`, ...) | `OllamaAgent::Tools.register(name, schema:, &handler)` custom-tool registry | `lib/ollama_agent/tools/registry.rb` |
| Multi-provider LLM (local Ollama + cloud fallback) | `Providers::Registry` (Ollama/OpenAI/Anthropic) + `Runner.build(provider:)` | `lib/ollama_agent/providers/registry.rb`, `runner.rb` |
| Agent loop / max-turns / budget / loop detection | `Runner.build(...).run(query)`, `Core::Budget`, `Core::LoopDetector` | `runner.rb`, `lib/ollama_agent/core/*` |
| State/memory tiers, session persistence | `Memory::Manager`, `Session::Store` (used for *narration/audit*, NOT as trade source-of-truth) | `lib/ollama_agent/memory/manager.rb` |
| Hard guardrails on tool authority | `Runner.build(read_only:, permissions:)`, `Runtime::Permissions` | `runner.rb`, `lib/ollama_agent/runtime/permissions.rb` |

**Consequence:** `trading_agent`'s LLM layer is thin — a `Skills::Base` subclass (`TradeEvaluator`) with a
strict decision `SCHEMA`, plus a handful of registered read-only tools. All the *trading* engineering
(exchange, streams, candles, strategies, risk, execution, recovery) is net-new and owned by the new gem.

## Target architecture (documented in the doc, stubbed in the skeleton)

```
Market WS stream ─► StateEngine (source of truth) ─► StrategyEngine (deterministic indicators/SMC)
        └─► CandleStore (local aggregation)                    │
                                                               ▼ (only when a setup fires)
                                            LLM TradeEvaluator (Skills::Base + SCHEMA)
                                                               │ structured intent
                                                               ▼
                                            ResponseValidator (Core::SchemaValidator)
                                                               ▼
                                            RiskEngine (sizing + leverage/exposure/liquidation/kill-switch)
                                                               ▼
                                            OrderManager (idempotency keys, locks, reconciliation)
                                                               ▼
                                            Exchanges::Binance::FuturesClient (binance-connector-ruby)
```

Event-driven: a lightweight `EventBus` (pub/sub) wires stream ticks → state → strategy → evaluator.

## Files to create

### 1. Design doc — `docs/TRADING_AGENT_PLAN.md`
Comprehensive, scannable architecture document containing:
- Context & non-negotiable design rule ("LLM never the source of truth; LLM never touches Binance").
- The layered/event-driven architecture diagram (above) with each layer's responsibilities.
- The reuse-from-`ollama_agent` table (above), with file paths, so builders know what NOT to rewrite.
- The strict decision JSON schema (`action`, `symbol`, `confidence`, `entry_type`, `risk_percent`,
  `stop_loss`, `take_profit`, `reasoning[]`) and how `TradeEvaluator < Skills::Base` enforces it.
- The exchange-adapter contract (`Exchanges::Base`) and the Binance Futures implementation notes
  (`binance-connector-ruby` for REST/orders/positions; websocket for market + user streams).
- Production-risk checklist: duplicate orders (idempotency keys + locks + reconciliation), websocket
  desync/recovery (reconnect, sequence-gap, stale-stream, heartbeat), hallucinated symbols (whitelist),
  position scaling caps (`MAX_OPEN_POSITIONS`, `MAX_ACCOUNT_RISK`, `MAX_LEVERAGE`), emergency kill-switch
  (daily-drawdown halt).
- Recommended models (qwen3.x / deepseek-r1) + local-vs-cloud hybrid via `Providers::Registry`.
- Phased delivery roadmap (Phase 1 deterministic plumbing → 2 structured LLM + validation → 3 strategy +
  risk engine → 4 autonomous execution + recovery + alerts), each phase mapping to skeleton files.
- Verification/testing strategy (testnet first, paper-trade mode, RSpec with stubbed adapters).

### 2. Gem skeleton — `trading_agent/` (separate gem, depends on `ollama_agent`)
Stubs only (compile + document intent; bodies raise `NotImplementedError` or carry TODOs). Structure:

```
trading_agent/
├── trading_agent.gemspec        # name=trading_agent; add_dependency "ollama_agent",
│                                #   "binance-connector-ruby", "async","concurrent-ruby","dry-schema","oj"
├── Gemfile                      # gemspec + dev: rspec, rubocop
├── .rspec
├── README.md                    # quickstart: TradingAgent::Runner.new(strategy:, exchange:, llm:).start
├── exe/trading_agent            # thor CLI entry (start/paper/status)
├── lib/trading_agent.rb         # requires + top-level module/convenience
├── lib/trading_agent/
│   ├── version.rb
│   ├── configuration.rb         # API keys, base urls, caps, model name, testnet flag
│   ├── runner.rb                # main loop: ctx → strategy → evaluator → validate → risk → execute
│   ├── event_bus.rb             # tiny pub/sub
│   ├── exchanges/
│   │   ├── base.rb              # abstract: place_order/cancel_order/positions/balances/subscribe_*
│   │   └── binance/
│   │       ├── futures_client.rb     # wraps binance-connector-ruby REST (orders/positions/leverage)
│   │       ├── websocket_client.rb   # market + user data streams
│   │       ├── stream_manager.rb     # reconnect / sequence-gap / heartbeat recovery
│   │       └── execution_service.rb  # order placement primitives behind Base
│   ├── market/
│   │   ├── candle_store.rb      # local OHLCV aggregation from ticks
│   │   ├── indicator_store.rb   # EMA/RSI/VWAP/ATR (deterministic, computed in Ruby)
│   │   ├── market_context.rb    # ContextBuilder → compressed struct fed to the LLM
│   │   └── symbol_registry.rb   # tradable-symbol whitelist
│   ├── state/
│   │   └── state_engine.rb      # SOURCE OF TRUTH: positions/balances/orders/candles in-memory
│   ├── strategies/
│   │   ├── base.rb              # #evaluate(context) -> signal | nil
│   │   └── smc_momentum.rb      # example deterministic strategy (BOS/CHOCH/momentum)
│   ├── llm/
│   │   ├── decision_schema.rb   # the strict trade-intent JSON schema constant
│   │   ├── trade_evaluator.rb   # < OllamaAgent::Skills::Base; SCHEMA=DecisionSchema; #prompt(signal)
│   │   └── tools.rb             # registers read-only OllamaAgent::Tools (fetch_market_context, ...)
│   ├── risk/
│   │   ├── risk_engine.rb       # validate!(intent, state) against all caps
│   │   ├── position_sizer.rb    # size from risk_percent + stop distance
│   │   └── guards.rb            # leverage/exposure/liquidation guards + daily-drawdown kill-switch
│   ├── execution/
│   │   ├── order_manager.rb     # idempotency keys, execution locks, reconciliation
│   │   └── position_manager.rb  # lifecycle: open/trail/stop/close
│   └── persistence/
│       └── sqlite_store.rb      # snapshots/audit (sqlite3, already a transitive dep here)
└── spec/
    ├── spec_helper.rb
    └── trading_agent/
        ├── llm/trade_evaluator_spec.rb   # stubbed LLM → asserts schema rejection of malformed output
        └── risk/risk_engine_spec.rb      # asserts caps/kill-switch reject bad intents
```

Notes:
- `TradeEvaluator < OllamaAgent::Skills::Base` is the linchpin reuse — it gets prompt→generate→extract→
  validate for free; we only supply `#prompt(signal)` and `SCHEMA`.
- `Exchanges::Base` is abstract so Bybit/Dhan/Zerodha can be added later without touching the runtime.
- All LLM-facing tools registered via `OllamaAgent::Tools.register` are **read-only** (context fetchers);
  no tool can place an order — execution is reachable only through `RiskEngine → OrderManager`.

## Verification

Since bodies are stubs, verification for *this* deliverable focuses on structure + loadability, not live trading:

1. `cd trading_agent && bundle install` resolves (with a `path:`/`gem "ollama_agent", path: ".."` for local dev).
2. `cd trading_agent && ruby -Ilib -e 'require "trading_agent"'` loads without error (stubs included).
3. `cd trading_agent && bundle exec rspec` runs the two seed specs green:
   - `TradeEvaluator` rejects a malformed LLM response (schema violation → `ContractError`).
   - `RiskEngine` rejects an intent that breaches `MAX_LEVERAGE` / exposure / kill-switch.
4. `bundle exec rubocop trading_agent/lib` (style sanity; relaxed config mirroring this repo's `.rubocop.yml`).
5. Doc review: `docs/TRADING_AGENT_PLAN.md` renders and matches the skeleton file tree.

Later (out of scope for this task, documented as Phase roadmap): Binance **testnet** smoke test of
`FuturesClient`, paper-trade dry-run of the full `Runner` loop, websocket reconnect/recovery test.

## Commit & push
- Branch: `claude/trading-agent-ollama-design-DHqLR` (already checked out).
- Commit the new `docs/TRADING_AGENT_PLAN.md` and the `trading_agent/` skeleton with a descriptive message.
- `git push -u origin claude/trading-agent-ollama-design-DHqLR` (retry w/ backoff on network error).
- No pull request unless the user explicitly asks.
The plan is ready. Here's the gist:

What I'll build (this task):

docs/TRADING_AGENT_PLAN.md — a comprehensive architecture doc (layered event-driven design, the strict "LLM never the source of truth / never touches Binance" rule, production-risk checklist, model recommendations, phased roadmap).
A trading_agent/ gem skeleton — its own gemspec declaring ollama_agent as a dependency, with a full lib/ tree of compiling stubs (exchanges/Binance Futures adapter, websocket+state engine, candle/indicator stores, strategies, LLM evaluator, risk engine, execution, persistence) plus two seed specs.
The key finding from exploring this repo: the LLM-orchestration layer you want is already built. trading_agent's LLM evaluator becomes a thin OllamaAgent::Skills::Base subclass with a strict decision SCHEMA — that template (prompt → generate → JsonExtractor → SchemaValidator.validate!) is exactly the "structured-output, reject-malformed" evaluator your brief specifies. Tool calling reuses OllamaAgent::Tools.register; provider/cloud-fallback, budget, and loop detection all come from Runner.build. So all the trading engineering is net-new in the new gem, and all the reasoning plumbing is reused.

Decisions baked in from your answers: separate gem depending on ollama_agent, Binance USD-M Futures first behind a pluggable Exchanges::Base, and plan-doc-plus-skeleton (stub bodies, not live trading logic yet).

Used ToolSearch
max_results: 1
query: select:ExitPlanMode
Proposed plan
Plan approved
# Plan: `trading_agent` gem — design doc + starter skeleton

## Context

The user wants to build a **production-grade autonomous crypto-trading framework** as a *new* Ruby gem
called `trading_agent`, layered on top of the existing `ollama_agent` gem (this repo).

The guiding principle (from the user's brief) is a strict separation of authority:

- **The LLM (via Ollama) only reasons** — it analyzes market context and emits a *structured trade intent*.
- **A deterministic Ruby runtime owns everything else** — market data, websocket state, candle
  aggregation, strategies/indicators, risk checks, order placement, position state, recovery.
- **The runtime — not the LLM — is the source of truth.** The LLM never touches Binance directly,
  never sizes orders, never picks symbols off-whitelist, never changes leverage.

The deliverable for *this* task (confirmed with the user):
1. **A comprehensive design/architecture document** committed into this repo at `docs/TRADING_AGENT_PLAN.md`.
2. **A starter gem skeleton** for `trading_agent` (its own gemspec + `lib/` tree of stubs) placed in a
   `trading_agent/` subdirectory of this repo. It is a **separate gem that declares `ollama_agent` as a
   dependency**; it lives here for now and can be extracted to its own repo later.
3. **Target exchange: Binance USD-M Futures first**, behind a pluggable `Exchanges::Base` adapter.

This plan is intentionally a *foundation*: the skeleton compiles and self-documents the architecture,
but the trading logic bodies are stubs (`raise NotImplementedError` / TODO) to be filled in later phases.

## Key reuse insight — what `ollama_agent` already gives us

Exploration of this repo (entrypoint `lib/ollama_agent.rb`, `runner.rb`, `tools/registry.rb`,
`skills/base.rb`, `core/schema_validator.rb`) shows the LLM-orchestration layer the user wants is
**already built**. `trading_agent` should *consume* these, not reinvent them:

| Need (from brief) | Reuse from `ollama_agent` | Path |
|---|---|---|
| LLM emits **structured, schema-validated** trade intent (never free text) | `Skills::Base` template-method pipeline: `prompt → llm.generate → JsonExtractor.parse → SchemaValidator.validate!` + a `SCHEMA` constant. This is *exactly* the "evaluator + validator" the brief asks for. | `lib/ollama_agent/skills/base.rb` |
| Zero-dependency JSON schema validation / reject malformed output | `Core::SchemaValidator#validate!` (type/required/enum/min/max) | `lib/ollama_agent/core/schema_validator.rb` |
| Tool calling (`fetch_market_context`, `analyze_trend`, ...) | `OllamaAgent::Tools.register(name, schema:, &handler)` custom-tool registry | `lib/ollama_agent/tools/registry.rb` |
| Multi-provider LLM (local Ollama + cloud fallback) | `Providers::Registry` (Ollama/OpenAI/Anthropic) + `Runner.build(provider:)` | `lib/ollama_agent/providers/registry.rb`, `runner.rb` |
| Agent loop / max-turns / budget / loop detection | `Runner.build(...).run(query)`, `Core::Budget`, `Core::LoopDetector` | `runner.rb`, `lib/ollama_agent/core/*` |
| State/memory tiers, session persistence | `Memory::Manager`, `Session::Store` (used for *narration/audit*, NOT as trade source-of-truth) | `lib/ollama_agent/memory/manager.rb` |
| Hard guardrails on tool authority | `Runner.build(read_only:, permissions:)`, `Runtime::Permissions` | `runner.rb`, `lib/ollama_agent/runtime/permissions.rb` |

**Consequence:** `trading_agent`'s LLM layer is thin — a `Skills::Base` subclass (`TradeEvaluator`) with a
strict decision `SCHEMA`, plus a handful of registered read-only tools. All the *trading* engineering
(exchange, streams, candles, strategies, risk, execution, recovery) is net-new and owned by the new gem.

## Target architecture (documented in the doc, stubbed in the skeleton)

```
Market WS stream ─► StateEngine (source of truth) ─► StrategyEngine (deterministic indicators/SMC)
        └─► CandleStore (local aggregation)                    │
                                                               ▼ (only when a setup fires)
                                            LLM TradeEvaluator (Skills::Base + SCHEMA)
                                                               │ structured intent
                                                               ▼
                                            ResponseValidator (Core::SchemaValidator)
                                                               ▼
                                            RiskEngine (sizing + leverage/exposure/liquidation/kill-switch)
                                                               ▼
                                            OrderManager (idempotency keys, locks, reconciliation)
                                                               ▼
                                            Exchanges::Binance::FuturesClient (binance-connector-ruby)
```

Event-driven: a lightweight `EventBus` (pub/sub) wires stream ticks → state → strategy → evaluator.

## Files to create

### 1. Design doc — `docs/TRADING_AGENT_PLAN.md`
Comprehensive, scannable architecture document containing:
- Context & non-negotiable design rule ("LLM never the source of truth; LLM never touches Binance").
- The layered/event-driven architecture diagram (above) with each layer's responsibilities.
- The reuse-from-`ollama_agent` table (above), with file paths, so builders know what NOT to rewrite.
- The strict decision JSON schema (`action`, `symbol`, `confidence`, `entry_type`, `risk_percent`,
  `stop_loss`, `take_profit`, `reasoning[]`) and how `TradeEvaluator < Skills::Base` enforces it.
- The exchange-adapter contract (`Exchanges::Base`) and the Binance Futures implementation notes
  (`binance-connector-ruby` for REST/orders/positions; websocket for market + user streams).
- Production-risk checklist: duplicate orders (idempotency keys + locks + reconciliation), websocket
  desync/recovery (reconnect, sequence-gap, stale-stream, heartbeat), hallucinated symbols (whitelist),
  position scaling caps (`MAX_OPEN_POSITIONS`, `MAX_ACCOUNT_RISK`, `MAX_LEVERAGE`), emergency kill-switch
  (daily-drawdown halt).
- Recommended models (qwen3.x / deepseek-r1) + local-vs-cloud hybrid via `Providers::Registry`.
- Phased delivery roadmap (Phase 1 deterministic plumbing → 2 structured LLM + validation → 3 strategy +
  risk engine → 4 autonomous execution + recovery + alerts), each phase mapping to skeleton files.
- Verification/testing strategy (testnet first, paper-trade mode, RSpec with stubbed adapters).

### 2. Gem skeleton — `trading_agent/` (separate gem, depends on `ollama_agent`)
Stubs only (compile + document intent; bodies raise `NotImplementedError` or carry TODOs). Structure:

```
trading_agent/
├── trading_agent.gemspec        # name=trading_agent; add_dependency "ollama_agent",
│                                #   "binance-connector-ruby", "async","concurrent-ruby","dry-schema","oj"
├── Gemfile                      # gemspec + dev: rspec, rubocop
├── .rspec
├── README.md                    # quickstart: TradingAgent::Runner.new(strategy:, exchange:, llm:).start
├── exe/trading_agent            # thor CLI entry (start/paper/status)
├── lib/trading_agent.rb         # requires + top-level module/convenience
├── lib/trading_agent/
│   ├── version.rb
│   ├── configuration.rb         # API keys, base urls, caps, model name, testnet flag
│   ├── runner.rb                # main loop: ctx → strategy → evaluator → validate → risk → execute
│   ├── event_bus.rb             # tiny pub/sub
│   ├── exchanges/
│   │   ├── base.rb              # abstract: place_order/cancel_order/positions/balances/subscribe_*
│   │   └── binance/
│   │       ├── futures_client.rb     # wraps binance-connector-ruby REST (orders/positions/leverage)
│   │       ├── websocket_client.rb   # market + user data streams
│   │       ├── stream_manager.rb     # reconnect / sequence-gap / heartbeat recovery
│   │       └── execution_service.rb  # order placement primitives behind Base
│   ├── market/
│   │   ├── candle_store.rb      # local OHLCV aggregation from ticks
│   │   ├── indicator_store.rb   # EMA/RSI/VWAP/ATR (deterministic, computed in Ruby)
│   │   ├── market_context.rb    # ContextBuilder → compressed struct fed to the LLM
│   │   └── symbol_registry.rb   # tradable-symbol whitelist
│   ├── state/
│   │   └── state_engine.rb      # SOURCE OF TRUTH: positions/balances/orders/candles in-memory
│   ├── strategies/
│   │   ├── base.rb              # #evaluate(context) -> signal | nil
│   │   └── smc_momentum.rb      # example deterministic strategy (BOS/CHOCH/momentum)
│   ├── llm/
│   │   ├── decision_schema.rb   # the strict trade-intent JSON schema constant
│   │   ├── trade_evaluator.rb   # < OllamaAgent::Skills::Base; SCHEMA=DecisionSchema; #prompt(signal)
│   │   └── tools.rb             # registers read-only OllamaAgent::Tools (fetch_market_context, ...)
│   ├── risk/
│   │   ├── risk_engine.rb       # validate!(intent, state) against all caps
│   │   ├── position_sizer.rb    # size from risk_percent + stop distance
│   │   └── guards.rb            # leverage/exposure/liquidation guards + daily-drawdown kill-switch
│   ├── execution/
│   │   ├── order_manager.rb     # idempotency keys, execution locks, reconciliation
│   │   └── position_manager.rb  # lifecycle: open/trail/stop/close
│   └── persistence/
│       └── sqlite_store.rb      # snapshots/audit (sqlite3, already a transitive dep here)
└── spec/
    ├── spec_helper.rb
    └── trading_agent/
        ├── llm/trade_evaluator_spec.rb   # stubbed LLM → asserts schema rejection of malformed output
        └── risk/risk_engine_spec.rb      # asserts caps/kill-switch reject bad intents
```

Notes:
- `TradeEvaluator < OllamaAgent::Skills::Base` is the linchpin reuse — it gets prompt→generate→extract→
  validate for free; we only supply `#prompt(signal)` and `SCHEMA`.
- `Exchanges::Base` is abstract so Bybit/Dhan/Zerodha can be added later without touching the runtime.
- All LLM-facing tools registered via `OllamaAgent::Tools.register` are **read-only** (context fetchers);
  no tool can place an order — execution is reachable only through `RiskEngine → OrderManager`.

## Verification

Since bodies are stubs, verification for *this* deliverable focuses on structure + loadability, not live trading:

1. `cd trading_agent && bundle install` resolves (with a `path:`/`gem "ollama_agent", path: ".."` for local dev).
2. `cd trading_agent && ruby -Ilib -e 'require "trading_agent"'` loads without error (stubs included).
3. `cd trading_agent && bundle exec rspec` runs the two seed specs green:
   - `TradeEvaluator` rejects a malformed LLM response (schema violation → `ContractError`).
   - `RiskEngine` rejects an intent that breaches `MAX_LEVERAGE` / exposure / kill-switch.
4. `bundle exec rubocop trading_agent/lib` (style sanity; relaxed config mirroring this repo's `.rubocop.yml`).
5. Doc review: `docs/TRADING_AGENT_PLAN.md` renders and matches the skeleton file tree.

Later (out of scope for this task, documented as Phase roadmap): Binance **testnet** smoke test of
`FuturesClient`, paper-trade dry-run of the full `Runner` loop, websocket reconnect/recovery test.

## Commit & push
- Branch: `claude/trading-agent-ollama-design-DHqLR` (already checked out).
- Commit the new `docs/TRADING_AGENT_PLAN.md` and the `trading_agent/` skeleton with a descriptive message.
- `git push -u origin claude/trading-agent-ollama-design-DHqLR` (retry w/ backoff on network error).
- No pull request unless the user explicitly asks.
Plan approved. Let me verify the local environment and the ollama_agent version, then start building.

Ran
Check ruby, gem version, skills files
Bash
ruby -v; echo "---"; cat /home/user/ollama_agent/lib/ollama_agent/version.rb; echo "---bundler---"; bundle -v 2>/dev/null; echo "---skills runner/llm_client---"; ls /home/user/ollama_agent/lib/ollama_agent/skills/
ruby 3.3.6 (2024-11-05 revision 75015d4c1f) [x86_64-linux]
---
# frozen_string_literal: true

module OllamaAgent
  VERSION = "1.0.0"
end
---bundler---
4.0.9
---skills runner/llm_client---
architecture_refactorer.rb
base.rb
debug_engineer.rb
feature_builder.rb
json_extractor.rb
llm_client.rb
performance_optimizer.rb
registry.rb
runner.rb
Let me read LlmClient and SchemaValidator to ground the evaluator and schema correctly.


Read 2 files
Read
llm_client.rb
/home/user/ollama_agent/lib/ollama_agent/
skills/llm_client.rb
# frozen_string_literal: true

require_relative "../providers/registry"

module OllamaAgent
  module Skills
    # Thin facade over Providers::Registry tuned for deterministic, single-shot
    # JSON generation. Defaults to the local Ollama provider so skills stay
    # local-first and auditable. Inject any object responding to +#generate+
    # in tests.
    class LlmClient
      DEFAULT_TEMPERATURE = 0.0
      DEFAULT_PROVIDER    = "ollama"

      def initialize(provider: nil, model: nil, temperature: DEFAULT_TEMPERATURE)
        @provider    = provider || Providers::Registry.resolve(DEFAULT_PROVIDER)
        @model       = model || ENV.fetch("OLLAMA_AGENT_SKILL_MODEL", default_model)
        @temperature = temperature
      end

      # @param prompt [String]
      # @return [String] raw assistant content
      def generate(prompt)
        response = @provider.chat(messages: [user_message(prompt)], model: @model, temperature: @temperature)
        content  = response.content
        raise OllamaAgent::Error, "empty response from provider" if content.to_s.strip.empty?

        content
      end

      private

      def user_message(prompt)
        { role: "user", content: prompt }
      end

      def default_model
        ENV.fetch("OLLAMA_AGENT_MODEL", "llama3.2")
      end
    end
  end
end
Read
schema_validator.rb
/home/user/ollama_agent/lib/ollama_agent/
core/schema_validator.rb
# frozen_string_literal: true

module OllamaAgent
  module Core
    # Lightweight JSON-schema validator for tool arguments.
    # Supports: type, required, properties, enum, minimum, maximum, minLength, maxLength.
    # Does NOT require the json-schema gem — all validation is hand-rolled for zero dependencies.
    class SchemaValidator
      class ValidationError < StandardError
      end

      # Validate +data+ against +schema+.
      # @param schema [Hash] JSON schema (symbol or string keys)
      # @param data   [Hash] data to validate
      # @return [Array<String>] list of error messages (empty = valid)
      def validate(schema, data)
        @errors = []
        schema  = stringify_keys(schema)
        data    = stringify_keys(data || {})

        check_type(schema, data)
        check_required(schema, data)
        check_properties(schema, data)

        @errors.dup
      end

      # Raises ValidationError if any errors found.
      def validate!(schema, data)
        errors = validate(schema, data)
        raise ValidationError, errors.join("; ") if errors.any?

        true
      end

      private

      def check_type(schema, data)
        expected = schema["type"]
        return if expected.nil?

        actual = ruby_type(data)
        return if type_match?(expected, actual, data)

        @errors << "expected type #{expected}, got #{actual}"
      end

      def check_required(schema, data)
        required = schema["required"]
        return unless required.is_a?(Array)

        required.each do |field|
          @errors << "missing required field: #{field}" unless data.key?(field.to_s)
        end
      end

      def check_properties(schema, data)
        props = schema["properties"]
        return unless props.is_a?(Hash)

        props.each do |prop_name, prop_schema|
          next unless data.key?(prop_name.to_s)

          value = data[prop_name.to_s]
          prop_errors = self.class.new.validate(prop_schema, value)
          prop_errors.each { |e| @errors << "#{prop_name}: #{e}" }
          check_constraints(prop_name, prop_schema, value)
        end
      end

      def check_constraints(name, schema, value)
        check_enum(name, schema, value)
        check_string_length(name, schema, value)
        check_numeric_range(name, schema, value)
      end

      def check_enum(name, schema, value)
        allowed = schema["enum"]
        return unless allowed.is_a?(Array)
        return if allowed.include?(value)

        @errors << "#{name}: must be one of #{allowed.inspect}, got #{value.inspect}"
      end

      def check_string_length(name, schema, value)
        return unless value.is_a?(String)

        min_len = schema["minLength"]
        max_len = schema["maxLength"]

        if min_len && value.length < min_len
          @errors << "#{name}: length #{value.length} is less than minLength #{min_len}"
        end
        return unless max_len && value.length > max_len

        @errors << "#{name}: length #{value.length} exceeds maxLength #{max_len}"
      end

      def check_numeric_range(name, schema, value)
        return unless value.is_a?(Numeric)

        minimum = schema["minimum"]
        maximum = schema["maximum"]

        @errors << "#{name}: #{value} is less than minimum #{minimum}" if minimum && value < minimum
        @errors << "#{name}: #{value} exceeds maximum #{maximum}" if maximum && value > maximum
      end

      def ruby_type(value)
        case value
        when Hash    then "object"
        when Array   then "array"
        when String  then "string"
        when Integer then "integer"
        when Float   then "number"
        when TrueClass, FalseClass then "boolean"
        when NilClass then "null"
        else "unknown"
        end
      end

      def type_match?(expected, actual, data)
        return actual == expected unless expected == "number"

        data.is_a?(Numeric)
      end

      def stringify_keys(obj)
        return obj unless obj.is_a?(Hash)

        obj.transform_keys(&:to_s).transform_values do |v|
          v.is_a?(Hash) ? stringify_keys(v) : v
        end
      end
    end
  end
end
Grounding confirmed: Skills::Base reads a SCHEMA constant and validates via Core::SchemaValidator. Let me check whether ollama_agent loads in this environment (its deps must be available for the evaluator spec).


Ran 2 commands
Ran
Test loading ollama_agent
Bash
ruby -Ilib -e 'require "ollama_agent"; puts "OK ollama_agent loaded"; puts OllamaAgent::Skills::Base' 2>&1 | tail -20
<internal:/opt/rbenv/versions/3.3.6/lib/ruby/3.3.0/rubygems/core_ext/kernel_require.rb>:136:in `require': cannot load such file -- ollama_client (LoadError)
Did you mean?  ollama_agent
	from <internal:/opt/rbenv/versions/3.3.6/lib/ruby/3.3.0/rubygems/core_ext/kernel_require.rb>:136:in `require'
	from /home/user/ollama_agent/lib/ollama_agent.rb:9:in `<top (required)>'
	from <internal:/opt/rbenv/versions/3.3.6/lib/ruby/3.3.0/rubygems/core_ext/kernel_require.rb>:136:in `require'
	from <internal:/opt/rbenv/versions/3.3.6/lib/ruby/3.3.0/rubygems/core_ext/kernel_require.rb>:136:in `require'
	from -e:1:in `<main>'
Ran
Check bundle install status
Bash
bundle check 2>&1 | tail -5; echo "---try load via bundle---"; bundle exec ruby -e 'require "ollama_agent"; puts "OK"' 2>&1 | tail -8
Fetching https://github.com/shubhamtaywade82/ruby_mastery.git
Fetching https://github.com/shubhamtaywade82/ruby_mastery.git
Bundler can't satisfy your Gemfile's dependencies.
Install missing gems with `bundle install`.
---try load via bundle---
	from /opt/rbenv/versions/3.3.6/lib/ruby/gems/3.3.0/gems/bundler-4.0.9/lib/bundler/ui/shell.rb:177:in `with_level'
	from /opt/rbenv/versions/3.3.6/lib/ruby/gems/3.3.0/gems/bundler-4.0.9/lib/bundler/ui/shell.rb:122:in `silence'
	from /opt/rbenv/versions/3.3.6/lib/ruby/gems/3.3.0/gems/bundler-4.0.9/lib/bundler/setup.rb:32:in `<top (required)>'
	from <internal:/opt/rbenv/versions/3.3.6/lib/ruby/3.3.0/rubygems/core_ext/kernel_require.rb>:136:in `require'
	from <internal:/opt/rbenv/versions/3.3.6/lib/ruby/3.3.0/rubygems/core_ext/kernel_require.rb>:136:in `require'
	from /opt/rbenv/versions/3.3.6/lib/ruby/3.3.0/rubygems.rb:1397:in `<top (required)>'
	from <internal:gem_prelude>:2:in `require'
	from <internal:gem_prelude>:2:in `<internal:gem_prelude>'
Dependencies aren't installed. Let me attempt bundle install to see if the network policy allows it.

Ran
Install ollama_agent dependencies
Bash
timeout 180 bundle install 2>&1 | tail -25
Installing tty-table 0.12.0
Fetching tty-prompt 0.23.1
Installing tty-prompt 0.23.1
Fetching rspec 3.13.2
Installing rspec 3.13.2
Fetching ollama-client 1.1.0
Installing ollama-client 1.1.0
Fetching rdoc 7.2.0
Installing rdoc 7.2.0
Fetching irb 1.17.0
Fetching rubocop-ast 1.49.1
Fetching unparser 0.8.2
Installing irb 1.17.0
Installing rubocop-ast 1.49.1
Installing unparser 0.8.2
Fetching rubocop 1.86.1
Installing rubocop 1.86.1
Fetching rubocop-rake 0.7.1
Fetching rubocop-rspec 3.9.0
Installing rubocop-rake 0.7.1
Installing rubocop-rspec 3.9.0
Bundle complete! 11 Gemfile dependencies, 63 gems now installed.
Use `bundle info [gemname]` to see where a bundled gem is installed.
1 installed gem you directly depend on is looking for funding.
  Run `bundle fund` for details
Network and install work. Let me confirm ollama_agent loads via bundle now.

Ran
Confirm ollama_agent loads
Bash
bundle exec ruby -e 'require "ollama_agent"; puts "OK"; p OllamaAgent::Skills::Base; p OllamaAgent::Core::SchemaValidator' 2>&1 | tail -8
OK
OllamaAgent::Skills::Base
OllamaAgent::Core::SchemaValidator
Everything works. Now I'll build the deliverables. Starting with the design doc.

Created
TRADING_AGENT_PLAN.md
+215
-0
/home/user/ollama_agent/docs/
TRADING_AGENT_PLAN.md
# `trading_agent` — Design & Architecture Plan

A production-grade autonomous crypto-trading framework, built as a **separate Ruby gem**
that layers on top of [`ollama_agent`](https://github.com/shubhamtaywade82/ollama_agent)
as its LLM-orchestration layer.

> Status: **design + starter skeleton**. The skeleton in [`/trading_agent`](../trading_agent)
> compiles and self-documents the architecture; trading-logic bodies are stubs to be filled in by phase.

---

## 1. Context & the one non-negotiable rule

We want an LLM (run locally via Ollama, with optional cloud fallback) to help make trading
decisions on Binance USD-M Futures. The danger with naive "prompt → place order" designs is that
the model eventually **hallucinates trades, violates leverage/risk limits, or deadlocks on
websocket state**. The architecture below exists to make that structurally impossible.

**The rule:**

> **The deterministic Ruby runtime — not the LLM — is the source of truth. The LLM only reasons.**

Concretely, the LLM may *analyze, plan, select read-only tools, and explain*. It **emits a
structured trade *intent*** and nothing more. It **never**:

- touches Binance directly,
- sizes orders or sets leverage,
- picks symbols outside the whitelist,
- holds authoritative position/balance state.

The Ruby runtime fetches market data, aggregates candles, runs deterministic strategies/indicators,
validates the LLM's intent, enforces risk caps, places/cancels orders, maintains state, and recovers
from websocket failures.

---

## 2. Architecture

Event-driven. A lightweight `EventBus` wires the stages; a `StateEngine` is the single source of truth.

```
Binance WS market stream ─┐
                          ├─► StateEngine (SOURCE OF TRUTH: positions/balances/orders/candles)
Binance WS user stream  ──┘            │
        │                              ▼
        └─► CandleStore ──► StrategyEngine (deterministic indicators / SMC)
            (local OHLCV)              │
                                       ▼  (only when a deterministic setup fires)
                         MarketContext (compressed struct for the LLM)
                                       ▼
                         LLM TradeEvaluator  ◄── OllamaAgent::Skills::Base + strict SCHEMA
                                       │ structured trade intent (JSON)
                                       ▼
                         ResponseValidator  ◄── OllamaAgent::Core::SchemaValidator
                                       ▼
                         RiskEngine  (sizing + leverage / exposure / liquidation / kill-switch)
                                       ▼
                         OrderManager (idempotency keys, execution locks, reconciliation)
                                       ▼
                         Exchanges::Binance::FuturesClient  ◄── binance-connector-ruby
```

**Layer responsibilities**

| Layer | Owns | Authority |
|---|---|---|
| `Exchanges::Binance` | REST (orders/positions/leverage/balances), market + user websocket streams | the *only* code that talks to Binance |
| `StateEngine` | in-memory positions/balances/orders/candles, reconciled against the user stream | source of truth |
| `CandleStore` / `IndicatorStore` | local OHLCV aggregation from ticks; EMA/RSI/VWAP/ATR | deterministic, no LLM |
| `StrategyEngine` | BOS/CHOCH/momentum/etc. → emits a `signal` or `nil` | decides *whether to even ask the LLM* |
| `MarketContext` | compresses state+indicators into a small struct | the only thing the LLM sees |
| `TradeEvaluator` (LLM) | reasons over context → emits structured intent | **no execution authority** |
| `ResponseValidator` | schema-validates the intent, rejects malformed output | gate |
| `RiskEngine` | sizing + every hard cap + kill-switch | veto power over every trade |
| `OrderManager` / `PositionManager` | order lifecycle, idempotency, reconciliation | executes only validated, risk-approved intents |

---

## 3. What we reuse from `ollama_agent` (do NOT rewrite)

The LLM-orchestration layer already exists in this repo. `trading_agent` *consumes* it.

| Need | Reuse | Path in `ollama_agent` |
|---|---|---|
| LLM emits **structured, schema-validated** output (never free text) | `Skills::Base` pipeline: `prompt → llm.generate → JsonExtractor.parse → SchemaValidator.validate!` + a `SCHEMA` constant | `lib/ollama_agent/skills/base.rb` |
| Single-shot, local-first JSON generation | `Skills::LlmClient` (defaults to Ollama, temperature 0.0, injectable in tests) | `lib/ollama_agent/skills/llm_client.rb` |
| Zero-dependency schema validation / reject malformed | `Core::SchemaValidator#validate!` (type/required/enum/min/max) | `lib/ollama_agent/core/schema_validator.rb` |
| Tool calling (read-only context fetchers) | `OllamaAgent::Tools.register(name, schema:, &handler)` | `lib/ollama_agent/tools/registry.rb` |
| Multi-provider LLM + cloud fallback | `Providers::Registry` / `Runner.build(provider:)` | `lib/ollama_agent/providers/registry.rb`, `runner.rb` |
| Agent loop, budget, loop detection | `Runner.build(...).run`, `Core::Budget`, `Core::LoopDetector` | `runner.rb`, `lib/ollama_agent/core/*` |
| Memory tiers / session persistence (for **audit/narration**, not trade truth) | `Memory::Manager`, `Session::Store` | `lib/ollama_agent/memory/manager.rb` |
| Hard guardrails on tool authority | `Runner.build(read_only:, permissions:)`, `Runtime::Permissions` | `runner.rb`, `lib/ollama_agent/runtime/permissions.rb` |

**Consequence:** the `trading_agent` LLM layer is thin — a `Skills::Base` subclass (`TradeEvaluator`)
with a strict decision `SCHEMA`, plus a few **read-only** registered tools. All *trading* engineering
(exchange, streams, candles, strategies, risk, execution, recovery) is net-new in the new gem.

---

## 4. The structured trade-intent contract

The LLM never returns prose. `TradeEvaluator < OllamaAgent::Skills::Base` declares a `SCHEMA`; the
base class validates every response and raises `ContractError` on any deviation.

```json
{
  "action":      "LONG",
  "symbol":      "BTCUSDT",
  "confidence":  0.83,
  "entry_type":  "MARKET",
  "risk_percent": 1.0,
  "stop_loss":   103200.0,
  "take_profit": 105800.0,
  "reasoning":   ["4H bullish BOS", "1H demand reclaim", "5m momentum expansion"]
}
```

Schema enforces: `action ∈ {LONG, SHORT, FLAT}`, `entry_type ∈ {MARKET, LIMIT}`,
`0 ≤ confidence ≤ 1`, `0 < risk_percent ≤ MAX_ACCOUNT_RISK`, required `symbol`/`stop_loss`/`take_profit`,
`reasoning` is a non-empty array. Anything else is rejected **before it reaches the RiskEngine**.

`symbol` is *still* re-checked against the whitelist in the RiskEngine — never trust an LLM string.

---

## 5. Exchange adapter contract

`Exchanges::Base` is abstract so we can add Bybit / Dhan / Zerodha later without touching the runtime:

```ruby
place_order(symbol:, side:, type:, quantity:, price: nil, client_order_id:)
cancel_order(symbol:, order_id:)
positions
balances
set_leverage(symbol:, leverage:)
subscribe_market(symbol:, &on_event)
subscribe_user(&on_event)
```

`Exchanges::Binance::FuturesClient` implements it on top of
[`binance-connector-ruby`](https://github.com/binance/binance-connector-ruby) for REST
(orders/positions/leverage/account) and websocket for market + user-data streams.
`StreamManager` owns reconnection, sequence-gap detection, stale-stream/heartbeat handling.

Use the Binance toolbox examples only as a **reference** for local order-book sync and websocket
sequencing — do not couple the runtime to example code.

---

## 6. Production-risk checklist (must-solve)

- **Duplicate orders** → client-supplied idempotency keys (`client_order_id`), execution locks per
  symbol, and periodic reconciliation against the user stream.
- **Websocket desync** → automatic reconnect, sequence-gap recovery, stale-stream detection,
  heartbeat monitoring (`StreamManager`).
- **Hallucinated symbols** → `SymbolRegistry` whitelist; RiskEngine rejects anything not on it.
- **Runaway position scaling** → hard caps outside LLM control:
  `MAX_OPEN_POSITIONS = 3`, `MAX_ACCOUNT_RISK = 5%`, `MAX_LEVERAGE = 5`.
- **Emergency kill-switch** → halt all new entries when `daily_drawdown > MAX_DAILY_DRAWDOWN`.
- **Rate limits** → centralized throttling, websocket-first reads, retry with jitter.

---

## 7. Models

Local-first via Ollama, cloud fallback via `Providers::Registry`:

- **Balanced / structured-output + tool calling:** `qwen3.x:14b` / `qwen3.x:32b`
- **Fast reasoning / planner:** `deepseek-r1:14b`
- **Heavy multi-symbol analysis (cloud fallback):** larger qwen / deepseek hosted models

Hybrid: a local agent handles low-latency execution decisions; a cloud agent handles deeper
multi-symbol ranking / regime detection.

---

## 8. Phased roadmap

Each phase maps to skeleton files under [`/trading_agent/lib/trading_agent`](../trading_agent/lib/trading_agent).

- **Phase 1 — deterministic plumbing (no AI):** `Exchanges::Binance::*`, `StreamManager`,
  `StateEngine`, `CandleStore`, `OrderManager`, `PositionManager`. Verify on **testnet**.
- **Phase 2 — structured LLM:** `Llm::DecisionSchema`, `Llm::TradeEvaluator`, `Llm::Tools`
  (read-only context fetchers), `ResponseValidator`. Reject malformed output.
- **Phase 3 — strategy + risk:** `Strategies::*`, `IndicatorStore`, `Risk::RiskEngine`,
  `Risk::PositionSizer`, `Risk::Guards`. Multi-timeframe context.
- **Phase 4 — autonomous execution + recovery + alerts:** full `Runner` loop, reconciliation,
  recovery daemon, Telegram/metrics alerts.

---

## 9. Verification

Skeleton-level (this deliverable):

1. `cd trading_agent && bundle install` resolves (`ollama_agent` via `path: ".."`).
2. `bundle exec ruby -Ilib -e 'require "trading_agent"'` loads cleanly.
3. `bundle exec rspec` passes the seed specs:
   - `TradeEvaluator` rejects a malformed LLM response (schema → `ContractError`).
   - `RiskEngine` rejects intents breaching `MAX_ACCOUNT_RISK` / `MAX_LEVERAGE` / kill-switch.

Later (per roadmap, out of scope here): Binance **testnet** smoke test of `FuturesClient`,
paper-trade dry-run of the full `Runner` loop, websocket reconnect/recovery test.

---

## 10. Skeleton layout

See [`/trading_agent`](../trading_agent). Key files:

- `lib/trading_agent/runner.rb` — the orchestration loop (ctx → strategy → evaluator → validate → risk → execute).
- `lib/trading_agent/llm/trade_evaluator.rb` — `OllamaAgent::Skills::Base` subclass; the linchpin reuse.
- `lib/trading_agent/risk/risk_engine.rb` + `risk/guards.rb` — the veto layer (implemented, not stubbed).
- `lib/trading_agent/exchanges/base.rb` — the adapter contract for multi-exchange support.
- `lib/trading_agent/state/state_engine.rb` — the source of truth.