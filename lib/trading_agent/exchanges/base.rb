# frozen_string_literal: true

module TradingAgent
  module Exchanges
    class Base
      def initialize(config = {})
        @config = config
      end

      def fetch_ticker(symbol)
        raise NotImplementedError
      end

      def fetch_candles(symbol, interval, limit: 100, start_time: nil, end_time: nil)
        raise NotImplementedError
      end

      def create_order(symbol, side, type, quantity, price: nil, params: {})
        raise NotImplementedError
      end

      def cancel_order(symbol, order_id)
        raise NotImplementedError
      end

      def fetch_positions
        raise NotImplementedError
      end

      def fetch_balances
        raise NotImplementedError
      end

      def set_leverage(symbol, leverage)
        raise NotImplementedError
      end

      def subscribe_market_data(symbols)
        raise NotImplementedError
      end
    end
  end
end
