import Foundation

public enum ExitReason: String, Codable, Sendable {
    case stopLoss, trailingStop, takeProfit, signal, maxHold, endOfTest

    public var title: String {
        switch self {
        case .stopLoss: return "Stop loss"
        case .trailingStop: return "Trailing stop"
        case .takeProfit: return "Take profit"
        case .signal: return "Exit signal"
        case .maxHold: return "Max hold"
        case .endOfTest: return "End of test"
        }
    }
}

public struct Trade: Identifiable, Equatable, Sendable {
    public let id: Int
    public let entryDay: Int          // index into the price history
    public let exitDay: Int
    public let entryPrice: Double
    public let exitPrice: Double
    /// Net of fees and slippage.
    public let returnPercent: Double
    public let reason: ExitReason
}

public struct Metrics: Equatable, Codable, Sendable {
    public let totalReturn: Double        // 0.25 = +25%
    public let annualizedReturn: Double
    public let maxDrawdown: Double        // 0.3 = fell 30% from a peak
    public let winRate: Double            // 0...1 (0 if no trades)
    public let trades: Int
    public let exposure: Double           // share of days holding bitcoin
    public let sharpe: Double             // daily returns, annualized
}

public struct BacktestSettings: Sendable {
    public var startCash = 100_000.0
    public var fee = GameSession.fee      // same 0.26% as the game
    /// Extra cost on market fills and stop fills (0.001 = 0.1%).
    public var slippage = 0.001
    public init() {}
}

/// One scheduled purchase made by a DCA robot.
public struct Purchase: Equatable, Sendable {
    public let day: Int          // index into the price history
    public let price: Double
    public let amount: Double    // dollars spent
}

public struct BacktestResult: Sendable {
    public let days: Range<Int>
    public let equity: [Double]           // one value per day, closing equity
    public let trades: [Trade]
    public let metrics: Metrics
    /// Filled only by DCA robots.
    public var purchases: [Purchase] = []
}

/// Runs a `Strategy` over real daily candles.
///
/// Rules of the road (no lookahead):
/// - Signals are read at the close of a candle; trades happen at the *next* open.
/// - Stops and take-profits are tested against each candle's real high and low;
///   a gap through a level fills at the open.
/// - If a stop and a take-profit are both touched in one candle, the stop wins.
public final class Backtester {
    public let history: PriceHistory
    private let closes: [Double]

    private var smaCache: [Int: [Double?]] = [:]
    private var rsiCache: [Int: [Double?]] = [:]
    private var bandCache: [String: Indicators.Bands] = [:]
    private var highCache: [Int: [Double]] = [:]        // highest close of last N days, including today
    private var prevHighCache: [Int: [Double]] = [:]    // highest close of the N days before today
    private lazy var macdLine: Indicators.MACD = Indicators.macd(closes)

    public init(history: PriceHistory = .bundled) {
        self.history = history
        self.closes = history.bars.map(\.close)
    }

    public var dayCount: Int { history.count }

    /// History index for a calendar date (UTC), clamped to the data.
    public func dayIndex(for date: Date) -> Int {
        let days = Int(((date.timeIntervalSince1970 - history.startDate.timeIntervalSince1970) / 86_400).rounded(.down))
        return min(max(days, 0), history.count - 1)
    }

    public func date(forDay i: Int) -> Date {
        history.startDate.addingTimeInterval(Double(i) * 86_400)
    }

    // MARK: Signals

    private func sma(_ p: Int) -> [Double?] {
        if let c = smaCache[p] { return c }
        let v = Indicators.sma(closes, period: p); smaCache[p] = v; return v
    }
    private func rsi(_ p: Int) -> [Double?] {
        if let c = rsiCache[p] { return c }
        let v = Indicators.rsi(closes, period: p); rsiCache[p] = v; return v
    }
    private func bands(_ p: Int, _ k: Double) -> Indicators.Bands {
        let key = "\(p)|\(k)"
        if let c = bandCache[key] { return c }
        let v = Indicators.bollinger(closes, period: p, deviations: k); bandCache[key] = v; return v
    }
    private func highest(_ n: Int) -> [Double] {
        if let c = highCache[n] { return c }
        var out = [Double](repeating: 0, count: closes.count)
        for i in closes.indices { out[i] = closes[max(0, i - n + 1)...i].max()! }
        highCache[n] = out; return out
    }
    private func previousHighest(_ n: Int) -> [Double] {
        if let c = prevHighCache[n] { return c }
        var out = [Double](repeating: .infinity, count: closes.count)
        for i in closes.indices where i >= 1 { out[i] = closes[max(0, i - n)..<i].max()! }
        prevHighCache[n] = out; return out
    }

