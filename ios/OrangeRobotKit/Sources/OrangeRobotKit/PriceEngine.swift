import Foundation

/// A single OHLC candle at any timeframe.
public struct Candle: Equatable, Sendable {
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
}

/// Turns real daily candles into a continuous intraday price path.
///
/// Daily and weekly candles are exactly the real data. Intraday movement is
/// procedural but anchored: it always starts at the previous real close, touches
/// the real high and low, and ends at the real close. It is a pure function of
/// (day index, minute), so replaying a window always gives the same path.
public final class PriceEngine {
    public let history: PriceHistory
    /// Day index into `history` where this run begins.
    public let startDay: Int

    /// Adds small deterministic flickers on top of the smooth intraday path so
    /// real-time play feels like a live market. The day's real open, high, low
    /// and close are untouched (the flicker fades to zero at every anchor).
    public let microMoves: Bool

    private var anchorCache: [Int: [Double]] = [:]
    private static let segments = 16
    private static let cacheLimit = 400

    public init(history: PriceHistory = .bundled, startDay: Int, microMoves: Bool = false) {
        self.history = history
        self.startDay = startDay
        self.microMoves = microMoves
    }

    /// Highest valid random start day (leaves 30 days of runway).
    public static func maxStartDay(for history: PriceHistory) -> Int { history.count - 30 }

    // MARK: Price

    public func price(atMinute absMinute: Double) -> Double {
        let dayIdx = startDay + Int(floor(absMinute / 1440))
        var m = absMinute.truncatingRemainder(dividingBy: 1440)
        if m < 0 { m += 1440 }
        return bridgeSample(dayIdx: dayIdx, fraction: m / 1440)
    }

    func bridgeSample(dayIdx: Int, fraction: Double) -> Double {
        let f = min(max(fraction, 0), 1)
        let anchors = dayAnchors(dayIdx)
        let n = anchors.count - 1
        let pos = f * Double(n)
        let i0 = min(n - 1, Int(floor(pos)))
        let t = pos - Double(i0)
        let s = t * t * (3 - 2 * t) // smoothstep
        let base = anchors[i0] + (anchors[i0 + 1] - anchors[i0]) * s
        guard microMoves else { return base }

        // Flicker: zero at both ends of every anchor segment, so anchors
        // (including the real high, low and close) are hit exactly.
        let envelope = 4 * t * (1 - t)
        if envelope <= 0 { return base }
        let bar = history.bar(at: dayIdx)
        let range = max(bar.high - bar.low, bar.close * 0.002)
        let amp = range * 0.010
        let minute = f * 1440
        let fine = Self.valueNoise(day: dayIdx, t: minute * 4, salt: 1)          // ~15 game-seconds
        let slow = Self.valueNoise(day: dayIdx, t: minute / 3, salt: 2)          // ~3 game-minutes
        let noisy = base + amp * envelope * (0.7 * fine + 1.1 * slow)
        // Never leave the day's real range (unless the path itself starts outside it).
        return min(max(noisy, min(bar.low, base)), max(bar.high, base))
    }

    /// Smooth value noise in [-1, 1], a pure function of (day, t).
    private static func valueNoise(day: Int, t: Double, salt: UInt32) -> Double {
        let i = Int(floor(t))
        let u = t - Double(i)
        func at(_ k: Int) -> Double {
            var g = Mulberry32(seed: UInt32(truncatingIfNeeded: Int64(day) &* 2_246_822_519 &+ Int64(k) &* 3_266_489_917)
                               ^ (salt &* 0x9E3779B9))
            _ = g.next()
            return g.next() * 2 - 1
        }
        let w = u * u * (3 - 2 * u)
        return at(i) + (at(i + 1) - at(i)) * w
    }

    private func dayAnchors(_ idx: Int) -> [Double] {
        if let cached = anchorCache[idx] { return cached }
        let bar = history.bar(at: idx)
        let prev = history.bar(at: idx - 1)
        let n = Self.segments
        var rng = Mulberry32(seed: UInt32(truncatingIfNeeded: Int64(idx) &* 2_654_435_761))

        var a = [Double](repeating: 0, count: n + 1)
        a[0] = prev.close
        a[n] = bar.close

        let hiPos = 2 + Int(floor(rng.next() * Double(n - 4)))
        var loPos = 2 + Int(floor(rng.next() * Double(n - 4)))
        while loPos == hiPos { loPos = 2 + Int(floor(rng.next() * Double(n - 4))) }
        a[hiPos] = bar.high
        a[loPos] = bar.low

        var fixed = [0, min(hiPos, loPos), max(hiPos, loPos), n]
        fixed = Array(Set(fixed)).sorted()
        let span = (bar.high - bar.low) == 0 ? 1 : (bar.high - bar.low)
        for s in 0..<(fixed.count - 1) {
            let lo = fixed[s], hi = fixed[s + 1]
            let va = a[lo], vb = a[hi]
            if hi - lo > 1 {
                for k in (lo + 1)..<hi {
                    let t = Double(k - lo) / Double(hi - lo)
                    var v = va + (vb - va) * t
                    v += (rng.next() - 0.5) * span * 0.35
                    a[k] = min(max(v, bar.low), bar.high)
                }
            }
        }
        for k in 0...n { a[k] = min(max(a[k], bar.low), bar.high) }
        a[0] = prev.close // keep true continuity even across a gap
        a[n] = bar.close

        if anchorCache.count >= Self.cacheLimit { anchorCache.removeAll(keepingCapacity: true) }
        anchorCache[idx] = a
        return a
    }

