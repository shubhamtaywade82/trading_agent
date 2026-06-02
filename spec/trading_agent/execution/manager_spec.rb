# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingAgent::Execution::Manager do
  let(:exchange) { double("Exchange") }
  let(:manager) { described_class.new(exchange) }
  
  let(:state) { instance_double(TradingAgent::Market::State) }
  
  before do
    allow(state).to receive(:get_price).with("BTCUSDT").and_return(100_000.0)
    allow(state).to receive(:total_equity).and_return(10_000.0)
  end

  describe "#calculate_quantity" do
    let(:intent) do
      {
        symbol: "BTCUSDT",
        risk_percent: 1.0,
        stop_loss: 95_000.0
      }
    end

    it "calculates correct quantity based on risk" do
      # Risk amount = 100
      # Distance = 5,000
      # Size = 100 / 5,000 = 0.02
      expect(manager.calculate_quantity(intent, state)).to eq(0.02)
    end

    it "returns 0 if stop loss is missing or zero" do
      expect(manager.calculate_quantity(intent.merge(stop_loss: 0.0), state)).to eq(0.0)
    end
  end

  describe "#execute_intent" do
    let(:intent) do
      {
        action: "BUY",
        symbol: "BTCUSDT",
        leverage: 3,
        risk_percent: 1.0,
        stop_loss: 95_000.0,
        take_profit: 110_000.0
      }
    end

    before do
      # Mock exchange calls
      allow(exchange).to receive(:respond_to?).with(:set_leverage).and_return(true)
      allow(exchange).to receive(:set_leverage).with("BTCUSDT", 3)
      allow(exchange).to receive(:create_order).with("BTCUSDT", "BUY", "MARKET", 0.02).and_return({ orderId: 123 })
      
      # Mock SL and TP order placement
      allow(exchange).to receive(:create_order).with("BTCUSDT", "SELL", "STOP_MARKET", 0.02, params: { stopPrice: 95_000.0, reduceOnly: true }).and_return({ orderId: 124 })
      allow(exchange).to receive(:create_order).with("BTCUSDT", "SELL", "TAKE_PROFIT_MARKET", 0.02, params: { stopPrice: 110_000.0, reduceOnly: true }).and_return({ orderId: 125 })
    end

    it "sets leverage, places market order and SL/TP orders" do
      expect(exchange).to receive(:set_leverage).with("BTCUSDT", 3)
      expect(exchange).to receive(:create_order).with("BTCUSDT", "BUY", "MARKET", 0.02)
      expect(exchange).to receive(:create_order).with("BTCUSDT", "SELL", "STOP_MARKET", 0.02, params: { stopPrice: 95_000.0, reduceOnly: true })
      expect(exchange).to receive(:create_order).with("BTCUSDT", "SELL", "TAKE_PROFIT_MARKET", 0.02, params: { stopPrice: 110_000.0, reduceOnly: true })
      
      # Subscribe to EventBus to assert publish
      event_received = false
      TradingAgent::EventBus.subscribe("execution.started") do |payload|
        event_received = true
        expect(payload[:intent][:symbol]).to eq("BTCUSDT")
        expect(payload[:quantity]).to eq(0.02)
      end

      manager.execute_intent(intent, state)
      expect(event_received).to be true
    end

    it "skips execution if action is HOLD" do
      expect(exchange).not_to receive(:create_order)
      manager.execute_intent(intent.merge(action: "HOLD"), state)
    end
  end
end
