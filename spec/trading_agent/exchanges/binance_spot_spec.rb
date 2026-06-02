# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingAgent::Exchanges::BinanceSpot do
  let(:api_key) { "mock_api_key" }
  let(:secret_key) { "mock_secret_key" }
  let(:exchange) { described_class.new(api_key: api_key, secret_key: secret_key, testnet: true) }
  let(:client) { double("Binance::Spot") }

  before do
    allow(Binance::Spot).to receive(:new).and_return(client)
  end

  describe "#fetch_ticker" do
    it "returns the ticker price parsed from client" do
      expect(client).to receive(:ticker_price).with(symbol: "BTCUSDT").and_return({ price: "95000.50" })
      res = exchange.fetch_ticker("BTCUSDT")
      expect(res).to eq({ price: 95000.50 })
    end
  end

  describe "#fetch_candles" do
    it "returns klines array directly" do
      klines = [
        [1716386348123, "90000.0", "91000.0", "89000.0", "90500.0", "1.5", 1716386348999]
      ]
      expect(client).to receive(:klines).with(symbol: "BTCUSDT", interval: "1h", limit: 100).and_return(klines)
      res = exchange.fetch_candles("BTCUSDT", "1h")
      expect(res).to eq(klines)
    end
  end

  describe "#fetch_balances" do
    it "returns mapped balances" do
      account_info = {
        balances: [
          { asset: "BTC", free: "1.5", locked: "0.5" },
          { asset: "USDT", free: "1000.0", locked: "0.0" }
        ]
      }
      expect(client).to receive(:account).and_return(account_info)
      res = exchange.fetch_balances
      expect(res).to eq([
        { asset: "BTC", balance: 2.0, free: 1.5, locked: 0.5 },
        { asset: "USDT", balance: 1000.0, free: 1000.0, locked: 0.0 }
      ])
    end

    it "returns empty array when credentials are missing" do
      no_creds_exchange = described_class.new(api_key: nil, secret_key: nil)
      expect(client).not_to receive(:account)
      expect(no_creds_exchange.fetch_balances).to eq([])
    end
  end
end
