import XCTest
@testable import OrangeRobotKit

final class QuoteTests: XCTestCase {
    func testBundledQuotesLoadAndAreWellFormed() {
        let q = QuoteBook.bundled
        XCTAssertGreaterThanOrEqual(q.count, 10)
        XCTAssertEqual(Set(q.map(\.id)).count, q.count, "ids must be unique")
        for item in q {
            XCTAssertFalse(item.text.isEmpty)
            XCTAssertLessThanOrEqual(item.text.count, 160, "one line: \(item.text)")
        }
        for kind in [Quote.Kind.site, .scripture, .original] {
            XCTAssertTrue(q.contains { $0.kind == kind }, "missing kind \(kind)")
        }
    }

    func testEveryQuoteIsShownOnceBeforeAnyRepeat() {
        var deck = QuoteDeck()
        var rng = SplitMix64(seed: 5)
        var shown: [String] = []
        for _ in 0..<deck.quotes.count { shown.append(deck.next(using: &rng)!.id) }
        XCTAssertEqual(Set(shown).count, deck.quotes.count)
    }

    func testReshuffleNeverRepeatsTheLastLineImmediately() {
        var rng = SplitMix64(seed: 11)
        for round in 0..<40 {
            var deck = QuoteDeck(seen: [], last: nil)
            var prev: String?
            for i in 0..<(deck.quotes.count * 3) {
                let id = deck.next(using: &rng)!.id
                if i > 0 { XCTAssertNotEqual(id, prev, "round \(round) step \(i)") }
                prev = id
            }
        }
    }

    func testProgressCanBeSavedAndRestored() {
        var rng = SplitMix64(seed: 3)
        let plain = QuoteBook.bundled.filter { $0.group == nil }
        var deck = QuoteDeck(quotes: plain)
        let first = deck.next(using: &rng)!
        var restored = QuoteDeck(quotes: deck.quotes, seen: deck.seen, last: deck.last, recent: deck.recent)
        var rest: [String] = []
        for _ in 0..<(deck.quotes.count - 1) { rest.append(restored.next(using: &rng)!.id) }
        XCTAssertFalse(rest.contains(first.id), "the one already shown is not dealt again this cycle")
    }

    func testLifeboatLinesAreNeverCloseTogether() {
        var rng = SplitMix64(seed: 9)
        for _ in 0..<60 {
            var deck = QuoteDeck()
            var ids: [String] = []
            for _ in 0..<(deck.quotes.count * 4) { ids.append(deck.next(using: &rng)!.id) }
            let group = Set(deck.quotes.filter { $0.group == "lifeboat" }.map(\.id))
            XCTAssertEqual(group.count, 2)
            let at = ids.enumerated().filter { group.contains($0.element) }.map(\.offset)
            for (a, b) in zip(at, at.dropFirst()) {
                XCTAssertGreaterThan(b - a, QuoteDeck.groupGap - 1, "positions \(a),\(b)")
            }
        }
    }

    func testEmptyDeckIsSafe() {
        var deck = QuoteDeck(quotes: [])
        XCTAssertNil(deck.next())
    }
}
