# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingAgent::Llm::Orchestrator do
  let(:state) { double("State") }
  let(:exchange) { double("Exchange") }
  let(:runner) { double("OllamaAgentRunner") }
  let(:hooks) { OllamaAgent::Streaming::Hooks.new }

  before do
    allow(OllamaAgent::Runner).to receive(:build).and_return(runner)
    allow(runner).to receive(:hooks).and_return(hooks)
    
    # We must reset custom tools before each run
    OllamaAgent::Tools.reset!
  end

  describe "initialization" do
    it "registers custom trading tools globally" do
      expect(OllamaAgent::Tools.custom_tool?("fetch_market_context")).to be false
      expect(OllamaAgent::Tools.custom_tool?("check_indicators")).to be false

      described_class.new(state, exchange)

      expect(OllamaAgent::Tools.custom_tool?("fetch_market_context")).to be true
      expect(OllamaAgent::Tools.custom_tool?("check_indicators")).to be true
    end
  end

  describe "#analyze_and_plan" do
    let(:orchestrator) { described_class.new(state, exchange) }
    let(:market_context) { { price: 100 } }

    let(:model_json) do
      <<-JSON
      {
        "action": "BUY",
        "symbol": "BTCUSDT",
        "leverage": 3,
        "risk_percent": 1.0,
        "stop_loss": 95000.0,
        "take_profit": 105000.0,
        "reasoning": ["Bullish structure"]
      }
      JSON
    end

    it "runs the LLM, fires on_complete hook, and parses JSON output" do
      # When runner.run is called, we simulate the hook emitting :on_complete with final message
      allow(runner).to receive(:run) do
        hooks.emit(:on_complete, {
          messages: [
            { role: "user", content: "Prompt" },
            { role: "assistant", content: model_json }
          ]
        })
      end

      intent = orchestrator.analyze_and_plan(market_context)
      expect(intent).not_to be_nil
      expect(intent[:action]).to eq("BUY")
      expect(intent[:symbol]).to eq("BTCUSDT")
      expect(intent[:leverage]).to eq(3)
      expect(intent[:risk_percent]).to eq(1.0)
      expect(intent[:stop_loss]).to eq(95000.0)
      expect(intent[:take_profit]).to eq(105000.0)
      expect(intent[:reasoning]).to eq(["Bullish structure"])
    end

    it "returns nil and logs when extraction or parsing fails" do
      allow(runner).to receive(:run) do
        hooks.emit(:on_complete, {
          messages: [
            { role: "assistant", content: "Not a JSON structure" }
          ]
        })
      end

      expect(orchestrator.analyze_and_plan(market_context)).to be_nil
    end
  end

  describe "model resolution and assignment" do
    before do
      allow(runner).to receive(:model).and_return("resolved-model")
    end

    it "exposes the active model name and delegates assignment" do
      orchestrator = described_class.new(state, exchange)
      expect(orchestrator.model).to eq("resolved-model")

      expect(runner).to receive(:assign_chat_model!).with("new-model")
      orchestrator.assign_chat_model!("new-model")
    end

    it "uses ENV variables for model selection during init" do
      stub_const("ENV", ENV.to_h.merge(
        "OLLAMA_AGENT_MODEL" => nil,
        "OLLAMA_MODEL" => "env-model"
      ))
      expect(OllamaAgent::Runner).to receive(:build).with(
        model: "env-model",
        system_prompt: anything,
        read_only: true
      ).and_return(runner)

      described_class.new(state, exchange, model: nil)
    end
  end
end
