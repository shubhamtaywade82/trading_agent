# frozen_string_literal: true

module TradingAgent
  module Execution
    class Manager
      attr_reader :exchange

      def initialize(exchange)
        @exchange = exchange
      end

      def execute_intent(intent, state)
        TradingAgent.logger.info("Executing trade intent", intent: intent)
        
        symbol = intent[:symbol]
        action = intent[:action].to_s.upcase
        return if action == "HOLD"

        # 1. Set Leverage for futures if supported
        if @exchange.respond_to?(:set_leverage) && intent[:leverage]
          begin
            @exchange.set_leverage(symbol, intent[:leverage].to_i)
          rescue StandardError => e
            TradingAgent.logger.error("Failed to set leverage on exchange", error: e.message)
          end
        end
        
        # 2. Calculate Quantity
        quantity = calculate_quantity(intent, state)
        if quantity.zero?
          TradingAgent.logger.warn("Calculated quantity is zero, skipping order placement", intent: intent)
          return
        end

        # 3. Place Main Order
        begin
          order = @exchange.create_order(
            symbol,
            action,
            "MARKET",
            quantity
          )
          TradingAgent.logger.info("Main order placed successfully", order: order)
        rescue StandardError => e
          TradingAgent.logger.error("Failed to place main order", error: e.message)
          raise Error, "Main order execution failed: #{e.message}"
        end
        
        # 4. Place Stop Loss (SL) Order
        if intent[:stop_loss] && intent[:stop_loss].to_f > 0.0
          sl_side = (action == "BUY") ? "SELL" : "BUY"
          begin
            sl_order = @exchange.create_order(
              symbol,
              sl_side,
              "STOP_MARKET",
              quantity,
              params: { stopPrice: intent[:stop_loss].to_f, reduceOnly: true }
            )
            TradingAgent.logger.info("Stop Loss order placed successfully", order: sl_order)
          rescue StandardError => e
            TradingAgent.logger.error("Failed to place Stop Loss order", error: e.message)
          end
        end

        # 5. Place Take Profit (TP) Order
        if intent[:take_profit] && intent[:take_profit].to_f > 0.0
          tp_side = (action == "BUY") ? "SELL" : "BUY"
          begin
            tp_order = @exchange.create_order(
              symbol,
              tp_side,
              "TAKE_PROFIT_MARKET",
              quantity,
              params: { stopPrice: intent[:take_profit].to_f, reduceOnly: true }
            )
            TradingAgent.logger.info("Take Profit order placed successfully", order: tp_order)
          rescue StandardError => e
            TradingAgent.logger.error("Failed to place Take Profit order", error: e.message)
          end
        end

        EventBus.publish("execution.started", intent: intent, quantity: quantity)
      end

      def calculate_quantity(intent, state)
        symbol = intent[:symbol]
        entry_price = state.get_price(symbol) || 0.0
        if entry_price.zero?
          begin
            entry_price = @exchange.fetch_ticker(symbol)[:price]
            state.update_price(symbol, entry_price)
          rescue StandardError
            return 0.0
          end
        end

        stop_loss = intent[:stop_loss].to_f
        return 0.0 if stop_loss.zero?

        dist = (entry_price - stop_loss).abs
        return 0.0 if dist.zero?

        equity = state.total_equity
        equity = 1000.0 if equity.zero?

        risk_pct = intent[:risk_percent].to_f
        risk_amount = equity * (risk_pct / 100.0)

        (risk_amount / dist).round(4)
      end
    end
  end
end
