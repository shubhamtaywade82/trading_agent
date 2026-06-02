# frozen_string_literal: true

module TradingAgent
  class Runner
    attr_reader :exchange, :state, :risk_engine, :execution_manager,
                :llm_orchestrator, :symbols, :confirm, :prop_desk_mode

    def initialize(exchange:, model: "qwen2.5:14b", symbols: ["BTCUSDT"],
                   confirm: false, prop_desk: false, think: false)
      @exchange         = exchange
      @symbols          = symbols
      @confirm          = confirm
      @prop_desk_mode   = prop_desk
      @state            = Market::State.new
      @risk_engine      = Risk::Engine.new
      @execution_manager = Execution::Manager.new(exchange)
      @llm_orchestrator  = Llm::Orchestrator.new(@state, @exchange, model: model, think: think)

      if @prop_desk_mode
        backtest  = Validation::BacktestEngine.new(@exchange)
        optimizer = Validation::Optimizer.new(backtest)
        @coordinator = Coordinator::PropDesk.new(
          llm_orchestrator: @llm_orchestrator,
          backtest_engine:  backtest,
          optimizer:        optimizer,
          state:            @state
        )
      end

      setup_subscriptions
    end

    def start
      mode_label = @prop_desk_mode ? "prop-desk" : "standard"
      TradingAgent.logger.info("Starting Trading Agent",
                               symbols: @symbols, mode: mode_label, confirm: @confirm)
      Async do |task|
        begin
          update_initial_state
        rescue StandardError => e
          TradingAgent.logger.error("Failed to fetch initial state", error: e.message)
        end

        loop do
          begin
            refresh_market_state
            run_evaluation_cycle
          rescue StandardError => e
            TradingAgent.logger.error("Error in evaluation cycle", error: e.message)
          end

          task.sleep 60
        end
      end
    end

    private

    def setup_subscriptions
      EventBus.subscribe("market.tick") { |_| }
    end

    def update_initial_state
      @state.update_balances(@exchange.fetch_balances)
      positions = @exchange.fetch_positions
      positions.each { |pos| @state.update_position(pos[:symbol], pos) }
    rescue StandardError => e
      TradingAgent.logger.error("Failed to update initial state", error: e.message)
    end

    def refresh_market_state
      @symbols.each do |symbol|
        ticker = @exchange.fetch_ticker(symbol)
        @state.update_price(symbol, ticker[:price])

        # Keep 1h + 4h candle cache warm
        %w[4h 1h 15m].each do |tf|
          candles = @exchange.fetch_candles(symbol, tf, limit: 100)
          @state.update_candles(symbol, tf, candles)
        end
      end
    end

    def run_evaluation_cycle
      @symbols.each do |symbol|
        intent = if @prop_desk_mode
          @coordinator.run_pipeline(symbol)
        else
          context = {
            prices:    { symbol => @state.get_price(symbol) },
            balances:  @state.get_balances,
            drawdown:  @state.current_drawdown_pct,
            positions: { symbol => @state.get_position(symbol) }
          }
          @llm_orchestrator.analyze_and_plan(context)
        end

        next if intent.nil?

        EventBus.publish("llm.intent", intent: intent)
        next if intent[:action].to_s.upcase == "HOLD"

        validation = @risk_engine.validate_intent(intent, @state)
        EventBus.publish("risk.validated", intent: intent, validation: validation)

        if validation[:success]
          confirm_and_execute(intent)
        else
          TradingAgent.logger.warn("Intent rejected by Risk Engine",
                                   symbol: symbol, reason: validation[:reason])
        end
      end
    end

    def confirm_and_execute(intent)
      if @confirm
        print_proposed_intent(intent)
        print "Confirm execution? (y/N): "
        answer = $stdin.gets.to_s.strip.downcase
        if answer == "y" || answer == "yes"
          @execution_manager.execute_intent(intent, @state)
          update_initial_state
        else
          TradingAgent.logger.info("Trade execution cancelled by user")
        end
      else
        @execution_manager.execute_intent(intent, @state)
        update_initial_state
      end
    end

    def print_proposed_intent(intent)
      pf_line = intent[:final_pf] ? " | Validated PF: #{intent[:final_pf]}" : ""
      puts "\n=== PROPOSED TRADE INTENT#{" [PROP-DESK VALIDATED]" if @prop_desk_mode} ==="
      puts "Action:      #{intent[:action]}"
      puts "Symbol:      #{intent[:symbol]}"
      puts "Leverage:    #{intent[:leverage]}x"
      puts "Risk %:      #{intent[:risk_percent]}%"
      puts "Stop Loss:   #{intent[:stop_loss]}"
      puts "Take Profit: #{intent[:take_profit]}#{pf_line}"
      puts "Reasoning:"
      Array(intent[:reasoning]).each { |r| puts "  - #{r}" }
      puts "=" * 50
    end
  end
end
