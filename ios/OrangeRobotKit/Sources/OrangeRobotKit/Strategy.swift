import Foundation

/// One yes/no test the robot can make at the close of a daily candle.
/// Every condition is a *state* ("RSI is below 30"); entries fire when all
/// entry conditions become true together (a rising edge), so the robot does
/// not re-buy over and over while a signal stays on.
public enum Condition: Codable, Equatable, Hashable, Sendable {
    case rsiBelow(period: Int, level: Double)
    case rsiAbove(period: Int, level: Double)
    case priceAboveMA(period: Int)
    case priceBelowMA(period: Int)
    /// Fast average above slow average.
    case maAbove(fast: Int, slow: Int)
    /// Fast average below slow average.
    case maBelow(fast: Int, slow: Int)
    /// Close is at least `percent` below the highest close of the last `days`.
    case dropFromHigh(days: Int, percent: Double)
    /// Close is above the highest close of the previous `days`.
    case breakout(days: Int)
    case belowLowerBand(period: Int, deviations: Double)
    case aboveUpperBand(period: Int, deviations: Double)
    case macdAboveSignal
    case macdBelowSignal
    /// Close is at or above an absolute dollar level.
    case priceAbove(price: Double)
    /// Close is at or below an absolute dollar level.
    case priceBelow(price: Double)
    /// Close is up at least `percent` over the last `days` days.
    case upPercent(days: Int, percent: Double)
    /// Close is down at least `percent` over the last `days` days.
    case downPercent(days: Int, percent: Double)
    /// Close is at least `percent` above its `period`-day average.
    case percentAboveMA(period: Int, percent: Double)
    /// Close is at least `percent` below its `period`-day average.
    case percentBelowMA(period: Int, percent: Double)
    /// Close is at least `percent` above the lowest close of the last `days`.
    case riseFromLow(days: Int, percent: Double)

    /// Plain-English description for screens.
    public var summary: String {
        func g(_ d: Double) -> String { String(format: "%g", d) }
        switch self {
        case let .rsiBelow(p, l): return "RSI(\(p)) is below \(g(l))"
        case let .rsiAbove(p, l): return "RSI(\(p)) is above \(g(l))"
        case let .priceAboveMA(p): return "Price is above its \(p)-day average"
        case let .priceBelowMA(p): return "Price is below its \(p)-day average"
        case let .maAbove(f, s): return "\(f)-day average is above the \(s)-day average"
        case let .maBelow(f, s): return "\(f)-day average is below the \(s)-day average"
        case let .dropFromHigh(d, p): return "Price is \(g(p))% below its \(d)-day high"
        case let .breakout(d): return "Price breaks above its \(d)-day high"
        case let .belowLowerBand(p, k): return "Price is below the lower Bollinger band (\(p), \(g(k))σ)"
        case let .aboveUpperBand(p, k): return "Price is above the upper Bollinger band (\(p), \(g(k))σ)"
        case .macdAboveSignal: return "MACD is above its signal line"
        case .macdBelowSignal: return "MACD is below its signal line"
        case let .priceAbove(p): return "Price is at or above $\(Int(p.rounded()).formatted())"
        case let .priceBelow(p): return "Price is at or below $\(Int(p.rounded()).formatted())"
        case let .upPercent(d, p): return "Price is up \(g(p))% or more over \(d) days"
        case let .downPercent(d, p): return "Price is down \(g(p))% or more over \(d) days"
        case let .percentAboveMA(n, p): return "Price is \(g(p))% or more above its \(n)-day average"
        case let .percentBelowMA(n, p): return "Price is \(g(p))% or more below its \(n)-day average"
        case let .riseFromLow(d, p): return "Price is \(g(p))% or more above its \(d)-day low"
        }
    }
}

/// Dollar-cost averaging: buy on a fixed schedule, whatever the price.
///
/// How much each purchase is worth is always explicit:
/// - `dollarsPerBuy` set: that many dollars every time,
/// - else `percentOfStart` set: that share of the starting cash every time,
/// - else the starting cash is spread evenly over every purchase day.
public struct DCAPlan: Codable, Equatable, Hashable, Sendable {
    /// Days between purchases (1 = daily, 7 = weekly, 14, 30 = roughly monthly).
    public var intervalDays: Int
    public var dollarsPerBuy: Double?
    public var percentOfStart: Double?
    /// When set, each purchase also adds this share (1...100) of the profit made so far,
    /// paid from cash that is still waiting. Zero or nil means off.
    public var reinvestPercent: Double?

    public init(intervalDays: Int = 7, dollarsPerBuy: Double? = nil, percentOfStart: Double? = nil,
                reinvestPercent: Double? = nil) {
        self.intervalDays = max(1, intervalDays)
        self.dollarsPerBuy = dollarsPerBuy.map { max($0, 1) }
        self.percentOfStart = percentOfStart.map { min(max($0, 0.1), 100) }
        self.reinvestPercent = reinvestPercent.flatMap { $0 > 0 ? min($0, 100) : nil }
    }

    public var reinvests: Bool { (reinvestPercent ?? 0) > 0 }

    public var label: String {
        switch intervalDays {
        case 1: return "every day"
        case 7: return "every week"
        case 14: return "every two weeks"
        case 30: return "every month"
        default: return "every \(intervalDays) days"
        }
    }

