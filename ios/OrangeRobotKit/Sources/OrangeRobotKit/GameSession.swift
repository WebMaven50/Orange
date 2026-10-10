import Foundation

public enum PlaybackSpeed: Sendable {
    case normal, fast
    /// Game minutes that pass per real second.
    var minutesPerSecond: Double { self == .fast ? 60 : 4 }
}

/// All state and rules of one Orange Robot Trader run.
///
/// Pure logic, no UI: drive it with `advance(seconds:)` from a display link or
/// timer and read the properties to render.
public struct GameSession {
    // Rules (identical to the web game)
    public static let fee = 0.0026
    public static let startCash = 100_000.0
    public static let winTarget = 1_000_000.0
    public static let sleepGameMinutes = 480.0
    public static let sleepRealSeconds = 3.0

    public let engine: PriceEngine
    public private(set) var absMinute: Double
    public private(set) var cash: Double
    /// Negative while short.
    public private(set) var btc: Double = 0
    public private(set) var lastPrice: Double
    public private(set) var bestEquity: Double
    public private(set) var trades = 0
    public private(set) var pendingOrders: [PendingOrder] = []
    public private(set) var outcome: GameOutcome?
    public private(set) var isPaused = false
    public var speed: PlaybackSpeed = .normal
    /// True when the start date was drawn at random. A run that starts at a
    /// date the player chose is a *practice* run: nothing stops them picking a
    /// known rally, so it does not count for the leaderboard or virtual sats.
    public let isRandomStart: Bool

    private var nextOrderID = 1
    private var sleep: (startMinute: Double, elapsed: Double)?

    public var isSleeping: Bool { sleep != nil }
    public var isRunning: Bool { outcome == nil }

    // MARK: Lifecycle

    public init(engine: PriceEngine, startMinute: Double, isRandomStart: Bool = true) {
        self.isRandomStart = isRandomStart
        self.engine = engine
        self.absMinute = startMinute
        self.cash = Self.startCash
        self.bestEquity = Self.startCash
        self.lastPrice = engine.price(atMinute: startMinute)
    }

    /// A fresh run in a random window of real history, starting mid-morning.
    public static func random<G: RandomNumberGenerator>(
        history: PriceHistory = .bundled, using rng: inout G
    ) -> GameSession {
        let startDay = Int.random(in: 0..<PriceEngine.maxStartDay(for: history), using: &rng)
        let minute = Double(480 + Int.random(in: 0..<120, using: &rng))
        return GameSession(engine: PriceEngine(history: history, startDay: startDay),
                           startMinute: minute)
    }

    public static func random(history: PriceHistory = .bundled) -> GameSession {
        var rng = SystemRandomNumberGenerator()
        return random(history: history, using: &rng)
    }

    /// A practice run at a player-chosen moment (UTC calendar date and time of day).
    /// The date is clamped to the playable history.
    public static func starting(at moment: Date, history: PriceHistory = .bundled) -> GameSession {
        let cal = utcCalendar
        let first = cal.startOfDay(for: history.startDate)
        let day = cal.dateComponents([.day], from: first, to: cal.startOfDay(for: moment)).day ?? 0
        let clamped = min(max(0, day), PriceEngine.maxStartDay(for: history))
        let hm = cal.dateComponents([.hour, .minute], from: moment)
        let minute = Double((hm.hour ?? 0) * 60 + (hm.minute ?? 0))
        return GameSession(engine: PriceEngine(history: history, startDay: clamped),
                           startMinute: minute, isRandomStart: false)
    }

    /// Earliest and latest moments a player may choose to start from.
    public static func startDateRange(history: PriceHistory = .bundled) -> ClosedRange<Date> {
        let cal = utcCalendar
        let first = cal.startOfDay(for: history.startDate)
        let lastDay = cal.date(byAdding: .day, value: PriceEngine.maxStartDay(for: history), to: first)!
        return first...cal.date(byAdding: .minute, value: 1439, to: lastDay)!
    }

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // MARK: Derived

    public var equity: Double { cash + btc * lastPrice }
    public var profitLoss: Double { equity - Self.startCash }
    public var goalProgress: Double { min(max(equity / Self.winTarget, 0), 1) }
    public var daysPlayed: Int { Int(floor(absMinute / 1440)) }
    public var currentDate: Date { engine.date(forDayOffset: daysPlayed) }
    public var minuteOfDay: Int { Int(((absMinute.truncatingRemainder(dividingBy: 1440)) + 1440)
                                        .truncatingRemainder(dividingBy: 1440)) }
    /// Change since today's real open, in percent.
    public var changeToday: Double {
        let open = engine.dayOpen(atMinute: absMinute)
        return open == 0 ? 0 : (lastPrice - open) / open * 100
    }

    /// 1 sat per dollar of profit above the starting stake.
    public var satsEarned: Int { max(0, Int((equity - Self.startCash).rounded())) }

    public func candles(timeframeMinutes: Int, count: Int) -> [Candle] {
        engine.candles(timeframeMinutes: timeframeMinutes, count: count, atMinute: absMinute)
    }

    // MARK: Time

