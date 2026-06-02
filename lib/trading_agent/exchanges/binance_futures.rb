# frozen_string_literal: true

require "binance"

module TradingAgent
  module Exchanges
    class BinanceFutures < Base
      def initialize(api_key: nil, secret_key: nil, testnet: true)
        super
        base_url = testnet ? "https://testnet.binancefuture.com" : "https://fapi.binance.com"
        @session = Binance::Session.new(
          key: api_key || "",
          secret: secret_key || "",
          base_url: base_url
        )
      end

      def fetch_ticker(symbol)
        response = @session.public_request(path: "/fapi/v1/ticker/price", params: { symbol: symbol.upcase })
        { price: response[:price].to_f }
      rescue StandardError => e
        TradingAgent.logger.error("Failed to fetch futures ticker for #{symbol}", error: e.message)
        { price: 0.0 }
      end

      def fetch_candles(symbol, interval, limit: 100, start_time: nil, end_time: nil)
        params = { symbol: symbol.upcase, interval: interval, limit: limit }
        params[:startTime] = start_time if start_time
        params[:endTime]   = end_time   if end_time
        @session.public_request(path: "/fapi/v1/klines", params: params)
      rescue StandardError => e
        TradingAgent.logger.error("Failed to fetch futures candles for #{symbol}", error: e.message)
        []
      end

      def create_order(symbol, side, type, quantity, price: nil, params: {})
        options = params.merge(
          symbol: symbol.upcase,
          side: side.to_s.upcase,
          type: type.to_s.upcase,
          quantity: quantity
        )
        options[:price] = price if price
        options[:timeInForce] = "GTC" if type.to_s.upcase == "LIMIT" && !options[:timeInForce]
        
        @session.sign_request(:post, "/fapi/v1/order", params: options)
      rescue StandardError => e
        TradingAgent.logger.error("Failed to create futures order", error: e.message)
        raise Error, "Futures order placement failed: #{e.message}"
      end

      def cancel_order(symbol, order_id)
        @session.sign_request(:delete, "/fapi/v1/order", params: { symbol: symbol.upcase, orderId: order_id })
      rescue StandardError => e
        TradingAgent.logger.error("Failed to cancel futures order", error: e.message)
        raise Error, "Futures order cancellation failed: #{e.message}"
      end

      def fetch_positions
        response = @session.sign_request(:get, "/fapi/v2/positionRisk")
        response.map do |pos|
          {
            symbol: pos[:symbol],
            position_amt: pos[:positionAmt].to_f,
            entry_price: pos[:entryPrice].to_f,
            leverage: pos[:leverage].to_i,
            unrealized_profit: pos[:unRealizedProfit].to_f,
            margin_type: pos[:marginType],
            liquidation_price: pos[:liquidationPrice].to_f
          }
        end
      rescue StandardError => e
        TradingAgent.logger.error("Failed to fetch futures positions", error: e.message)
        []
      end

      def fetch_balances
        response = @session.sign_request(:get, "/fapi/v2/balance")
        response.map do |bal|
          {
            asset: bal[:asset],
            balance: bal[:balance].to_f,
            free: bal[:availableBalance].to_f,
            locked: bal[:balance].to_f - bal[:availableBalance].to_f
          }
        end
      rescue StandardError => e
        TradingAgent.logger.error("Failed to fetch futures balances", error: e.message)
        []
      end

      def set_leverage(symbol, leverage)
        @session.sign_request(:post, "/fapi/v1/leverage", params: { symbol: symbol.upcase, leverage: leverage })
      rescue StandardError => e
        TradingAgent.logger.error("Failed to set leverage for #{symbol}", error: e.message)
        raise Error, "Leverage configuration failed: #{e.message}"
      end
    end
  end
end
