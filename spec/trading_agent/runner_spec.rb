# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingAgent::Runner do
  let(:exchange) { double("Exchange") }
  let(:runner) { described_class.new(exchange: exchange, symbols: ["BTCUSDT"]) }
  
  before do
    allow(OllamaAgent::Runner).to receive(:build).and_return(double("Agent", hooks: OllamaAgent::Streaming::Hooks.new))
  end

  describe "initialization" do
    it "sets up required components" do
      expect(runner.exchange).to eq(exchange)
      expect(runner.symbols).to eq(["BTCUSDT"])
      expect(runner.state).to be_a(TradingAgent::Market::State)
      expect(runner.risk_engine).to be_a(TradingAgent::Risk::Engine)
      expect(runner.execution_manager).to be_a(TradingAgent::Execution::Manager)
      expect(runner.llm_orchestrator).to be_a(TradingAgent::Llm::Orchestrator)
    end
  end

  describe "#update_initial_state" do
    it "updates balances and positions from exchange" do
      expect(exchange).to receive(:fetch_balances).and_return([{ asset: "USDT", balance: 5000.0, free: 5000.0 }])
      expect(exchange).to receive(:fetch_positions).and_return([{ symbol: "BTCUSDT", position_amt: 0.1, entry_price: 90000.0 }])

      runner.send(:update_initial_state)

      expect(runner.state.get_balances).to eq([{ asset: "USDT", balance: 5000.0, free: 5000.0 }])
      expect(runner.state.get_position("BTCUSDT")).to eq({ symbol: "BTCUSDT", position_amt: 0.1, entry_price: 90000.0 })
    end
  end

  describe "#run_evaluation_cycle" do
    let(:intent) do
      {
        action: "BUY",
        symbol: "BTCUSDT",
        leverage: 3,
        risk_percent: 1.0,
        stop_loss: 95000.0,
        take_profit: 105000.0
      }
    end

    before do
      allow(runner.llm_orchestrator).to receive(:analyze_and_plan).and_return(intent)
      allow(runner.risk_engine).to receive(:validate_intent).and_return({ success: true })
      allow(runner.execution_manager).to receive(:execute_intent)
      
      # Mock exchange updates for update_initial_state inside run_evaluation_cycle
      allow(exchange).to receive(:fetch_balances).and_return([])
      allow(exchange).to receive(:fetch_positions).and_return([])
    end

    it "calls orchestrator, validates intent, and executes if valid" do
      expect(runner.llm_orchestrator).to receive(:analyze_and_plan)
      expect(runner.risk_engine).to receive(:validate_intent).with(intent, runner.state)
      expect(runner.execution_manager).to receive(:execute_intent).with(intent, runner.state)

      # Check events are published
      intent_published = false
      validated_published = false
      
      TradingAgent::EventBus.subscribe("llm.intent") { intent_published = true }
      TradingAgent::EventBus.subscribe("risk.validated") { validated_published = true }

      runner.send(:run_evaluation_cycle)
      
      expect(intent_published).to be true
      expect(validated_published).to be true
    end

    it "does not execute if risk validation fails" do
      allow(runner.risk_engine).to receive(:validate_intent).and_return({ success: false, reason: "Risk limit reached" })
      expect(runner.execution_manager).not_to receive(:execute_intent)

      runner.send(:run_evaluation_cycle)
    end
  end
end
