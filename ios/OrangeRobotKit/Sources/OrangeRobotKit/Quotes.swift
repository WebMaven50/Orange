import Foundation

/// A single line shown before a run: from the book, the site, scripture, or written for the game.
public struct Quote: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case book, site, scripture, original }

    public let text: String
    public let source: String
    public let kind: Kind
    /// Lines sharing a group are never dealt close together (e.g. two lifeboat lines).
    public let group: String?

    /// Stable across launches (derived from the text), so "already shown" survives updates.
    public var id: String { String(text.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }) }
}

public enum QuoteBook {
    public static let bundled: [Quote] = {
        struct File: Decodable { let quotes: [Quote] }
        guard let url = Bundle.module.url(forResource: "quotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.quotes
    }()
}

/// Deals quotes like a shuffled deck: every line is seen once before any repeats, and the
/// first line after a reshuffle is never the one just shown.
public struct QuoteDeck: Sendable {
    public let quotes: [Quote]
    public private(set) var seen: Set<String>
    public private(set) var last: String?
    public private(set) var recent: [String]

    /// How many lines must pass before another from the same group can appear.
    public static let groupGap = 5

    public init(quotes: [Quote] = QuoteBook.bundled, seen: Set<String> = [], last: String? = nil,
                recent: [String] = []) {
        self.quotes = quotes
        self.seen = seen
        self.last = last
        self.recent = recent.isEmpty ? (last.map { [$0] } ?? []) : recent
    }

    public mutating func next<G: RandomNumberGenerator>(using rng: inout G) -> Quote? {
        guard !quotes.isEmpty else { return nil }
        var pool = quotes.filter { !seen.contains($0.id) }
        if pool.isEmpty {                        // everything shown: reshuffle
            seen = []
            pool = quotes.filter { $0.id != last }
            if pool.isEmpty { pool = quotes }
        }
        let recentGroups = Set(recent.suffix(Self.groupGap).compactMap { id in
            quotes.first { $0.id == id }?.group
        })
        let spaced = pool.filter { $0.group == nil || !recentGroups.contains($0.group!) }
        var candidates = spaced
        if candidates.isEmpty {                  // only a close group-mate is left: reach back instead
            let held = Set(recent)
            candidates = quotes.filter {
                !held.contains($0.id) && ($0.group == nil || !recentGroups.contains($0.group!))
            }
        }
        let pick = (candidates.isEmpty ? pool : candidates).randomElement(using: &rng)!
        seen.insert(pick.id)
        last = pick.id
        recent.append(pick.id)
        if recent.count > Self.groupGap { recent.removeFirst(recent.count - Self.groupGap) }
        return pick
    }

    public mutating func next() -> Quote? {
        var rng = SystemRandomNumberGenerator()
        return next(using: &rng)
    }
}
