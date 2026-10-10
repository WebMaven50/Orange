import Foundation

public enum NewsTag: String, Codable, Sendable, CaseIterable {
    case bitcoin, markets, regulation, security, tech, adoption
}

/// A real, dated headline. Written as of its own date: it never describes
/// anything that happened afterwards.
public struct NewsItem: Decodable, Identifiable, Equatable, Sendable {
    /// `yyyy-MM-dd`, UTC.
    public let date: String
    public let title: String
    public let detail: String?
    public let tag: NewsTag
    /// Big enough to flash a breaking-news banner when the game clock reaches it.
    public let significant: Bool
    /// For "first time above $X" items: the price threshold (kept in sync with the data by tests).
    public let milestone: Double?
    public let since: String?
    /// For "new all-time record" items.
    public let record: Bool?
    /// If set, the headline is only released once the ticker actually reaches this price
    /// on its date, so it never announces a price move before it happens.
    public let trigger: Double?
    /// `"below"` for falls; anything else (or nil) means the ticker must rise to `trigger`.
    public let direction: String?

    public var firesOnFall: Bool { direction == "below" }

    public var id: String { date + "|" + title }

    /// Days since 1970-01-01 (UTC): the unit the game clock is compared in.
    public var dayNumber: Int { Self.dayNumber(forISO: date) ?? 0 }

    static func dayNumber(forISO s: String) -> Int? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        guard let d = c.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        return Int((d.timeIntervalSince1970 / 86_400).rounded())
    }
}

/// The bundled timeline, filtered by what has already happened in the game.
public struct NewsFeed: Sendable {
    /// Oldest first.
    public let items: [NewsItem]

    public init(items: [NewsItem]) {
        self.items = items.sorted { ($0.dayNumber, $0.title) < ($1.dayNumber, $1.title) }
    }

    public static let bundled: NewsFeed = {
        struct File: Decodable { let items: [NewsItem] }
        guard let url = Bundle.module.url(forResource: "news", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return NewsFeed(items: []) }
        return NewsFeed(items: file.items)
    }()

    /// Everything on or before `day`, newest first. Nothing later is ever returned.
    public func items(upTo day: Int, limit: Int? = nil) -> [NewsItem] {
        let past = items.filter { $0.dayNumber <= day }.reversed()
        return Array(limit.map { Array(past.prefix($0)) } ?? Array(past))
    }

    /// Significant items the clock has just reached: `previousDay < date <= day`, oldest first.
    public func significantItems(after previousDay: Int, upTo day: Int) -> [NewsItem] {
        items.filter { $0.significant && $0.dayNumber > previousDay && $0.dayNumber <= day }
    }

    /// How many items (significant or not) fall in `(seenDay, day]`.
    public func count(after seenDay: Int, upTo day: Int) -> Int {
        items.filter { $0.dayNumber > seenDay && $0.dayNumber <= day }.count
    }
}

public extension GameSession {
    /// The game's current calendar day as days since 1970-01-01 (UTC).
    var currentDayNumber: Int { Int((currentDate.timeIntervalSince1970 / 86_400).rounded()) }
}


/// Decides, tick by tick, which headlines the player is allowed to see and
/// which should flash as breaking news. Strictly no spoilers: a price-triggered
/// headline stays hidden until the ticker reaches that price.
public struct NewsTracker: Sendable {
    public let feed: NewsFeed
    private var lastDay: Int
    private var reached: Set<String> = []

    public init(feed: NewsFeed = .bundled, startDay: Int) {
        self.feed = feed
        self.lastDay = startDay - 1   // events dated on the start day itself still flash
    }

    /// Advance the tracker. Returns the significant headlines that were just released.
    public mutating func update(day: Int, price: Double) -> [NewsItem] {
        var released: [NewsItem] = []
        if day > lastDay {
            // Newly started days: plain items release at the start of their day;
            // price-triggered items from days we skipped over are simply past news.
            for i in feed.items where i.dayNumber > lastDay && i.dayNumber <= day {
                if i.trigger == nil, i.significant { released.append(i) }
            }
            lastDay = day
        }
        for i in feed.items where i.dayNumber == day {
            guard let t = i.trigger, !reached.contains(i.id) else { continue }
            let hit = i.firesOnFall ? price <= t : price >= t
            if hit {
                reached.insert(i.id)
                if i.significant { released.append(i) }
            }
        }
        return released.sorted { $0.dayNumber < $1.dayNumber }
    }

    /// What the player may read right now, newest first.
    public func visible(day: Int, limit: Int? = nil) -> [NewsItem] {
        let v = feed.items.filter { isVisible($0, day: day) }.reversed()
        return limit.map { Array(v.prefix($0)) } ?? Array(v)
    }

    public func isVisible(_ i: NewsItem, day: Int) -> Bool {
        if i.dayNumber < day { return true }
        if i.dayNumber > day { return false }
        return i.trigger == nil || reached.contains(i.id)
    }

    /// Visible headlines newer than `seenDay`.
    public func unread(after seenDay: Int, day: Int) -> Int {
        feed.items.filter { $0.dayNumber > seenDay && isVisible($0, day: day) }.count
    }
}
