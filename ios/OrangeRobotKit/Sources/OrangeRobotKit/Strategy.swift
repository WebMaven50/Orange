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
        }
    }
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

    public static let limitValidDays = 3

    public init(name: String = "My rules",
                entry: [Condition] = [],
                exit: [Condition] = [],
                stopLossPercent: Double? = nil,
                takeProfitPercent: Double? = nil,
                trailingStopPercent: Double? = nil,
                maxHoldDays: Int? = nil,
                positionPercent: Double = 100,
                limitEntryDiscountPercent: Double? = nil) {
        self.name = name
        self.entry = entry
        self.exit = exit
        self.stopLossPercent = stopLossPercent
        self.takeProfitPercent = takeProfitPercent
        self.trailingStopPercent = trailingStopPercent
        self.maxHoldDays = maxHoldDays
        self.positionPercent = min(max(positionPercent, 1), 100)
        self.limitEntryDiscountPercent = limitEntryDiscountPercent
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
        Strategy(name: "Breakout rider",
                 entry: [.breakout(days: 30)],
                 exit: [.priceBelowMA(period: 20)],
                 trailingStopPercent: 15, positionPercent: 100),
    ]
}