    // MARK: Candles

    /// The last `count` candles at `timeframeMinutes`, ending at `absMinute`
    /// (the final candle is the still-forming one). Candles before the run's
    /// start are included, back to the start of the dataset, so charts are full
    /// from the first second.
    public func candles(timeframeMinutes tf: Int, count: Int, atMinute absMinute: Double) -> [Candle] {
        var out: [Candle] = []
        if tf >= 1440 {
            let daysPerCandle = tf / 1440
            let curDay = Int(floor(absMinute / 1440))
            let curBucket = curDay / daysPerCandle
            var b = curBucket - count + 1
            while b <= curBucket {
                defer { b += 1 }
                let bucketStart = b * daysPerCandle
                // History before the run's start is real data a trader would have
                // seen; only stop at the beginning of the dataset itself.
                if startDay + bucketStart < 0 { continue }
                let isCurrent = (b == curBucket)
                let daysSoFar = isCurrent ? (curDay - bucketStart + 1) : daysPerCandle
                var o: Double?
                var h = -Double.infinity, l = Double.infinity, c = 0.0
                for d in 0..<daysSoFar {
                    let dayOffset = bucketStart + d
                    let bar = history.bar(at: startDay + dayOffset)
                    if o == nil { o = bar.open }
                    if isCurrent && d == daysSoFar - 1 {
                        let frac = absMinute.truncatingRemainder(dividingBy: 1440) / 1440
                        let samples = 12
                        var ph = -Double.infinity, pl = Double.infinity, pc = bar.open
                        for s in 0...samples {
                            let p = bridgeSample(dayIdx: startDay + dayOffset,
                                                 fraction: frac * Double(s) / Double(samples))
                            ph = max(ph, p); pl = min(pl, p); pc = p
                        }
                        h = max(h, ph, bar.open); l = min(l, pl, bar.open); c = pc
                    } else {
                        h = max(h, bar.high); l = min(l, bar.low); c = bar.close
                    }
                }
                if let o { out.append(Candle(open: o, high: h, low: l, close: c)) }
            }
        } else {
            let curBucket = Int(floor(absMinute / Double(tf)))
            var b = curBucket - count + 1
            while b <= curBucket {
                defer { b += 1 }
                if Double(b * tf) < -Double(startDay) * 1440 { continue }
                let t0 = Double(b * tf)
                let t1 = (b == curBucket) ? absMinute : t0 + Double(tf)
                if t1 <= t0 {
                    let p = price(atMinute: t0)
                    out.append(Candle(open: p, high: p, low: p, close: p))
                    continue
                }
                let samples = 10
                var o = 0.0, c = 0.0
                var h = -Double.infinity, l = Double.infinity
                for s in 0...samples {
                    let p = price(atMinute: t0 + (t1 - t0) * Double(s) / Double(samples))
                    if s == 0 { o = p }
                    if s == samples { c = p }
                    h = max(h, p); l = min(l, p)
                }
                h = max(h, o, c); l = min(l, o, c)
                out.append(Candle(open: o, high: h, low: l, close: c))
            }
        }
        return out
    }

    /// Real open of the day containing `absMinute` (for the "% today" readout).
    public func dayOpen(atMinute absMinute: Double) -> Double {
        history.bar(at: startDay + Int(floor(absMinute / 1440))).open
    }

    // MARK: Calendar

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Calendar date shown to the player for a given day offset into the run.
    public func date(forDayOffset dayOffset: Int) -> Date {
        let n = history.count
        let wrapped = (((startDay + dayOffset) % n) + n) % n
        return Self.utc.date(byAdding: .day, value: wrapped, to: history.startDate)!
    }
}

/// Mulberry32 PRNG, bit-for-bit identical to the web game's generator.
struct Mulberry32 {
    var state: UInt32
    init(seed: UInt32) { state = seed }

    mutating func next() -> Double {
        state = state &+ 0x6D2B79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }
}
