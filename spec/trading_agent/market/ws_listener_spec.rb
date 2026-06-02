# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingAgent::Market::WsListener do
  let(:state) { instance_double(TradingAgent::Market::State) }
  let(:symbols) { ["BTCUSDT"] }

  subject(:listener) { described_class.new(state, symbols) }

  describe "#initialize" do
    it "stores symbols in upcase" do
      l = described_class.new(state, ["btcusdt", "solusdt"])
      expect(l.instance_variable_get(:@symbols)).to eq(["BTCUSDT", "SOLUSDT"])
    end

    it "is not connected initially" do
      expect(listener.connected).to be false
    end
  end

  describe "#on_tick" do
    it "registers a callback and returns self for chaining" do
      result = listener.on_tick { |_s, _p| }
      expect(result).to be(listener)
      expect(listener.instance_variable_get(:@tick_cbs).size).to eq(1)
    end
  end

  describe "#handle_message (private)" do
    before { allow(state).to receive(:update_price) }

    it "updates state and fires tick callbacks for a valid miniTicker frame" do
      raw = { "stream" => "btcusdt@miniTicker", "data" => { "s" => "BTCUSDT", "c" => "95000.50" } }.to_json
      received = []
      listener.on_tick { |sym, price| received << [sym, price] }

      listener.send(:handle_message, raw)

      expect(state).to have_received(:update_price).with("BTCUSDT", 95000.50)
      expect(received).to eq([["BTCUSDT", 95000.50]])
    end

    it "ignores malformed JSON without raising" do
      expect { listener.send(:handle_message, "NOT_JSON") }.not_to raise_error
    end

    it "ignores frames missing a symbol" do
      raw = { "data" => { "c" => "100.0" } }.to_json
      expect { listener.send(:handle_message, raw) }.not_to raise_error
      expect(state).not_to have_received(:update_price)
    end
  end

  describe "#stream_url (private)" do
    it "builds a spot combined stream URL for spot exchange" do
      url = listener.send(:stream_url)
      expect(url).to include("stream.binance.com")
      expect(url).to include("btcusdt@miniTicker")
    end

    it "builds a futures stream URL when futures: true" do
      l = described_class.new(state, ["BTCUSDT"], futures: true)
      url = l.send(:stream_url)
      expect(url).to include("fstream.binance.com")
    end
  end
end
