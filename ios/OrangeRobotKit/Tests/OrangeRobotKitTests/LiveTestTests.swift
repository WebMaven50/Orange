import XCTest
@testable import OrangeRobotKit

final class LiveTestTests: XCTestCase {
    // MARK: Parsers (fixtures shaped like the real APIs)

    func testParsesKraken() throws {
        let json = #"""
        {"error":[],"result":{"XXBTZUSD":[
          [1728000000,"62000.0","63000.5","61500.1","62800.9","62500.0","100.5",1200],
          [1728086400,"62800.9","64000.0","62000.0","63900.2","63000.0","90.1",1100]
        ],"last":1728086400}}
        """#
        let c = try LiveFeed.parseKraken(Data(json.utf8))
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c[0].open, 62000.0)
        XCTAssertEqual(c[0].high, 63000.5)
        XCTAssertEqual(c[0].low, 61500.1)
        XCTAssertEqual(c[0].close, 62800.9)
        XCTAssertEqual(c[1].day, c[0].day + 1)
        XCTAssertEqual(c[0].day, 1728000000 / 86_400)
    }

    func testParsesCoinbaseNewestFirstAndSortsOldestFirst() throws {
        // [time, low, high, open, close, volume]
        let json = "[[1728086400,62000,64000,62800,63900,10],[1728000000,61500,63000,62000,62800,12]]"
        let c = try LiveFeed.parseCoinbase(Data(json.utf8))
        XCTAssertEqual(c.map(\.day), [1728000000 / 86_400, 1728086400 / 86_400])
        XCTAssertEqual(c[0].open, 62000)   // 4th column is open
        XCTAssertEqual(c[0].low, 61500)    // 2nd column is low
        XCTAssertEqual(c[0].high, 63000)
        XCTAssertEqual(c[0].close, 62800)
    }

    func testMalformedAndEmptyPayloads() {
        XCTAssertThrowsError(try LiveFeed.parseKraken(Data("{}".utf8)))
        XCTAssertThrowsError(try LiveFeed.parseCoinbase(Data("{}".utf8)))
        XCTAssertThrowsError(try LiveFeed.parseCoinbase(Data("[]".utf8))) { XCTAssertEqual($0 as? LiveFeedError, .noData) }
    }

    // MARK: History building

    private func candles(_ days: [Int], base: Double = 100) -> [DailyCandle] {
        days.map { DailyCandle(day: $0, open: base, high: base + 1, low: base - 1, close: base) }
    }

    func testHistoryUsesOnlyTheUnbrokenRunAndDropsFutureDays() throws {
        let c = candles([10, 11, 12, 14, 15, 16, 17])   // gap at 13
        let h = try XCTUnwrap(LiveFeed.history(from: c, throughDay: 16))
        XCTAssertEqual(h.count, 3)                       // 14, 15, 16
        XCTAssertEqual(Int((h.startDate.timeIntervalSince1970 / 86_400).rounded()), 14)
    }

    // MARK: The test itself

    /// A day-number for a fixed "now" so the tests don't depend on the clock.
    private func at(day: Int, hour: Int = 12) -> Date { Date(timeIntervalSince1970: Double(day) * 86_400 + Double(hour) * 3_600) }

    private func strategy() -> Strategy {
        Strategy(name: "Trend", entry: [.priceAboveMA(period: 3)], positionPercent: 100)
    }

    /// 60 flat days, then a ramp: the signal fires a few days after the start.
    private func market(startDay: Int, flatDays: Int = 60, rampDays: Int = 20) -> [DailyCandle] {
        var out: [DailyCandle] = []
        var d = startDay - flatDays
        for _ in 0..<flatDays { out.append(DailyCandle(day: d, open: 100, high: 100, low: 100, close: 100)); d += 1 }
        for k in 0..<rampDays {
            let p = 100.0 + Double(k + 1) * 3
            out.append(DailyCandle(day: d, open: p - 2, high: p + 1, low: p - 3, close: p)); d += 1
        }
        return out
    }

    func testLockedRulesHaveAStableFingerprintAndDetectTampering() {
        let t = LiveTest(strategy: strategy(), horizonDays: 14, now: at(day: 20_000))
        XCTAssertEqual(t.fingerprint.count, 64)
        XCTAssertTrue(t.isIntact)
        var other = strategy(); other.stopLossPercent = 5
        XCTAssertNotEqual(t.fingerprint,
                          LiveTest.fingerprint(strategy: other, startDay: t.startDay, horizon: 14))
        XCTAssertEqual(t.fingerprint,
                       LiveTest.fingerprint(strategy: strategy(), startDay: t.startDay, horizon: 14))
    }

    func testWaitsForTheFirstCloseOnTheDayItStarts() {
        let t = LiveTest(strategy: strategy(), horizonDays: 14, now: at(day: 20_000))
        let s = LiveEvaluator.evaluate(t, candles: market(startDay: 20_000), now: at(day: 20_000, hour: 15))
        XCTAssertEqual(s.phase, .waitingForFirstClose)
        XCTAssertNil(s.robot)
    }

    func testNeverUsesCandlesFromTheFuture() {
        let t = LiveTest(strategy: strategy(), horizonDays: 14, now: at(day: 20_000))
        // Candles through day 20_019 exist, but "now" is only day 20_003.
        let s = LiveEvaluator.evaluate(t, candles: market(startDay: 20_000), now: at(day: 20_003))
        XCTAssertEqual(s.elapsedDays, 3)                 // days 20_000...20_002 have closed
        XCTAssertEqual(s.latestCandleDay, 20_002)
        XCTAssertEqual(s.days?.count, 3)
    }

    func testProgressesToFinished() {
        let t = LiveTest(strategy: strategy(), horizonDays: 14, now: at(day: 20_000))
        let mid = LiveEvaluator.evaluate(t, candles: market(startDay: 20_000), now: at(day: 20_008))
        XCTAssertEqual(mid.phase, .running)
        XCTAssertEqual(mid.elapsedDays, 8)
        let done = LiveEvaluator.evaluate(t, candles: market(startDay: 20_000), now: at(day: 20_030))
        XCTAssertEqual(done.phase, .finished)
        XCTAssertEqual(done.elapsedDays, 14)
        XCTAssertEqual(done.robotEquity.count, 14)
        XCTAssertEqual(done.holdEquity.count, 14)
    }

    func testRobotAndHoldingBothStartAtTheStartingCash() throws {
        let t = LiveTest(strategy: strategy(), horizonDays: 14, now: at(day: 20_000))
        let s = LiveEvaluator.evaluate(t, candles: market(startDay: 20_000), now: at(day: 20_010))
        XCTAssertEqual(s.robotEquity.first, 100_000)
        XCTAssertEqual(s.holdEquity.first, 100_000)
    }

    func testResultsAreReproducible() throws {
        let t = LiveTest(strategy: strategy(), horizonDays: 14, now: at(day: 20_000))
        let a = LiveEvaluator.evaluate(t, candles: market(startDay: 20_000), now: at(day: 20_030))
        let b = LiveEvaluator.evaluate(t, candles: market(startDay: 20_000), now: at(day: 20_030))
        XCTAssertEqual(a.robotEquity, b.robotEquity)
        XCTAssertEqual(a.robot?.trades, b.robot?.trades)
    }

    func testLiveTestIsCodable() throws {
        let t = LiveTest(strategy: strategy(), horizonDays: 30, now: at(day: 20_000))
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(LiveTest.self, from: data)
        XCTAssertEqual(back, t)
        XCTAssertTrue(back.isIntact)
    }
}

final class LiveEventTests: XCTestCase {
    private func at(day: Int) -> Date { Date(timeIntervalSince1970: Double(day) * 86_400 + 43_200) }

    private func ramp(from startDay: Int, flat: Int = 60, up: Int = 20, down: Int = 20) -> [DailyCandle] {
        var out: [DailyCandle] = []
        var d = startDay - flat
        for _ in 0..<flat { out.append(DailyCandle(day: d, open: 100, high: 100, low: 100, close: 100)); d += 1 }
        var p = 100.0
        for _ in 0..<up { p += 4; out.append(DailyCandle(day: d, open: p - 3, high: p + 1, low: p - 4, close: p)); d += 1 }
        for _ in 0..<down { p -= 5; out.append(DailyCandle(day: d, open: p + 4, high: p + 5, low: p - 1, close: p)); d += 1 }
        return out
    }

    private func test(horizon: Int) -> LiveTest {
        var s = Strategy(name: "Trend", entry: [.priceAboveMA(period: 3)], exit: [.priceBelowMA(period: 3)],
                         positionPercent: 100)
        s.stopLossPercent = nil
        return LiveTest(strategy: s, horizonDays: horizon, now: at(day: 20_000))
    }

    func testTrackIsSprintForAWeekAndMarathonForLonger() {
        XCTAssertEqual(test(horizon: 7).track, .sprint)
        XCTAssertEqual(test(horizon: 14).track, .sprint)
        XCTAssertEqual(test(horizon: 30).track, .marathon)
        XCTAssertEqual(test(horizon: 90).track, .marathon)
    }

    func testEventsListBuysAndSellsInOrder() {
        let t = test(horizon: 40)
        let s = LiveEvaluator.evaluate(t, candles: ramp(from: 20_000), now: at(day: 20_041))
        let ev = LiveEvaluator.events(s)
        XCTAssertFalse(ev.isEmpty)
        XCTAssertEqual(ev.first?.kind, .bought)
        XCTAssertEqual(ev.map(\.day), ev.map(\.day).sorted())
        XCTAssertTrue(ev.contains { $0.kind == .sold })
    }

    func testNewEventsOnlyReturnsWhatWasNotAnnouncedYet() {
        let t = test(horizon: 40)
        let s = LiveEvaluator.evaluate(t, candles: ramp(from: 20_000), now: at(day: 20_041))
        let all = LiveEvaluator.events(s)
        let firstDay = all[0].day
        XCTAssertEqual(LiveEvaluator.newEvents(s, after: nil).count, all.count)
        XCTAssertEqual(LiveEvaluator.newEvents(s, after: firstDay).count, all.filter { $0.day > firstDay }.count)
        XCTAssertTrue(LiveEvaluator.newEvents(s, after: all.last!.day).isEmpty)
    }

    func testNothingToAnnounceBeforeTheFirstClose() {
        let t = test(horizon: 14)
        let s = LiveEvaluator.evaluate(t, candles: ramp(from: 20_000), now: at(day: 20_000))
        XCTAssertTrue(LiveEvaluator.events(s).isEmpty)
    }

    func testNewTestStartsWithNothingAlreadyAnnounced() {
        let t = test(horizon: 14)
        XCTAssertEqual(t.lastNotifiedDay, t.startDay - 1)
    }

    func testOldSavedTestsWithoutTheNewFieldStillLoad() throws {
        let t = test(horizon: 14)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(t)) as? [String: Any])
        json.removeValue(forKey: "lastNotifiedDay")
        let data = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(LiveTest.self, from: data)
        XCTAssertNil(back.lastNotifiedDay)
    }

    func testMessages() {
        let b = LiveEvent(kind: .bought, day: 1, price: 61_234.4, reason: nil, returnPercent: nil)
        XCTAssertTrue(b.message(robot: "Trend").contains("paper-bought at $61,234"))
        let s = LiveEvent(kind: .sold, day: 2, price: 64_000, reason: .takeProfit, returnPercent: 4.5)
        XCTAssertTrue(s.message(robot: "Trend").contains("(+4.5%)"))
    }
}
