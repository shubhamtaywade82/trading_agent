# frozen_string_literal: true

require "binance"

module TradingAgent
  module Exchanges
    class BinanceSpot < Base
      def initialize(api_key: nil, secret_key: nil, testnet: true)
        super
        @api_key = api_key
        @secret_key = secret_key
        base_url = testnet ? "https://testnet.binance.vision" : "https://api.binance.com"
        @client = Binance::Spot.new(
          key: api_key,
          secret: secret_key,
          base_url: base_url
        )
      end

      def fetch_ticker(symbol)
        response = @client.ticker_price(symbol: symbol)
        { price: response[:price].to_f }
      rescue StandardError => e
        TradingAgent.logger.error("Failed to fetch ticker for #{symbol}", error: e.message)
        { price: 0.0 }
      end

      def fetch_candles(symbol, interval, limit: 100)
        @client.klines(symbol: symbol, interval: interval, limit: limit)
      rescue StandardError => e
        TradingAgent.logger.error("Failed to fetch candles for #{symbol}", error: e.message)
        []
      end

      def create_order(symbol, side, type, quantity, price: nil, params: {})
        options = params.merge(
          symbol: symbol,
          side: side.to_s.upcase,
          type: type.to_s.upcase,
          quantity: quantity
        )
        options[:price] = price if price
        options[:timeInForce] = "GTC" if type.to_s.upcase == "LIMIT" && !options[:timeInForce]
        
        @client.new_order(**options)
      rescue StandardError => e
        TradingAgent.logger.error("Failed to create spot order", error: e.message)
        raise Error, "Spot order placement failed: #{e.message}"
      end

      def fetch_positions
        # For spot, "positions" are just balances with free amount > 0
        fetch_balances.select { |b| b[:free].to_f > 0 }
      end

      def fetch_balances
        return [] if @api_key.to_s.empty? || @secret_key.to_s.empty?

        response = @client.account
        response[:balances].map do |bal|
          {
            asset: bal[:asset],
            balance: bal[:free].to_f + bal[:locked].to_f,
            free: bal[:free].to_f,
            locked: bal[:locked].to_f
          }
        end
      rescue Binance::ClientError => e
        TradingAgent.logger.error("Failed to fetch balances", error: e.message)
        []
      end
    end
  end
end
