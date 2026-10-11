import Foundation
import CryptoKit

/// One closed (or in-progress) UTC day of live market data.
public struct DailyCandle: Codable, Equatable, Sendable {
    /// Days since 1970-01-01, UTC.
    public let day: Int
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double

    public init(day: Int, open: Double, high: Double, low: Double, close: Double) {
        self.day = day; self.open = open; self.high = high; self.low = low; self.close = close
    }
}

public enum LiveFeedError: Error, Equatable, Sendable {
    case malformed
    case noData
    case network
}

/// Parsers for the free public daily-candle endpoints.
public enum LiveFeed {
    static func dayNumber(_ unixSeconds: Double) -> Int { Int((unixSeconds / 86_400).rounded(.down)) }

    /// Kraken `OHLC?pair=XBTUSD&interval=1440`.
    /// Rows are `[time, open, high, low, close, vwap, volume, count]`.
    public static func parseKraken(_ data: Data) throws -> [DailyCandle] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let key = result.keys.first(where: { $0 != "last" }),
              let rows = result[key] as? [[Any]]
        else { throw LiveFeedError.malformed }
        var out: [DailyCandle] = []
        for r in rows where r.count >= 5 {
            guard let t = (r[0] as? Double) ?? (r[0] as? Int).map(Double.init),
                  let o = Self.number(r[1]), let h = Self.number(r[2]),
                  let l = Self.number(r[3]), let c = Self.number(r[4]) else { continue }
            out.append(DailyCandle(day: dayNumber(t), open: o, high: h, low: l, close: c))
        }
        guard !out.isEmpty else { throw LiveFeedError.noData }
        return out.sorted { $0.day < $1.day }
    }

    /// Coinbase Exchange `products/BTC-USD/candles?granularity=86400`.
    /// Rows are `[time, low, high, open, close, volume]`, newest first.
    public static func parseCoinbase(_ data: Data) throws -> [DailyCandle] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { throw LiveFeedError.malformed }
        var out: [DailyCandle] = []
        for r in rows where r.count >= 5 {
            guard let t = Self.number(r[0]), let l = Self.number(r[1]), let h = Self.number(r[2]),
                  let o = Self.number(r[3]), let c = Self.number(r[4]) else { continue }
            out.append(DailyCandle(day: dayNumber(t), open: o, high: h, low: l, close: c))
        }
        guard !out.isEmpty else { throw LiveFeedError.noData }
        return out.sorted { $0.day < $1.day }
    }

    private static func number(_ v: Any) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    /// A price history from live candles: only days up to `throughDay`, and only the
    /// unbroken run of days leading up to it (a gap would corrupt every indicator).
    public static func history(from candles: [DailyCandle], throughDay: Int) -> PriceHistory? {
        let sorted = candles.filter { $0.day <= throughDay }.sorted { $0.day < $1.day }
        guard let last = sorted.last else { return nil }
        var run: [DailyCandle] = [last]
        for c in sorted.dropLast().reversed() {
            guard c.day == run[0].day - 1 else { break }
            run.insert(c, at: 0)
        }
        let start = Date(timeIntervalSince1970: Double(run[0].day) * 86_400)
        return PriceHistory(startDate: start, bars: run.map {
            DayBar(open: $0.open, high: $0.high, low: $0.low, close: $0.close)
        })
    }
}

/// Fetches live daily candles: Kraken first, Coinbase as the fallback.
public struct LiveClient: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session { self.session = session } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 12
            cfg.httpCookieStorage = nil
            self.session = URLSession(configuration: cfg)
        }
    }

    public func fetch() async throws -> (source: String, candles: [DailyCandle]) {
        do {
            let url = URL(string: "https://api.kraken.com/0/public/OHLC?pair=XBTUSD&interval=1440")!
            let (data, _) = try await session.data(from: url)
            return ("Kraken", try LiveFeed.parseKraken(data))
        } catch {
            var req = URLRequest(url: URL(string: "https://api.exchange.coinbase.com/products/BTC-USD/candles?granularity=86400")!)
            req.setValue("OrangeRobotLab", forHTTPHeaderField: "User-Agent")
            do {
                let (data, _) = try await session.data(for: req)
                return ("Coinbase", try LiveFeed.parseCoinbase(data))
            } catch {
                throw LiveFeedError.network
            }
        }
    }
}

/// A forward test: rules locked at a moment in time, then judged on days that
/// had not happened when they were locked.
public struct LiveTest: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let strategy: Strategy
    /// UTC day (days since 1970) the test was started. Its close is the first one the robot sees.
    public let startDay: Int
    public let horizonDays: Int
    public let startCash: Double
    public let createdAt: Date
    /// SHA-256 of the locked rules, start day and horizon: proof the rules weren't changed afterwards.
    public let fingerprint: String
    public var recordedInNotebook: Bool
    /// Last UTC day whose trades the player has already been told about.
    public var lastNotifiedDay: Int?

    public init(strategy: Strategy, horizonDays: Int, now: Date = Date(), startCash: Double = 100_000) {
        let day = LiveFeed.dayNumber(now.timeIntervalSince1970)
        self.id = UUID()
        self.name = strategy.name
        self.strategy = strategy
        self.startDay = day
        self.horizonDays = horizonDays
        self.startCash = startCash
        self.createdAt = now
        self.fingerprint = Self.fingerprint(strategy: strategy, startDay: day, horizon: horizonDays)
        self.recordedInNotebook = false
        self.lastNotifiedDay = day - 1
    }

    public static func fingerprint(strategy: Strategy, startDay: Int, horizon: Int) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        var data = (try? enc.encode(strategy)) ?? Data()
        data.append(contentsOf: "|\(startDay)|\(horizon)".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public enum Track: String, Sendable { case sprint, marathon }

    /// 7-day tests are Sprints (an early look); 30 days and longer are Marathons.
    public var track: Track { horizonDays >= 30 ? .marathon : .sprint }

    /// Rules still match what was locked.
    public var isIntact: Bool {
        Self.fingerprint(strategy: strategy, startDay: startDay, horizon: horizonDays) == fingerprint
    }
}

