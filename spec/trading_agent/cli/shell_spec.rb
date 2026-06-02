# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingAgent::InteractiveShell do
  let(:state) { instance_double(TradingAgent::Market::State) }
  let(:exchange) { double("Exchange") }
  let(:orchestrator) { double("Orchestrator") }
  let(:shell) { described_class.new(state, exchange, orchestrator) }

  before do
    allow(state).to receive(:update_balances)
    allow(state).to receive(:update_position)
    allow(state).to receive(:get_balances).and_return([])
    allow(state).to receive(:current_drawdown_pct).and_return(0.0)
    allow(state).to receive(:get_price).and_return(100.0)
    
    allow(exchange).to receive(:fetch_balances).and_return([])
    allow(exchange).to receive(:fetch_positions).and_return([])
  end

  describe "#chat_with_advisor" do
    it "constructs a prompt, renders response via Console.format_assistant, and wraps in advisor box" do
      expect(orchestrator).to receive(:free_chat).with(anything).and_return("Advice")
      allow(OllamaAgent::Console).to receive(:format_assistant).with("Advice").and_return("Advice")
      expect { shell.send(:chat_with_advisor, "what should I do?") }.to output(/Advisor.*Advice/m).to_stdout
    end
  end

  describe "slash commands" do
    it "fetches balances and prints them" do
      balances = [{ asset: "BTC", balance: 1.0, free: 1.0 }]
      expect(exchange).to receive(:fetch_balances).and_return(balances)
      expect { shell.send(:print_balances) }.to output(/Asset:.*BTC/).to_stdout
    end

    it "fetches positions and prints them" do
      positions = [{ symbol: "BTCUSDT", position_amt: 0.5, entry_price: 90000.0, leverage: 3, unrealized_profit: 100.0 }]
      expect(exchange).to receive(:fetch_positions).and_return(positions)
      expect { shell.send(:print_positions) }.to output(/Symbol:.*BTCUSDT/).to_stdout
    end

    it "fetches ticker price and prints it" do
      expect(exchange).to receive(:fetch_ticker).with("BTCUSDT").and_return({ price: 95000.0 })
      expect(state).to receive(:update_price).with("BTCUSDT", 95000.0)
      expect { shell.send(:print_ticker, "BTCUSDT") }.to output(/95000/).to_stdout
    end

    it "streams live ticker price via WsListener and exits on Interrupt" do
      fake_listener = instance_double(
        TradingAgent::Market::WsListener,
        on_tick: nil,
        start: nil,
        stop: nil
      )
      # on_tick should capture the callback and invoke it with a price
      allow(fake_listener).to receive(:on_tick) do |&blk|
        blk.call("BTCUSDT", 95000.0)
        fake_listener
      end
      allow(fake_listener).to receive(:start) { raise Interrupt }
      allow(TradingAgent::Market::WsListener).to receive(:new).and_return(fake_listener)

      expect { shell.send(:print_live_ticker, "BTCUSDT") }.to output(/LTP:.*95000.*Stopped/m).to_stdout
    end
  end

  describe "#read_line" do
    context "when readline is available" do
      before { allow(shell).to receive(:readline_available?).and_return(true) }

      it "returns nil and prints newline when Interrupt is raised" do
        allow(Readline).to receive(:readline).and_raise(Interrupt)
        expect { expect(shell.send(:read_line)).to be_nil }.to output("\n").to_stdout
      end
    end
  end
end
