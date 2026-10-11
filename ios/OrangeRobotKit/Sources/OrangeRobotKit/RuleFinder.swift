import Foundation

/// How a found rule set behaved on time it was *not* tuned on.
public struct Robustness: Equatable, Sendable {
    /// How many other periods of the same length were tried.
    public let windows: Int
    public let medianReturn: Double
    /// Share of those periods that ended in profit (0...1).
    public let positiveShare: Double
    /// Share of those periods where the rules beat simply holding.
    public let beatsHoldShare: Double
}

public enum Verdict: String, Codable, Sendable {
    /// Made money on time it never saw *and* beat simply holding in at least half of those periods.
    case holdsUp
    /// Made money on unseen time but holding did better; the ride was smoother (smaller drops).
    case steadier
    case mixed
    /// Looked great on the practice period, then fell apart.
    case fellApart

    public var title: String {
        switch self {
        case .holdsUp: return "Beat holding"
        case .steadier: return "Smoother, but holding won"
        case .mixed: return "Mixed"
        case .fellApart: return "Fell apart"
        }
    }

    public var explanation: String {
        switch self {
        case .holdsUp: return "Kept making money on periods it was not tuned on, and beat just holding Bitcoin in at least half of them."
        case .steadier: return "Made money on unseen periods with smaller drops, but simply holding Bitcoin earned more."
        case .mixed: return "Some unseen periods went well and some didn't. Treat it as a maybe."
        case .fellApart: return "Great on the practice period, poor on periods it had not seen. A classic case of fitting the past."
        }
    }
}

public struct Candidate: Identifiable, Sendable {
    public let id: Int
    public let strategy: Strategy
    public let train: Metrics
    public let trainBuyAndHold: Metrics
    /// The stretch right after (or, failing that, before) the training period.
    public let validationDays: Range<Int>?
    public let validation: Metrics?
    public let validationBuyAndHold: Metrics?
    public let robustness: Robustness?
    public let verdict: Verdict
}

public struct FinderRequest: Sendable {
    /// The historical period the robot practices on (indices into the price history).
    public var trainDays: Range<Int>
    /// How many random rule sets to try.
    public var candidates = 1_500
    /// How many to return.
    public var keep = 8
    /// Rules that trade fewer times than this are ignored (too lucky to trust).
    public var minTrades = 3
    public var settings = BacktestSettings()
    /// Same request -> same answer.
    public var seed: UInt64?

    public init(trainDays: Range<Int>) { self.trainDays = trainDays }
}

/// Searches for rules that did well over a chosen historical period, then
/// checks them on periods they weren't tuned on.
public final class RuleFinder {
    public let backtester: Backtester

    public init(backtester: Backtester = Backtester()) {
        self.backtester = backtester
    }