public struct LiveStatus: Sendable {
    public enum Phase: Sendable { case waitingForFirstClose, running, finished }
    public let phase: Phase
    public let elapsedDays: Int
    public let horizonDays: Int
    /// Robot results over the test days so far (days index into `history`).
    public let robot: BacktestResult?
    public let robotEquity: [Double]
    public let holdEquity: [Double]
    public let history: PriceHistory?
    public let days: Range<Int>?
    public var latestCandleDay: Int?
    public var robotMetrics: Metrics? { robot?.metrics }
    public let holdMetrics: Metrics?
    /// The dollars both sides are measured on (cost basis for DCA, otherwise the starting cash).
    public var base: Double { holdEquity.first ?? 0 }
}

public enum LiveEvaluator {
    /// Run a live test against the candles available now. Today's unfinished candle is ignored.
    public static func evaluate(_ test: LiveTest, candles: [DailyCandle], now: Date = Date()) -> LiveStatus {
        let today = LiveFeed.dayNumber(now.timeIntervalSince1970)
        let closedThrough = today - 1
        func empty(_ phase: LiveStatus.Phase, elapsed: Int = 0) -> LiveStatus {
            LiveStatus(phase: phase, elapsedDays: elapsed, horizonDays: test.horizonDays, robot: nil,
                       robotEquity: [], holdEquity: [], history: nil, days: nil, latestCandleDay: nil,
                       holdMetrics: nil)
        }
        let elapsed = min(max(closedThrough - test.startDay + 1, 0), test.horizonDays)
        guard elapsed > 0 else { return empty(.waitingForFirstClose) }
        guard let history = LiveFeed.history(from: candles, throughDay: closedThrough) else { return empty(.waitingForFirstClose) }

        let firstDay = Int((history.startDate.timeIntervalSince1970 / 86_400).rounded())
        let from = test.startDay - firstDay
        guard from >= 0, from < history.count else { return empty(.waitingForFirstClose) }
        let to = min(from + elapsed, history.count)
        let range = from..<to

        let bt = Backtester(history: history)
        var settings = BacktestSettings(); settings.startCash = test.startCash
        let robot = bt.run(test.strategy, days: range, settings: settings)

        // Holding starts at the first open that comes *after* the test began, and is given the
        // same dollars the robot actually invested (its cost basis).
        let base = robot.base(startCash: test.startCash)
        var hold = [Double](repeating: base, count: robot.equity.count)
        if range.count > 1 {
            var hs = settings; hs.startCash = base
            let h = bt.buyAndHold(days: (from + 1)..<to, settings: hs)
            for (i, v) in h.equity.enumerated() { hold[i + 1] = v }
        }
        let holdMetrics = Backtester.metrics(equity: hold, trades: [], daysIn: hold.count, start: base)
        return LiveStatus(phase: elapsed >= test.horizonDays ? .finished : .running,
                          elapsedDays: elapsed, horizonDays: test.horizonDays,
                          robot: robot, robotEquity: robot.equity, holdEquity: hold,
                          history: history, days: range, latestCandleDay: closedThrough,
                          holdMetrics: holdMetrics)
    }
}


/// Something the robot did that is worth telling the player about.
public struct LiveEvent: Equatable, Sendable {
    public enum Kind: String, Sendable { case bought, sold }
    public let kind: Kind
    /// UTC day number (days since 1970) the trade happened on.
    public let day: Int
    public let price: Double
    public let reason: ExitReason?
    public let returnPercent: Double?

    /// Notification text.
    public func message(robot: String) -> String {
        switch kind {
        case .bought:
            return "\(robot) paper-bought at $\(Int(price.rounded()).formatted())."
        case .sold:
            let pct = returnPercent.map { String(format: " (%+.1f%%)", $0) } ?? ""
            return "\(robot) paper-sold at $\(Int(price.rounded()).formatted())\(pct)."
        }
    }
}

public extension LiveEvaluator {
    /// Every buy and sell in the test so far, oldest first.
    static func events(_ status: LiveStatus) -> [LiveEvent] {
        guard let robot = status.robot, let hist = status.history else { return [] }
        let first = Int((hist.startDate.timeIntervalSince1970 / 86_400).rounded())
        var out: [LiveEvent] = []
        if !robot.purchases.isEmpty {
            // A DCA robot's decisions are its scheduled buys.
            return robot.purchases.map {
                LiveEvent(kind: .bought, day: first + $0.day, price: $0.price, reason: nil, returnPercent: nil)
            }
        }
        for t in robot.trades {
            out.append(LiveEvent(kind: .bought, day: first + t.entryDay, price: t.entryPrice, reason: nil, returnPercent: nil))
            // The end-of-test close is bookkeeping, not a decision the robot made.
            if t.reason != .endOfTest {
                out.append(LiveEvent(kind: .sold, day: first + t.exitDay, price: t.exitPrice,
                                     reason: t.reason, returnPercent: t.returnPercent))
            }
        }
        return out.sorted { ($0.day, $0.kind.rawValue) < ($1.day, $1.kind.rawValue) }
    }

    /// Events newer than the last one the player was told about.
    static func newEvents(_ status: LiveStatus, after day: Int?) -> [LiveEvent] {
        events(status).filter { $0.day > (day ?? Int.min) }
    }
}
