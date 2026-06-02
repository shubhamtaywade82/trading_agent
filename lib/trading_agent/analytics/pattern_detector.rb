# frozen_string_literal: true

module TradingAgent
  module Analytics
    class PatternDetector
      include SemanticLogger::Loggable

      # Last bearish candle before a bullish impulse → bullish order block
      # Last bullish candle before a bearish impulse → bearish order block
      def detect_order_blocks(candles, impulse_len: 3)
        return { bullish: [], bearish: [] } if candles.size < impulse_len + 2

        bullish_obs = []
        bearish_obs = []

        (0..(candles.size - impulse_len - 2)).each do |i|
          c       = candles[i]
          impulse = candles[(i + 1)..(i + impulse_len)]
          next unless impulse.size == impulse_len

          o = c[1].to_f
          cl = c[4].to_f

          if cl < o  # bearish base candle
            if impulse.all? { |nc| nc[4].to_f > nc[1].to_f }
              bullish_obs << {
                time:          c[0],
                high:          c[2].to_f.round(4),
                low:           c[3].to_f.round(4),
                open:          o.round(4),
                close:         cl.round(4),
                impulse_range: impulse_strength(impulse).round(4)
              }
            end
          elsif cl > o  # bullish base candle
            if impulse.all? { |nc| nc[4].to_f < nc[1].to_f }
              bearish_obs << {
                time:          c[0],
                high:          c[2].to_f.round(4),
                low:           c[3].to_f.round(4),
                open:          o.round(4),
                close:         cl.round(4),
                impulse_range: impulse_strength(impulse).round(4)
              }
            end
          end
        end

        { bullish: bullish_obs.last(3), bearish: bearish_obs.last(3) }
      end

      # Wick below key swing low (then reclaim) = bullish liquidity sweep
      # Wick above key swing high (then reclaim) = bearish liquidity sweep
      def detect_liquidity_sweeps(candles, lookback: 40)
        return [] if candles.size < lookback + 2

        sweeps = []
        tail   = candles.last(lookback + 2)

        (lookback..(tail.size - 2)).each do |i|
          c    = tail[i]
          prev = tail[0...i]

          low   = c[3].to_f
          high  = c[2].to_f
          close = c[4].to_f
          open  = c[1].to_f

          recent_lows  = prev.last(20).map { |p| p[3].to_f }
          recent_highs = prev.last(20).map { |p| p[2].to_f }
          swing_low  = recent_lows.min
          swing_high = recent_highs.max
          tol = 0.002

          if low < swing_low * (1 - tol) && close > swing_low && close > open
            sweeps << { type: :bullish, time: c[0], swept_level: swing_low.round(4),
                        wick_low: low.round(4), close: close.round(4) }
          end

          if high > swing_high * (1 + tol) && close < swing_high && close < open
            sweeps << { type: :bearish, time: c[0], swept_level: swing_high.round(4),
                        wick_high: high.round(4), close: close.round(4) }
          end
        end

        sweeps.last(5)
      end

      # 50% equilibrium split: above = premium (short bias), below = discount (long bias)
      def detect_premium_discount_zones(candles, lookback: 100)
        slice      = candles.last([lookback, candles.size].min)
        swing_high = slice.map { |c| c[2].to_f }.max
        swing_low  = slice.map { |c| c[3].to_f }.min
        range      = swing_high - swing_low
        eq         = swing_low + range / 2.0
        current    = candles.last[4].to_f

        disc_ceil   = swing_low + range * 0.35
        prem_floor  = swing_low + range * 0.65

        zone = if current <= disc_ceil
          :discount
        elsif current >= prem_floor
          :premium
        else
          :equilibrium
        end

        {
          swing_high:                  swing_high.round(4),
          swing_low:                   swing_low.round(4),
          equilibrium:                 eq.round(4),
          discount_ceiling:            disc_ceil.round(4),
          premium_floor:               prem_floor.round(4),
          current_price:               current.round(4),
          zone:                        zone,
          distance_to_eq_pct:          ((current - eq).abs / eq * 100).round(2)
        }
      end

      private

      def impulse_strength(candles)
        candles.sum { |c| (c[4].to_f - c[1].to_f).abs }
      end
    end
  end
end
