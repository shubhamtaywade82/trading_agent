# frozen_string_literal: true

module TradingAgent
  class EventBus
    include Dry::Events::Publisher[:trading_agent]

    register_event("market.tick")
    register_event("market.candle_closed")
    register_event("order.created")
    register_event("order.filled")
    register_event("position.updated")
    register_event("strategy.signal")
    register_event("llm.intent")
    register_event("risk.validated")
    register_event("execution.started")

    def self.instance
      @instance ||= new
    end

    def self.publish(event_id, payload = {})
      instance.publish(event_id, payload)
    end

    def self.subscribe(event_id, &block)
      instance.subscribe(event_id, &block)
    end
  end
end
