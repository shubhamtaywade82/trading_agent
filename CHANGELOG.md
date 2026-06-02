# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-02

### Added

- **First Independent Release**: Extracted the `TradingAgent` codebase out of the `ollama_agent` monorepo into its own repository.
- **Exchanges Integration**: Binance Spot and Binance Futures API connectors for order management, data fetching (ticker, candles), and account details.
- **Technical Market Indicators**: SMA, EMA, RSI, BB, MACD, and ATR calculation engines.
- **Risk Management Engine**: Daily drawdown checking, position sizing calculations, maximum open position constraints, and leverage control.
- **Execution Manager**: Semi-autonomous and autonomous order generation with stop-loss/take-profit triggers.
- **Orchestrator and LLM Integration**: Planning cycle using local Ollama model context, auto-repair of malformed JSON outputs, and console interface tools.
- **Interactive Console Shell**: Command line client with slash commands (e.g. `/balances`, `/positions`, `/ticker`, `/live`) and full keyboard control.
