# frozen_string_literal: true

require "readline"
require "json"
require "fileutils"

module TradingAgent
  class InteractiveShell
    PROMPT = "\e[36mtrader\e[0m \e[90m›\e[0m "
    HISTORY_FILE = File.join(Dir.home, ".config", "trading_agent", "repl_history")
    MAX_HISTORY  = 500

    def initialize(state, exchange, orchestrator)
      @state = state
      @exchange = exchange
      @orchestrator = orchestrator
    end

    def start
      setup_readline
      print_banner

      # Fetch initial balances and positions in background
      begin
        @state.update_balances(@exchange.fetch_balances)
        @exchange.fetch_positions.each { |p| @state.update_position(p[:symbol], p) }
      rescue StandardError => e
        puts "\e[33mWarning: Failed to fetch initial status: #{e.message}\e[0m"
      end

      loop do
        line = read_line
        break if line.nil?

        line = line.strip
        next if line.empty?

        break if %w[/exit /quit exit quit].include?(line)

        if line == "/help"
          print_help
        elsif line == "/balances" || line == "/bal"
          print_balances
        elsif line == "/positions" || line == "/pos"
          print_positions
        elsif line =~ %r{^/ticker\s+(\S+)}
          print_ticker($1)
        elsif line =~ %r{^/live\s+(\S+)}
          print_live_ticker($1)
        elsif line =~ %r{^/model\s+(\S+)}
          change_model($1)
        elsif line == "/model"
          puts "Current chat model: \e[1;32m#{@orchestrator.model}\e[0m"
        elsif line.start_with?("/")
          puts "\e[31mUnknown command: #{line}. Type /help for commands.\e[0m"
        else
          chat_with_advisor(line)
        end
      end

      puts "\n\e[90mGoodbye.\e[0m"
    ensure
      save_history
    end

    private

    def setup_readline
      return unless readline_available?

      begin
        FileUtils.mkdir_p(File.dirname(HISTORY_FILE))
        if File.exist?(HISTORY_FILE)
          File.readlines(HISTORY_FILE).each do |line|
            Readline::HISTORY.push(line.chomp)
          end
        end
      rescue StandardError => e
        # Silently fail if history file is not accessible
      end
    end

    def save_history
      return unless readline_available?

      begin
        File.open(HISTORY_FILE, "w") do |f|
          Readline::HISTORY.to_a.last(MAX_HISTORY).each do |line|
            f.puts(line)
          end
        end
      rescue StandardError
        # Silently fail if unable to save history
      end
    end

    def readline_available?
      defined?(Readline)
    end

    def read_line
      if readline_available?
        Readline.readline(PROMPT, true)
      else
        print PROMPT
        $stdout.flush
        $stdin.gets
      end
    rescue Interrupt
      puts ""
      nil
    end

    def print_banner
      puts "\e[1;36m" + "=" * 60
      puts "   TradingAgent Interactive Chat Shell (v#{TradingAgent::VERSION})"
      puts "   Model: \e[1;32m#{@orchestrator.model}\e[1;36m"
      puts "   Type \e[1;33m/help\e[1;36m for commands, \e[1;33m/quit\e[1;36m to exit."
      puts "=" * 60 + "\e[0m\n"
    end

    def print_help
      puts "\n\e[1;36mAvailable Commands:\e[0m"
      puts "  \e[33m/balances\e[0m or \e[33m/bal\e[0m   - View current account balances"
      puts "  \e[33m/positions\e[0m or \e[33m/pos\e[0m  - View current open positions"
      puts "  \e[33m/ticker <symbol>\e[0m    - Fetch current price of a symbol (e.g. /ticker BTCUSDT)"
      puts "  \e[33m/live <symbol>\e[0m      - Stream live LTP of a symbol in-place (e.g. /live BTCUSDT)"
      puts "  \e[33m/model [name]\e[0m       - View or switch the active chat model (e.g. /model qwen2.5:14b)"
      puts "  \e[33m/help\e[0m               - Show this help message"
      puts "  \e[33m/quit\e[0m or \e[33m/exit\e[0m      - Exit the shell"
      puts "  \e[90m<any other text>\e[0m    - Ask the LLM Trading Advisor a question\n\n"
    end

    def print_balances
      balances = @exchange.fetch_balances
      @state.update_balances(balances)
      if balances.empty?
        puts "\e[31mNo balances found or API keys missing.\e[0m"
      else
        puts "\n\e[1;36m=== Account Balances ===\e[0m"
        balances.each do |b|
          puts "Asset: \e[1m#{b[:asset].ljust(6)}\e[0m | Balance: \e[32m#{b[:balance].to_s.ljust(12)}\e[0m | Available: \e[32m#{b[:free]}\e[0m"
        end
        puts "\e[1;36m========================\e[0m\n\n"
      end
    end

    def print_positions
      positions = @exchange.fetch_positions
      positions.each { |p| @state.update_position(p[:symbol], p) }
      open_positions = positions.select { |p| p[:position_amt].to_f.abs > 0.0 }
      
      if open_positions.empty?
        puts "\e[33mNo open positions.\e[0m"
      else
        puts "\n\e[1;36m=== Open Positions ===\e[0m"
        open_positions.each do |p|
          puts "Symbol: \e[1m#{p[:symbol].ljust(10)}\e[0m | Size: \e[33m#{p[:position_amt].to_s.ljust(8)}\e[0m | Entry: \e[32m#{p[:entry_price].to_s.ljust(10)}\e[0m | Leverage: #{p[:leverage]}x | PnL: \e[32m#{p[:unrealized_profit]}\e[0m"
        end
        puts "\e[1;36m======================\e[0m\n\n"
      end
    end

    def print_ticker(symbol)
      symbol = symbol.upcase
      ticker = @exchange.fetch_ticker(symbol)
      @state.update_price(symbol, ticker[:price])
      puts "Current \e[1m#{symbol}\e[0m price: \e[1;32m#{ticker[:price]}\e[0m"
    rescue StandardError => e
      puts "\e[31mFailed to fetch ticker for #{symbol}: #{e.message}\e[0m"
    end

    def print_live_ticker(symbol)
      symbol  = symbol.upcase
      futures = symbol.end_with?("PERP") || @exchange.is_a?(TradingAgent::Exchanges::BinanceFutures)

      listener = Market::WsListener.new(@state, [symbol], futures: futures)

      # Each tick: overwrite the same terminal line with the latest price
      listener.on_tick do |sym, price|
        print "\r\e[32m●\e[0m \e[1m#{sym}\e[0m LTP: \e[1;33m$#{'%.4f' % price}\e[0m  \e[90m#{Time.now.strftime('%H:%M:%S.%L')}\e[0m   "
        $stdout.flush
      end

      puts "\e[36mStreaming \e[1m#{symbol}\e[0m via WebSocket. Press \e[1mCtrl+C\e[0m to return to shell...\e[0m"

      listener.start
      # Block this shell method until Ctrl+C interrupts — the WS thread does all the work
      sleep
    rescue Interrupt
      puts "\n\e[36mStopped streaming.\e[0m\n"
    ensure
      listener&.stop
    end

    def chat_with_advisor(query)
      market_context = {
        prices: @state.get_balances.map { |b| [b[:asset] + "USDT", @state.get_price(b[:asset] + "USDT")] }.reject { |k, v| v.nil? }.to_h,
        balances: @state.get_balances,
        drawdown: @state.current_drawdown_pct,
        user_question: query
      }

      prompt = <<~PROMPT
        User Question: #{query}
        
        Current Market Context:
        #{market_context.to_json}
        
        Analyze the user's query relative to the current market context. Feel free to use check_indicators or fetch_market_context tools if necessary.
        Respond to their question directly and concisely as a trading advisor. Respond in natural text (Markdown formatting is okay).
      PROMPT
      
      puts "\e[90mAdvisor is analyzing...\e[0m"
      response = @orchestrator.free_chat(prompt)
      puts "\n\e[1;36m╔═ Advisor ═══════════════════════════════════════════╗\e[0m"
      puts OllamaAgent::Console.format_assistant(response.to_s)
      puts "\e[1;36m╚═════════════════════════════════════════════════════╝\e[0m\n"
    end

    def change_model(name)
      old_model = @orchestrator.model
      @orchestrator.assign_chat_model!(name)
      puts "Changed model from \e[1;31m#{old_model}\e[0m to \e[1;32m#{@orchestrator.model}\e[0m"
    rescue StandardError => e
      puts "\e[31mFailed to change model: #{e.message}\e[0m"
    end
  end
end