    func isTrue(_ c: Condition, at i: Int) -> Bool {
        guard i >= 0, i < closes.count else { return false }
        let close = closes[i]
        switch c {
        case let .rsiBelow(p, l): return rsi(p)[i].map { $0 < l } ?? false
        case let .rsiAbove(p, l): return rsi(p)[i].map { $0 > l } ?? false
        case let .priceAboveMA(p): return sma(p)[i].map { close > $0 } ?? false
        case let .priceBelowMA(p): return sma(p)[i].map { close < $0 } ?? false
        case let .maAbove(f, s):
            guard let a = sma(f)[i], let b = sma(s)[i] else { return false }
            return a > b
        case let .maBelow(f, s):
            guard let a = sma(f)[i], let b = sma(s)[i] else { return false }
            return a < b
        case let .dropFromHigh(d, p):
            return i >= d - 1 && close <= highest(d)[i] * (1 - p / 100)
        case let .breakout(d):
            return i >= d && close > previousHighest(d)[i]
        case let .belowLowerBand(p, k): return bands(p, k).lower[i].map { close < $0 } ?? false
        case let .aboveUpperBand(p, k): return bands(p, k).upper[i].map { close > $0 } ?? false
        case .macdAboveSignal:
            guard let m = macdLine.macd[i], let s = macdLine.signal[i] else { return false }
            return m > s
        case .macdBelowSignal:
            guard let m = macdLine.macd[i], let s = macdLine.signal[i] else { return false }
            return m < s
        case let .priceAbove(p): return close >= p
        case let .priceBelow(p): return close <= p
        case let .upPercent(d, p): return i >= d && close >= closes[i - d] * (1 + p / 100)
        case let .downPercent(d, p): return i >= d && close <= closes[i - d] * (1 - p / 100)
        case let .percentAboveMA(n, p): return sma(n)[i].map { close >= $0 * (1 + p / 100) } ?? false
        case let .percentBelowMA(n, p): return sma(n)[i].map { close <= $0 * (1 - p / 100) } ?? false
        case let .riseFromLow(d, p):
            guard i >= d - 1 else { return false }
            let low = closes[max(0, i - d + 1)...i].min()!
            return close >= low * (1 + p / 100)
        }
    }

    private func entryActive(_ s: Strategy, at i: Int) -> Bool {
        !s.entry.isEmpty && s.entry.allSatisfy { isTrue($0, at: i) }
    }

    // MARK: Run

