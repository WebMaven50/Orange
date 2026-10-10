import Foundation

/// One real daily Bitcoin candle.
public struct DayBar: Equatable, Sendable {
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
}

/// The real daily BTC/USD history the game is played on.
public struct PriceHistory: Sendable {
    public let startDate: Date
    public let bars: [DayBar]

    public var count: Int { bars.count }

    public init(startDate: Date, bars: [DayBar]) {
        precondition(!bars.isEmpty, "PriceHistory needs at least one bar")
        self.startDate = startDate
        self.bars = bars
    }

    /// Bar for a day index. Out-of-range indices wrap, matching the web game.
    public func bar(at index: Int) -> DayBar {
        let n = bars.count
        return bars[((index % n) + n) % n]
    }

    /// The history bundled with the package (Jul 2010 – Sep 2024).
    public static let bundled: PriceHistory = {
        guard let url = Bundle.module.url(forResource: "btc_daily", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(Raw.self, from: data)
        else { fatalError("btc_daily.json missing or unreadable") }
        return PriceHistory(from: raw)
    }()

    private struct Raw: Decodable {
        let startDate: String
        let days: Int
        let ohlc: [Double]
    }

    private init(from raw: Raw) {
        var bars: [DayBar] = []
        bars.reserveCapacity(raw.days)
        for i in 0..<raw.days {
            let o = i * 4
            bars.append(DayBar(open: raw.ohlc[o], high: raw.ohlc[o + 1],
                               low: raw.ohlc[o + 2], close: raw.ohlc[o + 3]))
        }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        self.init(startDate: f.date(from: raw.startDate)!, bars: bars)
    }
}
