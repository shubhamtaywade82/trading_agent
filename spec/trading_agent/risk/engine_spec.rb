# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingAgent::Risk::Engine do
  let(:config) do
    {
      max_leverage: 5,
      max_position_size_pct: 0.5, # 50%
      max_daily_drawdown_pct: 0.05, # 5%
      max_open_positions: 2
    }
  end
  let(:engine) { described_class.new(config) }
  
  let(:state) { instance_double(TradingAgent::Market::State) }
  
  before do
    allow(state).to receive(:current_drawdown_pct).and_return(0.01)
    allow(state).to receive(:open_positions_count).and_return(0)
    allow(state).to receive(:get_position).and_return(nil)
    allow(state).to receive(:get_price).with("BTCUSDT").and_return(100_000.0)
    allow(state).to receive(:total_equity).and_return(10_000.0)
  end

  describe "#validate_intent" do
    let(:valid_intent) do
      {
        action: "BUY",
        symbol: "BTCUSDT",
        leverage: 3,
        risk_percent: 1.0,
        stop_loss: 95_000.0,
        take_profit: 110_000.0
      }
    end

    it "allows a valid intent" do
      res = engine.validate_intent(valid_intent, state)
      expect(res[:success]).to be true
    end

    it "returns success for HOLD action" do
      res = engine.validate_intent(valid_intent.merge(action: "HOLD"), state)
      expect(res[:success]).to be true
    end

    it "rejects when max daily drawdown is exceeded" do
      allow(state).to receive(:current_drawdown_pct).and_return(0.06)
      res = engine.validate_intent(valid_intent, state)
      expect(res[:success]).to be false
      expect(res[:reason]).to include("drawdown")
    end

    it "rejects when max open positions is reached" do
      allow(state).to receive(:open_positions_count).and_return(2)
      res = engine.validate_intent(valid_intent, state)
      expect(res[:success]).to be false
      expect(res[:reason]).to include("positions")
    end

    it "allows trade on a symbol with existing position even if max positions limit is reached" do
      allow(state).to receive(:open_positions_count).and_return(2)
      allow(state).to receive(:get_position).with("BTCUSDT").and_return({ position_amt: 0.5 })
      res = engine.validate_intent(valid_intent, state)
      expect(res[:success]).to be true
    end

    it "rejects when leverage exceeds limit" do
      intent = valid_intent.merge(leverage: 10)
      res = engine.validate_intent(intent, state)
      expect(res[:success]).to be false
      expect(res[:reason]).to include("Leverage")
    end

    it "rejects when calculated position notional size exceeds limit" do
      # Risk Amount = 10000 * 5% = 500
      # Distance = 100000 - 95000 = 5000
      # Position Size = 500 / 5000 = 0.1
      # Notional Value = 0.1 * 100000 = 10_000 (which is 100% of equity, exceeding max_position_size_pct of 10%)
      intent = valid_intent.merge(risk_percent: 5.0)
      res = engine.validate_intent(intent, state)
      expect(res[:success]).to be false
      expect(res[:reason]).to include("notional value")
    end
  end
end