    /// Move the clock forward by `seconds` of real time.
    public mutating func advance(seconds dt: Double) {
        guard isRunning, !isPaused else { return }
        let dt = min(dt, 0.05) // clamp like the web game so a stall can't skip the market
        if var s = sleep {
            s.elapsed += dt
            let t = min(max(s.elapsed / Self.sleepRealSeconds, 0), 1)
            absMinute = s.startMinute + Self.sleepGameMinutes * t
            sleep = t >= 1 ? nil : s
        } else {
            absMinute += speed.minutesPerSecond * dt
        }
        lastPrice = engine.price(atMinute: absMinute)
        // Orders keep working while you sleep (the web version skipped them).
        checkPendingOrders()
        bestEquity = max(bestEquity, equity)
        checkEndConditions()
    }

    /// Freeze the clock. Prices, sleep and resting orders all stop; the player
    /// can still look around and place orders at the frozen price.
    public mutating func pause() { if isRunning { isPaused = true } }
    public mutating func resume() { isPaused = false }

    /// Skip 8 game-hours. Prices keep moving and resting orders still fill.
    @discardableResult
    public mutating func startSleep() -> Bool {
        guard isRunning, !isSleeping, !isPaused else { return false }
        sleep = (absMinute, 0)
        return true
    }

    public mutating func cashOut() {
        guard isRunning, !isSleeping else { return }
        outcome = .cashout
    }

    private mutating func checkEndConditions() {
        guard outcome == nil else { return }
        if equity >= Self.winTarget { outcome = .win }
        else if equity <= 0 { outcome = .bust }
    }

    // MARK: Sizing

    /// Largest order (USD) allowed on `side`. Exact, not rounded: "100%" really
    /// means the whole balance or position. The UI can snap to $100 steps if it
    /// wants (the web game rounded here and left up to $99 of dust behind).
    public func maxAmount(for side: Side) -> Double {
        switch side {
        case .buy:
            return max(0, cash)
        case .sell:
            if btc > 0 { return btc * lastPrice }
            // Opening or adding to a short: notional capped at 1x equity.
            return max(0, equity)
        }
    }

    // MARK: Orders

    /// Place an order. `level` is the limit/stop price, or trail percent.
    @discardableResult
    public mutating func place(side: Side, type: OrderType, amountUSD: Double,
                               level: Double? = nil) throws -> PendingOrder? {
        guard isRunning else { throw OrderError.sessionOver }
        guard !isSleeping else { throw OrderError.sleeping }
        guard amountUSD >= 1 else { throw OrderError.amountTooSmall }

        if type == .market {
            let ok = side == .buy ? executeBuy(amountUSD, at: lastPrice)
                                  : executeSell(amountUSD, at: lastPrice)
            if !ok { throw OrderError.amountTooSmall }
            bestEquity = max(bestEquity, equity)
            checkEndConditions()
            return nil
        }

        guard let level, level.isFinite, level > 0 else { throw OrderError.invalidPrice }
        let maxNow = maxAmount(for: side)
        let fraction = maxNow > 0 ? min(max(amountUSD / maxNow, 0), 1) : 0
        let order = PendingOrder(id: nextOrderID, type: type, side: side,
                                 amountFraction: fraction, createdAtPrice: lastPrice,
                                 level: level, extreme: lastPrice)
        nextOrderID += 1
        pendingOrders.append(order)
        return order
    }

    public mutating func cancelOrder(id: Int) {
        pendingOrders.removeAll { $0.id == id }
    }

    /// Dollar size an order would fill at right now.
    public func liveAmount(for order: PendingOrder) -> Double {
        max(0, maxAmount(for: order.side) * order.amountFraction)
    }

    private mutating func checkPendingOrders() {
        guard !pendingOrders.isEmpty else { return }
        let price = lastPrice
        var remaining: [PendingOrder] = []
        for var o in pendingOrders {
            var filled = false
            switch o.type {
            case .market:
                break
            case .limit:
                if o.side == .buy, price <= o.level {
                    executeBuy(liveAmount(for: o), at: o.level); filled = true
                } else if o.side == .sell, price >= o.level {
                    executeSell(liveAmount(for: o), at: o.level); filled = true
                }
            case .stop:
                if o.side == .buy, price >= o.level {
                    executeBuy(liveAmount(for: o), at: price); filled = true
                } else if o.side == .sell, price <= o.level {
                    executeSell(liveAmount(for: o), at: price); filled = true
                }
            case .trailing:
                if o.side == .sell {
                    o.extreme = max(o.extreme, price)
                    if price <= o.extreme * (1 - o.level / 100) {
                        executeSell(liveAmount(for: o), at: price); filled = true
                    }
                } else {
                    o.extreme = min(o.extreme, price)
                    if price >= o.extreme * (1 + o.level / 100) {
                        executeBuy(liveAmount(for: o), at: price); filled = true
                    }
                }
            }
            if !filled { remaining.append(o) }
        }
        pendingOrders = remaining
    }

    // MARK: Execution

    @discardableResult
    private mutating func executeBuy(_ amountUSD: Double, at price: Double) -> Bool {
        let spend = min(amountUSD, max(cash, 0))
        guard spend >= 1, price > 0 else { return false }
        btc += spend * (1 - Self.fee) / price
        cash -= spend
        trades += 1
        return true
    }

    @discardableResult
    private mutating func executeSell(_ amountUSD: Double, at price: Double) -> Bool {
        guard amountUSD >= 1, price > 0 else { return false }
        let qty = amountUSD / price
        btc -= qty
        cash += qty * price * (1 - Self.fee)
        trades += 1
        return true
    }
}
