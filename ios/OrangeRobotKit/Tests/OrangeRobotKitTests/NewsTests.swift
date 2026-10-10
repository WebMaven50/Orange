import XCTest
@testable import OrangeRobotKit

final class NewsTests: XCTestCase {
    private let feed = NewsFeed.bundled

    func testLoadsAndIsSubstantial() {
        XCTAssertGreaterThanOrEqual(feed.items.count, 80)
        XCTAssertGreaterThanOrEqual(feed.items.filter(\.significant).count, 25)
    }

    func testAllDatesParseAndStayInsideTheData() {
        let h = PriceHistory.bundled
        let end = Int((h.startDate.timeIntervalSince1970 / 86_400).rounded()) + h.count - 1
        for i in feed.items {
            XCTAssertNotNil(NewsItem.dayNumber(forISO: i.date), "bad date \(i.date)")
            XCTAssertLessThanOrEqual(i.dayNumber, end, "\(i.title) is after the price data ends")
        }
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(feed.items.map(\.id)).count, feed.items.count)
    }

    /// The core promise: no spoilers.
    func testNeverReturnsTheFuture() {
        for item in feed.items {
            let before = feed.items(upTo: item.dayNumber - 1)
            XCTAssertFalse(before.contains(item), "\(item.title) leaked a day early")
            XCTAssertTrue(feed.items(upTo: item.dayNumber).contains(item))
        }
        let day = NewsItem.dayNumber(forISO: "2013-06-01")!
        XCTAssertTrue(feed.items(upTo: day).allSatisfy { $0.dayNumber <= day })
    }

    func testNewestFirstOrdering() {
        let r = feed.items(upTo: NewsItem.dayNumber(forISO: "2020-01-01")!)
        XCTAssertEqual(r.map(\.dayNumber), r.map(\.dayNumber).sorted(by: >))
    }

    func testBannerTriggersFireOnceWhenTheClockCrossesTheDate() throws {
        let sig = try XCTUnwrap(feed.items.first { $0.significant && $0.dayNumber > 14_000 })
        let d = sig.dayNumber
        XCTAssertTrue(feed.significantItems(after: d - 2, upTo: d - 1).allSatisfy { $0 != sig })
        XCTAssertTrue(feed.significantItems(after: d - 1, upTo: d).contains(sig))
        XCTAssertFalse(feed.significantItems(after: d, upTo: d + 5).contains(sig), "must not fire twice")
    }

    func testSleepingAcrossSeveralDaysReturnsAllInOrder() {
        let a = NewsItem.dayNumber(forISO: "2022-11-08")!
        let b = NewsItem.dayNumber(forISO: "2022-11-11")!
        let hit = feed.significantItems(after: a - 1, upTo: b)
        XCTAssertEqual(hit.map(\.dayNumber), hit.map(\.dayNumber).sorted())
        XCTAssertTrue(hit.contains { $0.title.contains("FTX files") })
    }

    /// "First time above $X" headlines must agree with the game's own candles.
    func testPriceMilestonesMatchTheTicker() throws {
        let h = PriceHistory.bundled
        let start = Int((h.startDate.timeIntervalSince1970 / 86_400).rounded())
        var checked = 0
        for item in feed.items {
            guard let level = item.milestone else { continue }
            let from = item.since.flatMap(NewsItem.dayNumber(forISO:)).map { $0 - start } ?? 0
            let first = (max(0, from)..<h.count).first { h.bars[$0].high >= level }
            XCTAssertEqual(first.map { $0 + start }, item.dayNumber, "\(item.title)")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 8)
    }

    /// "New all-time record" headlines really are records in the data.
    func testRecordsAreRecords() throws {
        let h = PriceHistory.bundled
        let start = Int((h.startDate.timeIntervalSince1970 / 86_400).rounded())
        var checked = 0
        for item in feed.items where item.record == true {
            let i = item.dayNumber - start
            let priorMax = h.bars[..<i].map(\.high).max() ?? 0
            XCTAssertGreaterThan(h.bars[i].high, priorMax * 0.999, "\(item.title)")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 4)
    }

    /// Headlines are written as of their date: no hindsight about where prices went.
    func testNoHindsightLanguage() {
        let banned = ["later", "eventually", "would go on", "subsequently", "aftermath", "bottom", "all-time high of"]
        for i in feed.items {
            let text = (i.title + " " + (i.detail ?? "")).lowercased()
            for w in banned { XCTAssertFalse(text.contains(w), "\"\(w)\" in: \(i.title)") }
        }
    }

    func testSessionDayNumberMatchesNewsClock() {
        let s = GameSession.starting(at: Date(timeIntervalSince1970: 1_513_468_800)) // 2017-12-17 00:00 UTC
        XCTAssertEqual(s.currentDayNumber, NewsItem.dayNumber(forISO: "2017-12-17"))
    }

    // MARK: Tracker (price-triggered, no intraday spoilers)

    private func item(_ title: String) -> NewsItem { feed.items.first { $0.title.contains(title) }! }

    func testPriceHeadlineStaysHiddenUntilTheTickerReachesIt() {
        let cme = item("CME launches its own futures")
        let day = cme.dayNumber
        var t = NewsTracker(startDay: day)
        // 9am: price is well below the record the headline announces
        XCTAssertTrue(t.update(day: day, price: 19_000).isEmpty)
        XCTAssertFalse(t.visible(day: day).contains(cme), "must not spoil the day's record")
        // later that day the ticker reaches it
        let fired = t.update(day: day, price: 19_850)
        XCTAssertTrue(fired.contains(cme))
        XCTAssertTrue(t.visible(day: day).contains(cme))
        // and it never flashes twice
        XCTAssertTrue(t.update(day: day, price: 19_870).isEmpty)
    }

    func testFallHeadlineFiresWhenPriceDropsToTheLevel() {
        let crash = item("Black Thursday")
        let day = crash.dayNumber
        var t = NewsTracker(startDay: day)
        XCTAssertTrue(t.update(day: day, price: 7_900).isEmpty)
        XCTAssertFalse(t.visible(day: day).contains(crash))
        XCTAssertTrue(t.update(day: day, price: 6_000).contains(crash))
    }

    func testPlainSignificantItemFlashesWhenItsDayStarts() {
        let halving = item("Third halving")
        var t = NewsTracker(startDay: halving.dayNumber - 3)
        XCTAssertTrue(t.update(day: halving.dayNumber - 3, price: 8_000).allSatisfy { $0 != halving })
        XCTAssertFalse(t.visible(day: halving.dayNumber - 1).contains(halving))
        XCTAssertTrue(t.update(day: halving.dayNumber, price: 8_700).contains(halving))
    }

    func testPastPriceHeadlinesAreVisibleOnLaterDays() {
        let cme = item("CME launches its own futures")
        let t = NewsTracker(startDay: cme.dayNumber + 1)
        XCTAssertTrue(t.visible(day: cme.dayNumber + 1).contains(cme))
    }

    func testEveryTriggerIsReachableOnItsOwnDay() {
        let h = PriceHistory.bundled
        let start = Int((h.startDate.timeIntervalSince1970 / 86_400).rounded())
        var n = 0
        for i in feed.items {
            guard let trig = i.trigger else { continue }
            let bar = h.bars[i.dayNumber - start]
            XCTAssertTrue(i.firesOnFall ? bar.low <= trig : bar.high >= trig, i.title)
            n += 1
        }
        XCTAssertGreaterThanOrEqual(n, 15)
    }
}
