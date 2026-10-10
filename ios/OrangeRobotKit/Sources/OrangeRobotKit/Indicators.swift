import Foundation

/// Standard technical indicators computed from a series of closes.
/// Every function returns an array the same length as its input, with `nil`
/// where there isn't enough history yet.
public enum Indicators {

    /// Simple moving average.
    public static func sma(_ v: [Double], period: Int) -> [Double?] {
        guard period > 0, !v.isEmpty else { return [] }
        var out = [Double?](repeating: nil, count: v.count)
        var sum = 0.0
        for i in v.indices {
            sum += v[i]
            if i >= period { sum -= v[i - period] }
            if i >= period - 1 { out[i] = sum / Double(period) }
        }
        return out
    }

    /// Exponential moving average, seeded with the SMA of the first `period` values.
    public static func ema(_ v: [Double], period: Int) -> [Double?] {
        guard period > 0, v.count >= period else { return [Double?](repeating: nil, count: v.count) }
        var out = [Double?](repeating: nil, count: v.count)
        let k = 2.0 / Double(period + 1)
        var prev = v[0..<period].reduce(0, +) / Double(period)
        out[period - 1] = prev
        for i in period..<v.count {
            prev = v[i] * k + prev * (1 - k)
            out[i] = prev
        }
        return out
    }

    /// Relative Strength Index with Wilder's smoothing (0...100).
    public static func rsi(_ closes: [Double], period: Int = 14) -> [Double?] {
        var out = [Double?](repeating: nil, count: closes.count)
        guard period > 0, closes.count > period else { return out }
        var gain = 0.0, loss = 0.0
        for i in 1...period {
            let d = closes[i] - closes[i - 1]
            if d >= 0 { gain += d } else { loss -= d }
        }
        var avgGain = gain / Double(period)
        var avgLoss = loss / Double(period)
        func value() -> Double { avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss) }
        out[period] = value()
        if closes.count > period + 1 {
            for i in (period + 1)..<closes.count {
                let d = closes[i] - closes[i - 1]
                avgGain = (avgGain * Double(period - 1) + max(d, 0)) / Double(period)
                avgLoss = (avgLoss * Double(period - 1) + max(-d, 0)) / Double(period)
                out[i] = value()
            }
        }
        return out
    }

    public struct MACD: Equatable, Sendable {
        public let macd: [Double?]
        public let signal: [Double?]
        public let histogram: [Double?]
    }

    /// Moving Average Convergence Divergence (default 12 / 26 / 9).
    public static func macd(_ closes: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> MACD {
        let f = ema(closes, period: fast), s = ema(closes, period: slow)
        var line = [Double?](repeating: nil, count: closes.count)
        for i in closes.indices { if let a = f[i], let b = s[i] { line[i] = a - b } }

        // Signal = EMA of the MACD line, over the part of it that exists.
        var sig = [Double?](repeating: nil, count: closes.count)
        if let first = line.firstIndex(where: { $0 != nil }) {
            let tail = line[first...].map { $0! }
            let e = ema(tail, period: signal)
            for (k, v) in e.enumerated() { sig[first + k] = v }
        }
        var hist = [Double?](repeating: nil, count: closes.count)
        for i in closes.indices { if let m = line[i], let g = sig[i] { hist[i] = m - g } }
        return MACD(macd: line, signal: sig, histogram: hist)
    }

    public struct Bands: Equatable, Sendable {
        public let middle: [Double?]
        public let upper: [Double?]
        public let lower: [Double?]
    }

    /// Bollinger Bands: SMA ± `deviations` population standard deviations.
    public static func bollinger(_ closes: [Double], period: Int = 20, deviations: Double = 2) -> Bands {
        let mid = sma(closes, period: period)
        var up = [Double?](repeating: nil, count: closes.count)
        var lo = up
        guard period > 0 else { return Bands(middle: mid, upper: up, lower: lo) }
        for i in closes.indices where i >= period - 1 {
            guard let m = mid[i] else { continue }
            let window = closes[(i - period + 1)...i]
            let variance = window.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(period)
            let sd = variance.squareRoot()
            up[i] = m + deviations * sd
            lo[i] = m - deviations * sd
        }
        return Bands(middle: mid, upper: up, lower: lo)
    }
}