    public func find(_ request: FinderRequest,
                     progress: ((Double) -> Void)? = nil,
                     isCancelled: () -> Bool = { false }) -> [Candidate] {
        let train = request.trainDays
        guard train.count >= 60 else { return [] }
        var rng = SplitMix64(seed: request.seed ?? Self.defaultSeed(train))
        let hold = backtester.buyAndHold(days: train, settings: request.settings).metrics

        // 1. Try lots of random rule sets on the practice period.
        var scored: [(Strategy, Metrics, Double)] = []
        for n in 0..<request.candidates {
            if isCancelled() { break }
            let s = RuleGenerator.random(using: &rng)
            let r = backtester.run(s, days: train, settings: request.settings)
            if r.metrics.trades >= request.minTrades, r.metrics.exposure >= 0.03 {
                let fitness = r.metrics.totalReturn - 0.5 * r.metrics.maxDrawdown
                scored.append((s, r.metrics, fitness))
            }
            if n % 50 == 0 { progress?(Double(n) / Double(request.candidates) * 0.8) }
        }

        // 2. Best first; keep a mix (at most two per entry idea).
        scored.sort { $0.2 > $1.2 }
        var picked: [(Strategy, Metrics, Double)] = []
        var perFamily: [String: Int] = [:]
        for item in scored {
            let family = RuleGenerator.family(of: item.0)
            if perFamily[family, default: 0] >= 2 { continue }
            perFamily[family, default: 0] += 1
            picked.append(item)
            if picked.count >= request.keep { break }
        }

        // 3. Test the winners on time they never saw.
        let valRange = Self.validationRange(after: train, total: backtester.dayCount)
        let others = Self.otherWindows(length: train.count, avoiding: train, total: backtester.dayCount, count: 6)
        var out: [Candidate] = []
        for (i, item) in picked.enumerated() {
            if isCancelled() { break }
            let (s, trainM, _) = item
            var v: Metrics?, vHold: Metrics?
            if let vr = valRange {
                v = backtester.run(s, days: vr, settings: request.settings).metrics
                vHold = backtester.buyAndHold(days: vr, settings: request.settings).metrics
            }
            var rob: Robustness?
            if !others.isEmpty {
                var rets: [Double] = [], beats = 0
                for w in others {
                    let m = backtester.run(s, days: w, settings: request.settings).metrics
                    let h = backtester.buyAndHold(days: w, settings: request.settings).metrics
                    rets.append(m.totalReturn)
                    if m.totalReturn > h.totalReturn { beats += 1 }
                }
                let sorted = rets.sorted()
                let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2]
                    : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                rob = Robustness(windows: others.count, medianReturn: median,
                                 positiveShare: Double(rets.filter { $0 > 0 }.count) / Double(rets.count),
                                 beatsHoldShare: Double(beats) / Double(others.count))
            }
            out.append(Candidate(id: i, strategy: s, train: trainM, trainBuyAndHold: hold,
                                 validationDays: valRange, validation: v, validationBuyAndHold: vHold,
                                 robustness: rob,
                                 verdict: Self.verdict(validation: v, validationHold: vHold, robustness: rob)))
            progress?(0.8 + 0.2 * Double(i + 1) / Double(max(picked.count, 1)))
        }
        progress?(1)
        return out
    }

    // MARK: Helpers

    static func verdict(validation: Metrics?, validationHold: Metrics? = nil, robustness: Robustness?) -> Verdict {
        let profitableAfter = validation.map { $0.totalReturn > 0 }
        let positiveShare = robustness?.positiveShare
        let beatsHold = robustness?.beatsHoldShare

        // Clear failure: lost money on the next period and in most other periods.
        if profitableAfter == false, (positiveShare ?? 0) < 0.4 { return .fellApart }
        if profitableAfter == nil, let p = positiveShare, p < 0.4 { return .fellApart }

        let steadyProfit = (profitableAfter ?? true) && (positiveShare ?? 0) >= 0.6
        if steadyProfit {
            if let b = beatsHold, b >= 0.5 { return .holdsUp }
            if let v = validation, let h = validationHold, v.maxDrawdown < h.maxDrawdown { return .steadier }
            if beatsHold == nil, let v = validation, let h = validationHold, v.totalReturn > h.totalReturn {
                return .holdsUp
            }
        }
        return .mixed
    }

    /// A same-length stretch right after training; if there isn't room, right before.
    static func validationRange(after train: Range<Int>, total: Int) -> Range<Int>? {
        let len = min(train.count, 365)
        if train.upperBound + len <= total { return train.upperBound..<(train.upperBound + len) }
        if train.lowerBound - len >= 0 { return (train.lowerBound - len)..<train.lowerBound }
        return nil
    }

    /// Evenly spaced same-length windows that don't overlap the training period.
    static func otherWindows(length: Int, avoiding train: Range<Int>, total: Int, count: Int) -> [Range<Int>] {
        guard length >= 30, total > length else { return [] }
        var starts: [Int] = []
        var s = 0
        while s + length <= total {
            let w = s..<(s + length)
            if w.upperBound <= train.lowerBound || w.lowerBound >= train.upperBound { starts.append(s) }
            s += max(length / 2, 15)
        }
        guard !starts.isEmpty else { return [] }
        let n = min(count, starts.count)
        return (0..<n).map { k in
            let st = starts[k * (starts.count - 1) / max(n - 1, 1)]
            return st..<(st + length)
        }
    }

    static func defaultSeed(_ r: Range<Int>) -> UInt64 {
        UInt64(r.lowerBound) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(r.upperBound) &* 0xBF58_476D_1CE4_E5B9
    }
}