    public func run(_ s: Strategy, days: Range<Int>, settings: BacktestSettings = BacktestSettings()) -> BacktestResult {
        if let plan = s.dca { return runDCA(plan, days: days, settings: settings) }
        let range = clamp(days)
        let bars = history.bars
        var cash = settings.startCash
        var shares = 0.0
        var cost = 0.0, entryPrice = 0.0, highSince = 0.0, entryDay = 0, held = 0
        var pendingBuy = false
        var pendingLimit: (price: Double, expires: Int)?
        var pendingSell: ExitReason?
        var trades: [Trade] = []
        var equity: [Double] = []
        var daysIn = 0

        func buy(spend: Double, price: Double, day: Int) {
            guard spend > 1, price > 0 else { return }
            shares = spend * (1 - settings.fee) / price
            cash -= spend
            cost = spend; entryPrice = price; highSince = price; entryDay = day; held = 0
        }
        func sell(price: Double, day: Int, reason: ExitReason) {
            guard shares > 0 else { return }
            let proceeds = shares * price * (1 - settings.fee)
            cash += proceeds
            trades.append(Trade(id: trades.count, entryDay: entryDay, exitDay: day,
                                entryPrice: entryPrice, exitPrice: price,
                                returnPercent: (proceeds / cost - 1) * 100, reason: reason))
            shares = 0; cost = 0
        }

        for i in range {
            let b = bars[i]
            var boughtByLimitToday = false

            // 1. Orders decided at yesterday's close fill at today's open.
            if let r = pendingSell, shares > 0 {
                sell(price: b.open * (1 - settings.slippage), day: i, reason: r)
            }
            pendingSell = nil
            if pendingBuy, shares == 0 {
                buy(spend: cash * s.positionPercent / 100, price: b.open * (1 + settings.slippage), day: i)
            }
            pendingBuy = false

            // 2. A resting limit buy fills if today trades down to it.
            if shares == 0, let pl = pendingLimit {
                if i > pl.expires {
                    pendingLimit = nil
                } else if b.low <= pl.price {
                    buy(spend: cash * s.positionPercent / 100, price: min(b.open, pl.price), day: i)
                    pendingLimit = nil
                    boughtByLimitToday = true
                }
            }

            // 3. Protective orders, tested against today's real range.
            if shares > 0, !boughtByLimitToday {
                var stop: Double?
                var stopIsTrailing = false
                if let sl = s.stopLossPercent { stop = entryPrice * (1 - sl / 100) }
                if let tr = s.trailingStopPercent {
                    let t = highSince * (1 - tr / 100)
                    if stop == nil || t > stop! { stop = t; stopIsTrailing = true }
                }
                let target = s.takeProfitPercent.map { entryPrice * (1 + $0 / 100) }
                let stopHit = stop.map { b.low <= $0 } ?? false
                let targetHit = target.map { b.high >= $0 } ?? false
                if stopHit, let st = stop {
                    let fill = b.open <= st ? b.open : st
                    sell(price: fill * (1 - settings.slippage), day: i,
                         reason: stopIsTrailing ? .trailingStop : .stopLoss)
                } else if targetHit, let tg = target {
                    sell(price: b.open >= tg ? b.open : tg, day: i, reason: .takeProfit)
                }
            }

            // 4. End of day bookkeeping, then read signals at the close.
            if shares > 0 {
                daysIn += 1
                held += 1
                highSince = max(highSince, b.high)
                if let mh = s.maxHoldDays, held >= mh { pendingSell = .maxHold }
                if pendingSell == nil, s.exit.contains(where: { isTrue($0, at: i) }) { pendingSell = .signal }
            } else if pendingBuy == false, pendingLimit == nil {
                let now = entryActive(s, at: i)
                let before = i > 0 ? entryActive(s, at: i - 1) : false
                if now && !before {
                    if let d = s.limitEntryDiscountPercent {
                        pendingLimit = (b.close * (1 - d / 100), i + Strategy.limitValidDays)
                    } else {
                        pendingBuy = true
                    }
                }
            }

            equity.append(cash + shares * b.close)
        }

        if shares > 0, let last = range.last {
            // Close the final position at the last close so every trade is counted.
            sell(price: bars[last].close, day: last, reason: .endOfTest)
            equity[equity.count - 1] = cash
        }
        return BacktestResult(days: range, equity: equity, trades: trades,
                              metrics: Self.metrics(equity: equity, trades: trades,
                                                    daysIn: daysIn, start: settings.startCash))
    }

    /// Buy equal dollar amounts on a schedule; the starting cash is spread over all purchase days.
    private func runDCA(_ plan: DCAPlan, days: Range<Int>, settings: BacktestSettings) -> BacktestResult {
        let range = clamp(days)
        let bars = history.bars
        guard !range.isEmpty else {
            return BacktestResult(days: range, equity: [], trades: [],
                                  metrics: Self.metrics(equity: [], trades: [], daysIn: 0, start: settings.startCash))
        }
        let interval = max(1, plan.intervalDays)
        let buyCount = (range.count + interval - 1) / interval
        let amount = settings.startCash / Double(buyCount)
        var cash = settings.startCash, shares = 0.0, spent = 0.0, grossQty = 0.0
        var purchases: [Purchase] = []
        var equity: [Double] = []
        var daysIn = 0
        for (k, i) in range.enumerated() {
            if k % interval == 0 {
                let spend = min(amount, cash)
                let price = bars[i].open * (1 + settings.slippage)
                if spend > 1, price > 0 {
                    shares += spend * (1 - settings.fee) / price
                    grossQty += spend / price
                    spent += spend; cash -= spend
                    purchases.append(Purchase(day: i, price: price, amount: spend))
                }
            }
            if shares > 0 { daysIn += 1 }
            equity.append(cash + shares * bars[i].close)
        }
        guard let last = range.last else { fatalError() }
        var trades: [Trade] = []
        if shares > 0, let first = purchases.first {
            let proceeds = shares * bars[last].close * (1 - settings.fee)
            cash += proceeds
            equity[equity.count - 1] = cash
            trades.append(Trade(id: 0, entryDay: first.day, exitDay: last,
                                entryPrice: spent / max(grossQty, 1e-12), exitPrice: bars[last].close,
                                returnPercent: (proceeds / spent - 1) * 100, reason: .endOfTest))
        }
        var r = BacktestResult(days: range, equity: equity, trades: trades,
                               metrics: Self.metrics(equity: equity, trades: trades, daysIn: daysIn,
                                                     start: settings.startCash))
        r.purchases = purchases
        return r
    }