    public enum Mode: String, Sendable { case evenSpread, dollars, percent }
    public var mode: Mode {
        if dollarsPerBuy != nil { return .dollars }
        if percentOfStart != nil { return .percent }
        return .evenSpread
    }

    /// Number of purchase days in a test of `days` days (first day included).
    public func buyCount(days: Int) -> Int { max(1, (max(days, 1) + intervalDays - 1) / intervalDays) }

    /// Dollars spent on each purchase.
    public func amountPerBuy(startCash: Double, days: Int) -> Double {
        if let d = dollarsPerBuy { return d }
        if let p = percentOfStart { return startCash * p / 100 }
        return startCash / Double(buyCount(days: days))
    }

    /// Money that will actually be invested over the test (never more than the cash available).
    public func totalInvested(startCash: Double, days: Int) -> Double {
        min(startCash, amountPerBuy(startCash: startCash, days: days) * Double(buyCount(days: days)))
    }

    /// Plain-English description, e.g. "Buys $1,887 every week · 53 purchases · $100,000 in total".
    public func summary(startCash: Double, days: Int) -> String {
        let amt = amountPerBuy(startCash: startCash, days: days)
        let n = buyCount(days: days)
        let total = totalInvested(startCash: startCash, days: days)
        var out = "Buys \(Self.money(amt)) \(label) · \(n) purchase\(n == 1 ? "" : "s") · \(Self.money(total)) in total"
        if startCash - total >= 1 { out += " · \(Self.money(startCash - total)) stays in cash" }
        if amt * Double(n) > startCash + 0.5 { out += " · stops when cash runs out" }
        if let r = reinvestPercent, r > 0 {
            out += " · plus \(String(format: "%g", r))% of the profit so far each time"
        }
        return out
    }

    /// Short label without needing the test length.
    public var shortAmountText: String {
        let base: String
        if let d = dollarsPerBuy { base = Self.money(d) }
        else if let p = percentOfStart { base = String(format: "%g%% of cash", p) }
        else { base = "an equal share of cash" }
        if let r = reinvestPercent, r > 0 { return base + String(format: " + %g%% of profit", r) }
        return base
    }

    public static func money(_ x: Double) -> String { "$" + Int(x.rounded()).formatted() }
}

/// A complete set of rules for the robot. Long-only: it either holds Bitcoin or cash.
public struct Strategy: Codable, Equatable, Hashable, Sendable {
    public var name: String
    /// All of these must become true together to buy.
    public var entry: [Condition]
    /// Any one of these being true sells (optional).
    public var exit: [Condition]
    /// Sell if the price falls this many percent below the buy price.
    public var stopLossPercent: Double?
    /// Sell (limit order) when the price rises this many percent above the buy price.
    public var takeProfitPercent: Double?
    /// Sell if the price falls this many percent from its highest point since buying.
    public var trailingStopPercent: Double?
    /// Sell after holding this many days.
    public var maxHoldDays: Int?
    /// Share of cash to invest on each buy (1...100).
    public var positionPercent: Double
    /// If set, buy with a limit order this many percent below the signal price
    /// (good for `Strategy.limitValidDays`) instead of buying at the next open.
    public var limitEntryDiscountPercent: Double?
    /// When set, the robot ignores signals and simply buys on a schedule.
    public var dca: DCAPlan?

    public static let limitValidDays = 3

    public init(name: String = "My rules",
                entry: [Condition] = [],
                exit: [Condition] = [],
                stopLossPercent: Double? = nil,
                takeProfitPercent: Double? = nil,
                trailingStopPercent: Double? = nil,
                maxHoldDays: Int? = nil,
                positionPercent: Double = 100,
                limitEntryDiscountPercent: Double? = nil,
                dca: DCAPlan? = nil) {
        self.name = name
        self.entry = entry
        self.exit = exit
        self.stopLossPercent = stopLossPercent
        self.takeProfitPercent = takeProfitPercent
        self.trailingStopPercent = trailingStopPercent
        self.maxHoldDays = maxHoldDays
        self.positionPercent = min(max(positionPercent, 1), 100)
        self.limitEntryDiscountPercent = limitEntryDiscountPercent
        self.dca = dca
    }

    /// Ready-made starting points for the rule builder.
    public static let templates: [Strategy] = [
        Strategy(name: "Buy the dip",
                 entry: [.dropFromHigh(days: 30, percent: 15), .rsiBelow(period: 14, level: 35)],
                 exit: [.rsiAbove(period: 14, level: 60)],
                 stopLossPercent: 12, takeProfitPercent: 30, positionPercent: 75),
        Strategy(name: "Follow the trend",
                 entry: [.maAbove(fast: 20, slow: 50)],
                 exit: [.maBelow(fast: 20, slow: 50)],
                 trailingStopPercent: 20, positionPercent: 100),
        Strategy(name: "RSI bounce",
                 entry: [.rsiBelow(period: 14, level: 30)],
                 exit: [.rsiAbove(period: 14, level: 55)],
                 stopLossPercent: 10, takeProfitPercent: 20, positionPercent: 50),
        Strategy(name: "Weekly DCA", dca: DCAPlan(intervalDays: 7)),
        Strategy(name: "Monthly DCA", dca: DCAPlan(intervalDays: 30)),
        Strategy(name: "Breakout rider",
                 entry: [.breakout(days: 30)],
                 exit: [.priceBelowMA(period: 20)],
                 trailingStopPercent: 15, positionPercent: 100),
    ]
}
