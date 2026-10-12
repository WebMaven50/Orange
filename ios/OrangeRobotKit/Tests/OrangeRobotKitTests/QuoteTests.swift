import XCTest
@testable import OrangeRobotKit

final class QuoteTests: XCTestCase {
    func testBundledQuotesLoadAndAreWellFormed() {
        let q = QuoteBook.bundled
        XCTAssertGreaterThanOrEqual(q.count, 12)
        XCTAssertEqual(Set(q.map(\.id)).count, q.count, "ids must be unique")
        for item in q {
            XCTAssertFalse(item.text.isEmpty)
            XCTAssertFalse(item.source.isEmpty)
            XCTAssertLessThanOrEqual(item.text.count, 160, "one line: \(item.text)")
        }
        for kind in [Quote.Kind.book, .scripture, .original] {
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
        var deck = QuoteDeck()
        let first = deck.next(using: &rng)!
        var restored = QuoteDeck(quotes: deck.quotes, seen: deck.seen, last: deck.last)
        var rest: [String] = []
        for _ in 0..<(deck.quotes.count - 1) { rest.append(restored.next(using: &rng)!.id) }
        XCTAssertFalse(rest.contains(first.id), "the one already shown is not dealt again this cycle")
    }

    func testEmptyDeckIsSafe() {
        var deck = QuoteDeck(quotes: [])
        XCTAssertNil(deck.next())
    }
}
