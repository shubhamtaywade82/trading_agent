# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingAgent::Market::Indicators do
  let(:prices) { [10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0] }
  let(:hash_candles) { prices.map { |p| { close: p, high: p + 1.0, low: p - 1.0 } } }
  let(:array_candles) { prices.map { |p| [0, 0, p + 1.0, p - 1.0, p, 0, 0] } }

  describe ".sma" do
    it "calculates simple moving average correctly" do
      expect(described_class.sma(hash_candles, 3)).to eq(18.0)
      expect(described_class.sma(array_candles, 3)).to eq(18.0)
    end

    it "returns nil if candles size is less than period" do
      expect(described_class.sma(hash_candles, 20)).to be_nil
    end
  end

  describe ".ema" do
    it "calculates exponential moving average correctly" do
      expect(described_class.ema(hash_candles, 3)).to eq(18.0)
    end
  end

  describe ".rsi" do
    it "calculates RSI correctly" do
      res = described_class.rsi(hash_candles, 5)
      expect(res).to be_a(Float)
      expect(res).to be > 90.0
    end
  end

  describe ".atr" do
    it "calculates ATR correctly" do
      res = described_class.atr(hash_candles, 5)
      expect(res).to eq(2.0)
    end
  end
end
