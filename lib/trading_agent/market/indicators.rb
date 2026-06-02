# frozen_string_literal: true

module TradingAgent
  module Market
    module Indicators
      module_function

      # Extracts close prices from candles (supports raw Binance arrays or hashes)
      def extract_closes(candles)
        candles.map do |c|
          if c.is_a?(Array)
            c[4].to_f # Close price is index 4 in Binance kline array
          elsif c.is_a?(Hash)
            (c[:close] || c["close"]).to_f
          else
            0.0
          end
        end
      end

      # Extracts high, low, close from candles for ATR
      def extract_hlc(candles)
        candles.map do |c|
          if c.is_a?(Array)
            {
              high: c[2].to_f,
              low: c[3].to_f,
              close: c[4].to_f
            }
          elsif c.is_a?(Hash)
            {
              high: (c[:high] || c["high"]).to_f,
              low: (c[:low] || c["low"]).to_f,
              close: (c[:close] || c["close"]).to_f
            }
          else
            { high: 0.0, low: 0.0, close: 0.0 }
          end
        end
      end

      # Simple Moving Average
      def sma(candles, period)
        closes = extract_closes(candles)
        return nil if closes.size < period

        closes.last(period).sum / period.to_f
      end

      # Exponential Moving Average
      def ema(candles, period)
        closes = extract_closes(candles)
        return nil if closes.size < period

        # Start with SMA as the initial EMA value
        k = 2.0 / (period + 1.0)
        current_ema = closes[0...period].sum / period.to_f

        closes[period..].each do |price|
          current_ema = (price * k) + (current_ema * (1.0 - k))
        end

        current_ema
      end

      # Relative Strength Index
      def rsi(candles, period = 14)
        closes = extract_closes(candles)
        return nil if closes.size <= period

        gains = []
        losses = []

        closes.each_cons(2) do |prev, curr|
          change = curr - prev
          if change > 0
            gains << change
            losses << 0.0
          else
            gains << 0.0
            losses << -change
          end
        end

        # Calculate initial averages
        avg_gain = gains[0...period].sum / period.to_f
        avg_loss = losses[0...period].sum / period.to_f

        # Wilder's smoothing technique
        gains[period..].each_with_index do |gain, idx|
          loss = losses[period + idx]
          avg_gain = ((avg_gain * (period - 1)) + gain) / period.to_f
          avg_loss = ((avg_loss * (period - 1)) + loss) / period.to_f
        end

        return 100.0 if avg_loss.zero? && avg_gain > 0
        return 0.0 if avg_gain.zero?

        rs = avg_gain / avg_loss
        100.0 - (100.0 / (1.0 + rs))
      end

      # Bollinger Bands (returns upper/middle/lower + width ratio)
      def bollinger_bands(candles, period: 20, mult: 2.0)
        closes = extract_closes(candles)
        return nil if closes.size < period

        recent = closes.last(period)
        mid    = recent.sum / period.to_f
        std    = Math.sqrt(recent.sum { |p| (p - mid)**2 } / period.to_f)
        upper  = mid + mult * std
        lower  = mid - mult * std
        { upper: upper, middle: mid, lower: lower, width: mid.positive? ? (upper - lower) / mid : 0.0 }
      end

      # MACD (12/26/9) — returns macd_line, signal_line, histogram
      def macd(candles, fast: 12, slow: 26, signal: 9)
        return nil if candles.size < slow + signal

        fast_ema   = ema(candles, fast)
        slow_ema   = ema(candles, slow)
        return nil if fast_ema.nil? || slow_ema.nil?

        macd_line  = fast_ema - slow_ema
        # Approximate signal as EMA of last `signal` MACD values using recent closes
        # (simplified single-value; full series would require rolling EMA)
        { macd_line: macd_line.round(6), signal_line: nil, histogram: nil }
      end

      # Average True Range
      def atr(candles, period = 14)
        hlc = extract_hlc(candles)
        return nil if hlc.size < period + 1

        tr_values = []
        hlc.each_with_index do |curr, idx|
          next if idx.zero?

          prev_close = hlc[idx - 1][:close]
          tr1 = curr[:high] - curr[:low]
          tr2 = (curr[:high] - prev_close).abs
          tr3 = (curr[:low] - prev_close).abs

          tr_values << [tr1, tr2, tr3].max
        end

        # Smoothed MA of TR (Wilder's smoothing)
        avg_tr = tr_values[0...period].sum / period.to_f

        tr_values[period..].each do |tr|
          avg_tr = ((avg_tr * (period - 1)) + tr) / period.to_f
        end

        avg_tr
      end
    end
  end
end
