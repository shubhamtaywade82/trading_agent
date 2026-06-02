# frozen_string_literal: true

module TradingAgent
  module Llm
    class Orchestrator
      MAX_REPAIR_ATTEMPTS = 3

      def initialize(state, exchange, model: "qwen2.5:14b", think: false)
        ToolRegistry.register_all(state, exchange)
        resolved_model = model || ENV["OLLAMA_AGENT_MODEL"] || ENV["OLLAMA_MODEL"] || ENV["MODEL"] || "qwen2.5:14b"
        runner_opts = {
          model:         resolved_model,
          system_prompt: system_prompt,
          read_only:     true
        }
        runner_opts[:think] = "medium" if think
        @agent = OllamaAgent::Runner.build(**runner_opts)
        @schema = Validation::Schemas::TradeIntent.new
      end

      def model
        @agent.model
      end

      def assign_chat_model!(name)
        @agent.assign_chat_model!(name)
      end

      def analyze_and_plan(market_context)
        prompt = build_prompt(market_context)
        intent = run_with_repair(prompt)
        return nil if intent.nil?

        validate_and_coerce(intent)
      end

      def free_chat(prompt)
        last_response = nil
        @agent.hooks.on(:on_complete)          { |p| last_response = p[:messages]&.last }
        @agent.hooks.on(:on_assistant_message) { |_| }
        @agent.run(prompt)
        return "No response received." if last_response.nil?

        last_response[:content] || last_response["content"]
      end

      private

      # Run the agent and attempt up to MAX_REPAIR_ATTEMPTS auto-repairs on schema failure.
      def run_with_repair(prompt)
        current_prompt = prompt
        MAX_REPAIR_ATTEMPTS.times do |attempt|
          raw = execute_agent(current_prompt)
          return nil if raw.nil?

          parsed = safe_parse_json(raw)
          return parsed if parsed

          TradingAgent.logger.warn("JSON parse failed, sending repair prompt",
                                   attempt: attempt + 1, snippet: raw.to_s[0, 200])
          current_prompt = repair_prompt(raw)
        end

        TradingAgent.logger.error("All repair attempts exhausted — returning nil")
        nil
      end

      def execute_agent(prompt)
        last_response = nil
        @agent.hooks.on(:on_complete) { |p| last_response = p[:messages]&.last }
        @agent.run(prompt)
        return nil if last_response.nil?

        last_response[:content] || last_response["content"]
      rescue StandardError => e
        TradingAgent.logger.error("Agent execution error", error: e.message)
        nil
      end

      def safe_parse_json(content)
        return nil if content.to_s.strip.empty?

        OllamaAgent::Skills::JsonExtractor.parse(content)
      rescue OllamaAgent::Skills::JsonExtractor::ExtractionError, JSON::ParserError
        nil
      end

      def validate_and_coerce(intent)
        result = @schema.call(
          action:       intent[:action].to_s,
          symbol:       intent[:symbol].to_s,
          leverage:     intent[:leverage].to_i,
          risk_percent: intent[:risk_percent].to_f,
          stop_loss:    intent[:stop_loss].to_f,
          take_profit:  intent[:take_profit].to_f
        )

        if result.success?
          intent
        else
          TradingAgent.logger.warn("Trade intent failed schema validation",
                                   errors: result.errors.to_h)
          nil
        end
      end

      def build_prompt(context)
        "Current Market Context:\n#{context.to_json}\n\n" \
          "Use the available tools (fetch_multi_timeframe_context, analyze_microstructure, detect_patterns) " \
          "to gather data, then respond with a JSON trade intent."
      end

      def repair_prompt(bad_response)
        <<~REPAIR
          Your previous response could not be parsed as valid JSON or did not match the required schema.
          Previous response: #{bad_response.to_s[0, 500]}

          You MUST respond with a single JSON object containing exactly these keys:
            action       (string: "BUY", "SELL", or "HOLD")
            symbol       (string: e.g. "BTCUSDT")
            leverage     (integer: 1..20)
            risk_percent (float: 0.1..5.0)
            stop_loss    (float)
            take_profit  (float)
            reasoning    (array of strings)

          Do not include any explanation, markdown, or code fences — just the raw JSON object.
        REPAIR
      end

      def system_prompt
        <<~PROMPT
          You are an expert crypto prop-desk quantitative trading agent operating on Binance Futures.

          WORKFLOW:
          1. Call fetch_multi_timeframe_context to get macro (4h/1h) and micro (15m/1m) context.
          2. Call analyze_microstructure to assess volume delta and absorption on 1m bars.
          3. Call detect_patterns to identify order blocks, liquidity sweeps, and premium/discount zones.
          4. Only propose a trade if all three timeframe perspectives align.

          OUTPUT FORMAT (strict JSON — no markdown, no code fences):
          {
            "action":       "BUY" | "SELL" | "HOLD",
            "symbol":       "BTCUSDT",
            "leverage":     3,
            "risk_percent": 1.0,
            "stop_loss":    95000.0,
            "take_profit":  105000.0,
            "reasoning":    ["4h bullish structure", "1m volume delta turning positive", "Price in discount zone"]
          }

          RULES:
          - Never risk more than 2% per trade (risk_percent ≤ 2.0).
          - Stop loss MUST be beyond the nearest structural level (order block / swing).
          - When in doubt, output HOLD.
        PROMPT
      end
    end
  end
end
