# frozen_string_literal: true

module TradingAgent
  module Analytics
    class Engine
      include SemanticLogger::Loggable

      # Binance kline index reference:
      # 0=open_time 1=open 2=high 3=low 4=close 5=volume 6=close_time
      # 7=quote_vol 8=trades 9=taker_buy_base_vol 10=taker_buy_quote_vol

      def volume_delta(candles)
        candles.map do |c|
          taker_buy = c[9].to_f
          total     = c[5].to_f
          sell_vol  = total - taker_buy
          {
            time:        c[0],
            buy_volume:  taker_buy.round(4),
            sell_volume: sell_vol.round(4),
            delta:       (taker_buy - sell_vol).round(4),
            total:       total.round(4)
          }
        end
      end

      def cumulative_delta(candles)
        cum = 0.0
        volume_delta(candles).map do |d|
          cum += d[:delta]
          d.merge(cumulative_delta: cum.round(4))
        end
      end

      # V / |ΔPrice| — high values indicate absorption (institutional flow)
      def volume_price_ratio(candles, smoothing: 20)
        ratios = candles.filter_map do |c|
          dp = (c[4].to_f - c[1].to_f).abs
          next if dp < 0.0001

          (c[5].to_f / dp).round(2)
        end
        return { latest_ratio: 0, average_ratio: 0, absorption_detected: false } if ratios.empty?

        window = [ratios.size, smoothing].min
        avg    = ratios.last(window).sum / window.to_f
        latest = ratios.last
        {
          latest_ratio:        latest,
          average_ratio:       avg.round(2),
          absorption_detected: latest > avg * 1.5
        }
      end

      def volume_spike(candles, threshold: 2.5, lookback: 20)
        vols   = candles.map { |c| c[5].to_f }
        window = [vols.size, lookback].min
        avg    = vols.last(window).sum / window.to_f
        latest = vols.last.to_f
        ratio  = avg.positive? ? (latest / avg).round(2) : 0.0
        {
          latest_volume: latest.round(4),
          volume_ma:     avg.round(4),
          spike_ratio:   ratio,
          is_spike:      ratio >= threshold
        }
      end

      def volatility_metrics(candles)
        return { bb_width: 0, atr: 0, compressed: false } if candles.size < 20

        bb  = bollinger_bands(candles)
        atr = Market::Indicators.atr(candles, 14).to_f
        {
          bb_upper:    bb[:upper].round(4),
          bb_lower:    bb[:lower].round(4),
          bb_middle:   bb[:middle].round(4),
          bb_width:    bb[:width].round(6),
          atr:         atr.round(4),
          compressed:  bb[:width] < bb[:width_baseline] * 0.7
        }
      end

      private

      def bollinger_bands(candles, period: 20, mult: 2.0)
        closes = candles.map { |c| c[4].to_f }
        return { upper: 0, lower: 0, middle: 0, width: 0, width_baseline: 0 } if closes.size < period

        recent = closes.last(period)
        mid    = recent.sum / period.to_f
        std    = Math.sqrt(recent.sum { |p| (p - mid)**2 } / period.to_f)
        upper  = mid + mult * std
        lower  = mid - mult * std
        width  = mid.positive? ? (upper - lower) / mid : 0.0

        # Baseline width over prior 50 bars
        width_baseline = if closes.size >= period + 20
          samples = []
          (period..(closes.size - 1)).step(5) do |i|
            w = closes[(i - period)...i]
            m = w.sum / period.to_f
            s = Math.sqrt(w.sum { |p| (p - m)**2 } / period.to_f)
            samples << (m.positive? ? (m + mult * s - (m - mult * s)) / m : 0)
          end
          samples.last(10).sum / [samples.size, 10].min
        else
          width
        end

        { upper: upper, lower: lower, middle: mid, width: width, width_baseline: width_baseline }
      end
    end
  end
end