    /// Put everything in at the first open and hold to the last close, with the same costs.
    public func buyAndHold(days: Range<Int>, settings: BacktestSettings = BacktestSettings()) -> BacktestResult {
        let range = clamp(days)
        let bars = history.bars
        guard let first = range.first, let last = range.last else {
            return BacktestResult(days: range, equity: [], trades: [],
                                  metrics: Self.metrics(equity: [], trades: [], daysIn: 0, start: settings.startCash))
        }
        let price = bars[first].open * (1 + settings.slippage)
        let shares = settings.startCash * (1 - settings.fee) / price
        var equity = range.map { shares * bars[$0].close }
        let exit = shares * bars[last].close * (1 - settings.fee)
        equity[equity.count - 1] = exit
        let trade = Trade(id: 0, entryDay: first, exitDay: last, entryPrice: price, exitPrice: bars[last].close,
                          returnPercent: (exit / settings.startCash - 1) * 100, reason: .endOfTest)
        return BacktestResult(days: range, equity: equity, trades: [trade],
                              metrics: Self.metrics(equity: equity, trades: [trade],
                                                    daysIn: range.count, start: settings.startCash))
    }

    private func clamp(_ r: Range<Int>) -> Range<Int> {
        let lo = max(0, r.lowerBound), hi = min(history.count, r.upperBound)
        return lo < hi ? lo..<hi : lo..<lo
    }

    static func metrics(equity: [Double], trades: [Trade], daysIn: Int, start: Double) -> Metrics {
        guard let final = equity.last, !equity.isEmpty else {
            return Metrics(totalReturn: 0, annualizedReturn: 0, maxDrawdown: 0, winRate: 0, trades: 0, exposure: 0, sharpe: 0)
        }
        let total = final / start - 1
        let years = max(Double(equity.count) / 365, 1.0 / 365)
        let annual = final > 0 ? pow(final / start, 1 / years) - 1 : -1
        var peak = start, dd = 0.0
        for e in equity { peak = max(peak, e); dd = max(dd, (peak - e) / peak) }
        var rets: [Double] = []
        var prev = start
        for e in equity { rets.append(prev > 0 ? e / prev - 1 : 0); prev = e }
        let mean = rets.reduce(0, +) / Double(rets.count)
        let variance = rets.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(rets.count - 1, 1))
        let sd = variance.squareRoot()
        let sharpe = sd > 1e-12 ? mean / sd * 365.0.squareRoot() : 0
        let wins = trades.filter { $0.returnPercent > 0 }.count
        return Metrics(totalReturn: total, annualizedReturn: annual, maxDrawdown: dd,
                       winRate: trades.isEmpty ? 0 : Double(wins) / Double(trades.count),
                       trades: trades.count, exposure: Double(daysIn) / Double(equity.count), sharpe: sharpe)
    }
}

// MARK: - Replay helpers

public extension BacktestResult {
    /// The trade the robot was holding at the *close* of `day`, if any.
    /// (It buys at that trade's `entryDay` open and is out again by the close of its `exitDay`.)
    func holding(atCloseOf day: Int) -> Trade? {
        trades.first { $0.entryDay <= day && day < $0.exitDay }
    }

    /// Trades that had already been sold by the close of `day`, oldest first.
    func closedTrades(through day: Int) -> [Trade] {
        trades.filter { $0.exitDay <= day }
    }

    /// The most recent buy or sell on or before `day`, for "what just happened" captions.
    func latestEvent(through day: Int) -> (trade: Trade, isExit: Bool)? {
        var best: (Trade, Bool, Int)?
        for t in trades {
            if t.entryDay <= day, best == nil || t.entryDay >= best!.2 { best = (t, false, t.entryDay) }
            if t.exitDay <= day, best == nil || t.exitDay >= best!.2 { best = (t, true, t.exitDay) }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Equity at the close of absolute history day `day` (nil outside the tested range).
    func equity(atDay day: Int) -> Double? {
        guard days.contains(day) else { return nil }
        return equity[day - days.lowerBound]
    }
}
