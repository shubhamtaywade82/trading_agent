# frozen_string_literal: true

require "websocket-eventmachine-client"
require "json"

module TradingAgent
  module Market
    # Connects to Binance WebSocket streams and keeps Market::State price cache
    # up-to-date in real time. Also fires an optional on_tick callback so callers
    # (e.g. the interactive shell's /live command) can react to every price update.
    #
    # Usage:
    #   listener = WsListener.new(state, ["BTCUSDT", "SOLUSDT"])
    #   listener.on_tick { |symbol, price| ... }
    #   listener.start   # non-blocking — runs EventMachine in a background thread
    #   ...
    #   listener.stop    # graceful teardown
    class WsListener
      # Binance Spot public stream base URL (no auth required for market data)
      SPOT_STREAM_BASE = "wss://stream.binance.com:9443"

      # Binance USD-M Futures stream base URL
      FUTURES_STREAM_BASE = "wss://fstream.binance.com"

      attr_reader :connected

      def initialize(state, symbols, futures: false)
        @state    = state
        @symbols  = Array(symbols).map { |s| s.upcase }
        @futures  = futures
        @tick_cbs = []
        @connected = false
        @thread   = nil
        @ws       = nil
      end

      # Register a block that is called on every price tick:
      #   listener.on_tick { |symbol, price| puts "#{symbol}: #{price}" }
      def on_tick(&block)
        @tick_cbs << block
        self
      end

      # Start the WebSocket listener in a background thread.
      # EventMachine requires its own thread when used alongside blocking I/O.
      def start
        return if @thread&.alive?

        @thread = Thread.new { run_event_loop }
        @thread.abort_on_exception = false
        self
      end

      # Gracefully stop EventMachine and the background thread.
      def stop
        EventMachine.stop_event_loop if EventMachine.reactor_running?
        @thread&.join(3)
        @connected = false
      end

      private

      def stream_url
        base = @futures ? FUTURES_STREAM_BASE : SPOT_STREAM_BASE
        # Combined stream: wss://…/stream?streams=btcusdt@miniTicker/solusdt@miniTicker
        streams = @symbols.map { |sym| "#{sym.downcase}@miniTicker" }.join("/")
        "#{base}/stream?streams=#{streams}"
      end

      def run_event_loop
        EventMachine.run do
          @ws = WebSocket::EventMachine::Client.connect(uri: stream_url)

          @ws.onopen do
            @connected = true
            TradingAgent.logger.info("WS connected", symbols: @symbols, futures: @futures)
          end

          @ws.onmessage do |raw, _type|
            handle_message(raw)
          end

          @ws.onerror do |err|
            TradingAgent.logger.error("WS error", error: err.to_s)
          end

          @ws.onclose do |code, reason|
            @connected = false
            TradingAgent.logger.info("WS closed", code: code, reason: reason)
            # Reconnect after 3 s unless the reactor is stopping
            EventMachine.add_timer(3) { reconnect } if EventMachine.reactor_running?
          end
        end
      rescue StandardError => e
        TradingAgent.logger.error("WS event loop crashed", error: e.message)
      end

      def reconnect
        TradingAgent.logger.info("WS reconnecting…")
        @ws = WebSocket::EventMachine::Client.connect(uri: stream_url)
        # Re-attach callbacks (same logic — extracted to keep onopen/onmessage DRY)
        run_event_loop
      end

      def handle_message(raw)
        envelope = JSON.parse(raw)
        # Combined stream wraps the payload under "data"
        data = envelope["data"] || envelope

        symbol = data["s"]&.upcase
        # miniTicker uses "c" for the last (close/last traded) price
        price  = data["c"]&.to_f

        return unless symbol && price

        @state.update_price(symbol, price)
        fire_tick(symbol, price)
      rescue JSON::ParserError
        # Ignore malformed frames
      end

      def fire_tick(symbol, price)
        @tick_cbs.each { |cb| cb.call(symbol, price) }
      end
    end
  end
end
