# frozen_string_literal: true

module TradingAgent
  module Risk
    class Engine
      attr_reader :config

      def initialize(config = {})
        @config = {
          max_leverage: 5,
          max_position_size_pct: 0.1, # 10% of balance
          max_daily_drawdown_pct: 0.05, # 5%
          max_open_positions: 3
        }.merge(config)
      end

      def validate_intent(intent, state)
        action = intent[:action].to_s.upcase
        return { success: true } if action == "HOLD"

        # 1. Check max daily drawdown
        drawdown = state.current_drawdown_pct
        if drawdown > @config[:max_daily_drawdown_pct]
          return { success: false, reason: "Max daily drawdown exceeded: #{(drawdown * 100).round(2)}%" }
        end

        # 2. Check max open positions
        symbol = intent[:symbol]
        existing_pos = state.get_position(symbol)
        has_position = existing_pos && existing_pos[:position_amt].to_f.abs > 0.0
        
        if !has_position && state.open_positions_count >= @config[:max_open_positions]
          return { success: false, reason: "Max open positions reached" }
        end

        # 3. Check leverage
        if intent[:leverage].to_i > @config[:max_leverage]
          return { success: false, reason: "Leverage exceeds maximum allowed (#{@config[:max_leverage]})" }
        end

        # 4. Check position size notional value limit
        entry_price = state.get_price(symbol) || 0.0
        if entry_price.zero?
          # Fallback to current ticker price if state doesn't have it cached yet
          # risk engine shouldn't block if we can't find it, but let's be strict if not present anywhere
          return { success: false, reason: "Current price for #{symbol} is unavailable in state" }
        end

        stop_loss = intent[:stop_loss].to_f
        if stop_loss.zero?
          return { success: false, reason: "Stop loss must be specified for risk calculations" }
        end

        dist = (entry_price - stop_loss).abs
        if dist.zero?
          return { success: false, reason: "Stop loss cannot equal current entry price" }
        end

        equity = state.total_equity
        equity = 1000.0 if equity.zero? # local testing fallback

        risk_pct = intent[:risk_percent].to_f
        risk_amount = equity * (risk_pct / 100.0)
        
        # Position Size = Risk Amount / Price Distance
        position_size = risk_amount / dist
        notional_value = position_size * entry_price
        
        max_notional = equity * @config[:max_position_size_pct]

        if notional_value > max_notional
          return {
            success: false,
            reason: "Calculated position notional value #{notional_value.round(2)} exceeds maximum allowed #{max_notional.round(2)} (based on max_position_size_pct)"
          }
        end

        { success: true }
      end
    end
  end
end