/// Small deterministic RNG so a search is reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds plausible random rule sets from a handful of well-known ideas.
enum RuleGenerator {
    static func family(of s: Strategy) -> String {
        s.entry.map { c -> String in
            switch c {
            case .rsiBelow, .rsiAbove: return "rsi"
            case .priceAboveMA, .priceBelowMA: return "price-ma"
            case .maAbove, .maBelow: return "ma-cross"
            case .dropFromHigh: return "dip"
            case .breakout: return "breakout"
            case .belowLowerBand, .aboveUpperBand: return "bands"
            case .macdAboveSignal, .macdBelowSignal: return "macd"
            }
        }.sorted().joined(separator: "+")
    }

    static func random<G: RandomNumberGenerator>(using rng: inout G) -> Strategy {
        func pick<T>(_ a: [T]) -> T { a[Int.random(in: 0..<a.count, using: &rng)] }
        func maybe<T>(_ a: [T], chance: Double = 0.55) -> T? {
            Double.random(in: 0..<1, using: &rng) < chance ? pick(a) : nil
        }

        var s = Strategy()
        switch Int.random(in: 0..<6, using: &rng) {
        case 0: // buy the dip
            let d = pick([10, 20, 30, 60]), p = pick([8.0, 10, 15, 20, 25, 30])
            s.entry = [.dropFromHigh(days: d, percent: p)]
            if Bool.random(using: &rng) { s.entry.append(.rsiBelow(period: 14, level: pick([30, 35, 40, 45]))) }
            s.exit = Bool.random(using: &rng) ? [.rsiAbove(period: 14, level: pick([55, 60, 65, 70]))] : []
            s.name = "Dip buyer"
        case 1: // oversold bounce
            let p = pick([7, 14, 21]), l = pick([20.0, 25, 30, 35])
            s.entry = [.rsiBelow(period: p, level: l)]
            s.exit = [.rsiAbove(period: p, level: pick([50.0, 55, 60, 70]))]
            s.name = "RSI bounce"
        case 2: // moving-average trend
            let f = pick([5, 10, 20, 30]), sl = pick([40, 50, 100, 150, 200])
            s.entry = [.maAbove(fast: f, slow: max(sl, f + 10))]
            s.exit = Bool.random(using: &rng) ? [.maBelow(fast: f, slow: max(sl, f + 10))] : []
            s.name = "Trend follower"
        case 3: // breakout
            let d = pick([20, 30, 55, 100])
            s.entry = [.breakout(days: d)]
            s.exit = Bool.random(using: &rng) ? [.priceBelowMA(period: pick([10, 20, 50]))] : []
            s.name = "Breakout rider"
        case 4: // band bounce
            let p = pick([20, 30]), k = pick([1.5, 2.0, 2.5])
            s.entry = [.belowLowerBand(period: p, deviations: k)]
            s.exit = [pick([.priceAboveMA(period: p), .aboveUpperBand(period: p, deviations: k)])]
            s.name = "Band bouncer"
        default: // momentum
            s.entry = [.macdAboveSignal, .priceAboveMA(period: pick([50, 100, 200]))]
            s.exit = [.macdBelowSignal]
            s.name = "Momentum"
        }
        s.stopLossPercent = maybe([5.0, 8, 10, 15, 20])
        s.takeProfitPercent = maybe([10.0, 15, 25, 40, 60, 100], chance: 0.45)
        s.trailingStopPercent = maybe([8.0, 12, 15, 20, 30], chance: 0.4)
        s.positionPercent = pick([50.0, 75, 100])
        s.limitEntryDiscountPercent = maybe([2.0, 4, 6], chance: 0.25)
        // A rule set with no way out other than the end of the test is just "buy and forget".
        if s.exit.isEmpty, s.stopLossPercent == nil, s.takeProfitPercent == nil, s.trailingStopPercent == nil {
            s.trailingStopPercent = pick([12.0, 20])
        }
        return s
    }
}
