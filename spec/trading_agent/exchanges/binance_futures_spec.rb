# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingAgent::Exchanges::BinanceFutures do
  let(:api_key) { "mock_api_key" }
  let(:secret_key) { "mock_secret_key" }
  let(:exchange) { described_class.new(api_key: api_key, secret_key: secret_key, testnet: true) }
  let(:session) { double("Binance::Session") }

  before do
    allow(Binance::Session).to receive(:new).and_return(session)
  end

  describe "#fetch_ticker" do
    it "returns the ticker price parsed from client" do
      expect(session).to receive(:public_request).with(path: "/fapi/v1/ticker/price", params: { symbol: "BTCUSDT" }).and_return({ price: "95000.50" })
      res = exchange.fetch_ticker("BTCUSDT")
      expect(res).to eq({ price: 95000.50 })
    end
  end

  describe "#fetch_candles" do
    it "returns klines array directly" do
      klines = [
        [1716386348123, "90000.0", "91000.0", "89000.0", "90500.0", "1.5", 1716386348999]
      ]
      expect(session).to receive(:public_request).with(path: "/fapi/v1/klines", params: { symbol: "BTCUSDT", interval: "1h", limit: 100 }).and_return(klines)
      res = exchange.fetch_candles("BTCUSDT", "1h")
      expect(res).to eq(klines)
    end
  end

  describe "#fetch_positions" do
    it "returns mapped positions" do
      api_response = [
        { symbol: "BTCUSDT", positionAmt: "0.5", entryPrice: "90000.0", leverage: "3", unRealizedProfit: "2500.0", marginType: "cross", liquidationPrice: "62000.0" }
      ]
      expect(session).to receive(:sign_request).with(:get, "/fapi/v2/positionRisk").and_return(api_response)
      res = exchange.fetch_positions
      expect(res).to eq([
        {
          symbol: "BTCUSDT",
          position_amt: 0.5,
          entry_price: 90000.0,
          leverage: 3,
          unrealized_profit: 2500.0,
          margin_type: "cross",
          liquidation_price: 62000.0
        }
      ])
    end
  end

  describe "#fetch_balances" do
    it "returns mapped balances" do
      api_response = [
        { asset: "USDT", balance: "10000.0", availableBalance: "9500.0" }
      ]
      expect(session).to receive(:sign_request).with(:get, "/fapi/v2/balance").and_return(api_response)
      res = exchange.fetch_balances
      expect(res).to eq([
        { asset: "USDT", balance: 10000.0, free: 9500.0, locked: 500.0 }
      ])
    end
  end

  describe "#set_leverage" do
    it "sends post request to leverage endpoint" do
      expect(session).to receive(:sign_request).with(:post, "/fapi/v1/leverage", params: { symbol: "BTCUSDT", leverage: 5 }).and_return({ symbol: "BTCUSDT", leverage: 5 })
      res = exchange.set_leverage("BTCUSDT", 5)
      expect(res).to eq({ symbol: "BTCUSDT", leverage: 5 })
    end
  end
end
