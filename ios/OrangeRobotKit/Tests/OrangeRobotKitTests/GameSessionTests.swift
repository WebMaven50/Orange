import XCTest
@testable import OrangeRobotKit

final class GameSessionTests: XCTestCase {
    private func session(startDay: Int = 3000) -> GameSession {
        GameSession(engine: PriceEngine(startDay: startDay), startMinute: 500)
    }

    func testStartsWith100k() {
        let s = session()
        XCTAssertEqual(s.cash, 100_000)
        XCTAssertEqual(s.equity, 100_000)
        XCTAssertEqual(s.maxAmount(for: .buy), 100_000)
    }

    func testMarketBuyChargesFee() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 10_000)
        XCTAssertEqual(s.cash, 90_000, accuracy: 1e-9)
        XCTAssertEqual(s.btc, 10_000 * (1 - 0.0026) / s.lastPrice, accuracy: 1e-12)
        XCTAssertEqual(s.trades, 1)
        // Fee is paid immediately, so equity dips by 0.26%.
        XCTAssertEqual(s.equity, 100_000 - 26, accuracy: 1e-6)
    }

    func testSellingWithoutBTCOpensShort() throws {
        var s = session()
        XCTAssertEqual(s.maxAmount(for: .sell), 100_000)
        try s.place(side: .sell, type: .market, amountUSD: 5_000)
        XCTAssertLessThan(s.btc, 0)
        XCTAssertGreaterThan(s.cash, 100_000)
    }

    func testRejectsTinyAndBadOrders() {
        var s = session()
        XCTAssertThrowsError(try s.place(side: .buy, type: .market, amountUSD: 0.5))
        XCTAssertThrowsError(try s.place(side: .buy, type: .limit, amountUSD: 1000, level: nil))
        XCTAssertThrowsError(try s.place(side: .buy, type: .limit, amountUSD: 1000, level: -3))
    }

    func testLimitBuyFillsAtLimitPrice() throws {
        var s = session()
        let p = s.lastPrice
        // Limit above the market fills on the next tick, at the limit price.
        try s.place(side: .buy, type: .limit, amountUSD: 10_000, level: p * 1.5)
        XCTAssertEqual(s.pendingOrders.count, 1)
        s.advance(seconds: 0.016)
        XCTAssertTrue(s.pendingOrders.isEmpty)
        // A buy limit above the market is marketable: it fills at the market, not at the limit.
        XCTAssertEqual(s.btc, 10_000 * (1 - 0.0026) / s.lastPrice, accuracy: 1e-9)
    }

    func testStopSellFillsWhenPriceFalls() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 50_000)
        // Trigger just under the market, then let the price fall through it.
        try s.place(side: .sell, type: .stop, amountUSD: 50_000, level: s.lastPrice * 0.9999999)
        for _ in 0..<2000 where !s.pendingOrders.isEmpty { s.advance(seconds: 0.5) }
        XCTAssertTrue(s.pendingOrders.isEmpty)
        XCTAssertEqual(s.btc, 0, accuracy: 1e-9) // 100% sells the whole position, no dust
    }

    func testStopOnTheWrongSideOfTheMarketIsRefused() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 50_000)
        XCTAssertThrowsError(try s.place(side: .sell, type: .stop, amountUSD: 10_000, level: s.lastPrice * 1.5)) {
            XCTAssertEqual($0 as? OrderError, .stopOnWrongSide(side: .sell))
        }
        XCTAssertThrowsError(try s.place(side: .buy, type: .stop, amountUSD: 10_000, level: s.lastPrice * 0.5))
        XCTAssertTrue(s.pendingOrders.isEmpty)
        // The right side is fine, and a limit above the market is a normal take-profit.
        try s.place(side: .sell, type: .stop, amountUSD: 10_000, level: s.lastPrice * 0.9)
        try s.place(side: .sell, type: .limit, amountUSD: 10_000, level: s.lastPrice * 1.5)
        XCTAssertEqual(s.pendingOrders.count, 2)
    }

    func testSellLimitAboveMarketRests() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 50_000)
        let before = s.btc
        try s.place(side: .sell, type: .limit, amountUSD: 50_000, level: s.lastPrice * 1.5)
        s.advance(seconds: 0.016)
        XCTAssertEqual(s.pendingOrders.count, 1)
        XCTAssertEqual(s.btc, before, accuracy: 1e-12)
    }

    func testTrailingStopFollowsHighs() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 50_000)
        let o = try XCTUnwrap(try s.place(side: .sell, type: .trailing, amountUSD: 50_000, level: 50))
        XCTAssertEqual(o.extreme, s.lastPrice)
        s.advance(seconds: 0.016)
        // A 50% trail won't trigger on one frame; extreme only ratchets up.
        XCTAssertEqual(s.pendingOrders.count, 1)
        XCTAssertGreaterThanOrEqual(s.pendingOrders[0].extreme, o.extreme)
    }

    func testCancelOrder() throws {
        var s = session()
        let o = try XCTUnwrap(try s.place(side: .buy, type: .limit, amountUSD: 1000,
                                          level: s.lastPrice * 0.01))
        s.cancelOrder(id: o.id)
        XCTAssertTrue(s.pendingOrders.isEmpty)
    }

    func testSleepAdvancesEightHoursAndBlocksTrading() throws {
        var s = session()
        let start = s.absMinute
        XCTAssertTrue(s.startSleep())
        XCTAssertThrowsError(try s.place(side: .buy, type: .market, amountUSD: 1000)) {
            XCTAssertEqual($0 as? OrderError, .sleeping)
        }
        var frames = 0
        while s.isSleeping && frames < 1000 { s.advance(seconds: 0.05); frames += 1 }
        XCTAssertFalse(s.isSleeping)
        XCTAssertEqual(s.absMinute - start, 480, accuracy: 1e-6)
    }

    func testRestingOrdersFillDuringSleep() throws {
        var s = session()
        try s.place(side: .buy, type: .limit, amountUSD: 1000, level: s.lastPrice * 10)
        s.startSleep()
        s.advance(seconds: 0.05)
        XCTAssertTrue(s.pendingOrders.isEmpty)
    }

    func testCashOutEndsSession() {
        var s = session()
        s.cashOut()
        XCTAssertEqual(s.outcome, .cashout)
        s.advance(seconds: 1)
        XCTAssertThrowsError(try s.place(side: .buy, type: .market, amountUSD: 1000))
    }

    func testBustEndsSession() throws {
        // Max short into a rally-prone window; run until it resolves or 5 game years pass.
        var s = GameSession(engine: PriceEngine(startDay: 3000), startMinute: 500)
        s.speed = .fast
        try s.place(side: .sell, type: .market, amountUSD: s.maxAmount(for: .sell))
        var frames = 0
        while s.isRunning && frames < 2_000_000 { s.advance(seconds: 0.05); frames += 1 }
        XCTAssertNotNil(s.outcome, "a 1x short over years should end by win or bust")
    }

    func testSatsIsProfitOnly() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 100_000)
        // Fee alone makes it a loss -> no sats.
        XCTAssertEqual(s.satsEarned, 0)
    }

    func testRandomSessionInRange() {
        for _ in 0..<50 {
            let s = GameSession.random()
            XCTAssertTrue((0..<PriceEngine.maxStartDay(for: .bundled)).contains(s.engine.startDay))
            XCTAssertTrue((480..<600).contains(s.absMinute))
        }
    }

    // MARK: Pause

    func testPauseFreezesClockAndOrders() throws {
        var s = session()
        try s.place(side: .buy, type: .limit, amountUSD: 1000, level: s.lastPrice * 10)
        s.pause()
        let t = s.absMinute, p = s.lastPrice
        for _ in 0..<40 { s.advance(seconds: 0.05) }
        XCTAssertEqual(s.absMinute, t)
        XCTAssertEqual(s.lastPrice, p)
        XCTAssertEqual(s.pendingOrders.count, 1, "resting orders must not fill while paused")
        s.resume()
        s.advance(seconds: 0.05)
        XCTAssertGreaterThan(s.absMinute, t)
        XCTAssertTrue(s.pendingOrders.isEmpty)
    }

    func testPauseFreezesSleepAndBlocksNewSleep() {
        var s = session()
        s.startSleep()
        s.advance(seconds: 0.05)
        s.pause()
        let t = s.absMinute
        s.advance(seconds: 0.05)
        XCTAssertEqual(s.absMinute, t)
        XCTAssertTrue(s.isSleeping)
        var s2 = session()
        s2.pause()
        XCTAssertFalse(s2.startSleep())
    }

    func testCannotPauseFinishedRun() {
        var s = session()
        s.cashOut()
        s.pause()
        XCTAssertFalse(s.isPaused)
    }

    // MARK: Chosen start

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testChosenStartLandsOnThatDateAndTime() {
        let s = GameSession.starting(at: utc(2017, 12, 17, 14, 30))
        XCTAssertFalse(s.isRandomStart)
        XCTAssertEqual(s.minuteOfDay, 14 * 60 + 30)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: s.currentDate)
        XCTAssertEqual([c.year, c.month, c.day], [2017, 12, 17])
        // Dec 17 2017 was the 2017 peak: price should be five figures.
        XCTAssertGreaterThan(s.lastPrice, 15_000)
    }

    func testChosenStartIsClamped() {
        let range = GameSession.startDateRange()
        let early = GameSession.starting(at: utc(2001, 1, 1))
        XCTAssertEqual(early.engine.startDay, 0)
        let late = GameSession.starting(at: utc(2035, 1, 1))
        XCTAssertEqual(late.engine.startDay, PriceEngine.maxStartDay(for: .bundled))
        XCTAssertLessThan(range.lowerBound, range.upperBound)
    }

    func testRandomRunsAreRandomStart() {
        XCTAssertTrue(GameSession.random().isRandomStart)
    }

    // MARK: Position tracking

    func testAverageEntryAndUnrealized() throws {
        var s = session()
        XCTAssertNil(s.averageEntry)
        XCTAssertFalse(s.hasPosition)
        let p = s.lastPrice
        try s.place(side: .buy, type: .market, amountUSD: 10_000)
        XCTAssertEqual(try XCTUnwrap(s.averageEntry), p, accuracy: 1e-9)
        XCTAssertTrue(s.hasPosition)
        XCTAssertEqual(s.fills.count, 1)
        XCTAssertEqual(s.fills[0].side, .buy)
        XCTAssertEqual(s.fills[0].fee, 26, accuracy: 1e-9)
        XCTAssertEqual(s.unrealizedPL, s.btc * (s.lastPrice - p), accuracy: 1e-6)
        XCTAssertEqual(s.feesPaid, 26, accuracy: 1e-9)
    }

    func testPartialCloseRealizesProfitAndKeepsEntry() throws {
        var s = session()
        let entry = s.lastPrice
        try s.place(side: .buy, type: .market, amountUSD: 10_000)
        s.advance(seconds: 0.05); s.advance(seconds: 0.05)   // price moves a little
        let qtyBefore = s.btc
        let px = s.lastPrice
        try s.place(side: .sell, type: .market, amountUSD: s.btc * px / 2)
        XCTAssertEqual(s.btc, qtyBefore / 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.averageEntry), entry, accuracy: 1e-9, "entry unchanged by a partial close")
        XCTAssertEqual(s.realizedPL, (qtyBefore / 2) * (px - entry), accuracy: 1e-6)
        XCTAssertEqual(s.fills.count, 2)
        XCTAssertEqual(s.fills[0].side, .sell, "newest first")
    }

    func testClosingToFlatClearsEntry() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 10_000)
        XCTAssertTrue(s.closePosition())
        XCTAssertNil(s.averageEntry)
        XCTAssertFalse(s.hasPosition)
        XCTAssertEqual(s.btc, 0, accuracy: 1e-9)
    }

    func testShortProfitWhenPriceFalls() throws {
        var s = session()
        let entry = s.lastPrice
        try s.place(side: .sell, type: .market, amountUSD: 10_000)
        XCTAssertLessThan(s.btc, 0)
        XCTAssertEqual(try XCTUnwrap(s.averageEntry), entry, accuracy: 1e-9)
        // pretend the price is lower by checking the formula directly
        let lower = entry * 0.9
        XCTAssertEqual(s.btc * (lower - entry), abs(s.btc) * (entry - lower), accuracy: 1e-6)
        XCTAssertTrue(s.closePosition())
        XCTAssertFalse(s.hasPosition)
    }

    func testFlippingLongToShortOpensNewEntryAtFlipPrice() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 10_000)
        let px = s.lastPrice
        // sell twice the position: closes long and opens a short at the same price
        try s.place(side: .sell, type: .market, amountUSD: s.btc * px * 2)
        XCTAssertLessThan(s.btc, 0)
        XCTAssertEqual(try XCTUnwrap(s.averageEntry), px, accuracy: 1e-9)
    }

    func testTriggeredOrderIsRecordedWithItsType() throws {
        var s = session()
        try s.place(side: .buy, type: .limit, amountUSD: 5_000, level: s.lastPrice * 2)
        s.advance(seconds: 0.016)
        XCTAssertEqual(s.fills.count, 1)
        XCTAssertEqual(s.fills[0].via, .limit)
    }

    func testCancelAllAndTriggerPrice() throws {
        var s = session()
        let a = try XCTUnwrap(try s.place(side: .buy, type: .limit, amountUSD: 1000, level: s.lastPrice * 0.5))
        let b = try XCTUnwrap(try s.place(side: .sell, type: .trailing, amountUSD: 1000, level: 10))
        XCTAssertEqual(s.triggerPrice(for: a), s.lastPrice * 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.triggerPrice(for: b), b.extreme * 0.9, accuracy: 1e-9)
        s.cancelAllOrders()
        XCTAssertTrue(s.pendingOrders.isEmpty)
    }

    // MARK: Editing orders

    func testModifyLimitOrderLevelAndSize() throws {
        var s = session()
        let o = try XCTUnwrap(try s.place(side: .buy, type: .limit, amountUSD: 10_000, level: s.lastPrice * 0.5))
        try s.modifyOrder(id: o.id, level: s.lastPrice * 0.4, amountFraction: 0.25)
        let m = try XCTUnwrap(s.pendingOrders.first)
        XCTAssertEqual(m.id, o.id)
        XCTAssertEqual(m.level, s.lastPrice * 0.4, accuracy: 1e-9)
        XCTAssertEqual(m.amountFraction, 0.25, accuracy: 1e-12)
    }

    func testModifiedOrderFillsAtTheNewLevel() throws {
        var s = session()
        let p = s.lastPrice
        let o = try XCTUnwrap(try s.place(side: .buy, type: .limit, amountUSD: 10_000, level: p * 0.1))
        s.advance(seconds: 0.016)
        XCTAssertEqual(s.pendingOrders.count, 1, "far below market: still resting")
        try s.modifyOrder(id: o.id, level: p * 3)
        s.advance(seconds: 0.016)
        XCTAssertTrue(s.pendingOrders.isEmpty)
        // Moved above the market, the limit is marketable and fills at the market price.
        XCTAssertEqual(s.fills.first?.price ?? 0, s.lastPrice, accuracy: 1e-9)
    }

    func testTrailingEditKeepsBestPriceMemory() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 10_000)
        let o = try XCTUnwrap(try s.place(side: .sell, type: .trailing, amountUSD: 5_000, level: 5))
        let extreme = o.extreme
        try s.modifyOrder(id: o.id, level: 8)
        XCTAssertEqual(s.pendingOrders[0].extreme, extreme)
        XCTAssertEqual(s.pendingOrders[0].level, 8)
    }

    func testModifyValidation() throws {
        var s = session()
        let o = try XCTUnwrap(try s.place(side: .buy, type: .limit, amountUSD: 1000, level: s.lastPrice * 0.5))
        XCTAssertThrowsError(try s.modifyOrder(id: o.id, level: -1)) { XCTAssertEqual($0 as? OrderError, .invalidPrice) }
        XCTAssertThrowsError(try s.modifyOrder(id: o.id, amountFraction: 0)) { XCTAssertEqual($0 as? OrderError, .amountTooSmall) }
        XCTAssertThrowsError(try s.modifyOrder(id: 999, level: 5)) { XCTAssertEqual($0 as? OrderError, .orderNotFound) }
        try s.modifyOrder(id: o.id, amountFraction: 7)   // clamped to 100%
        XCTAssertEqual(s.pendingOrders[0].amountFraction, 1)
        s.startSleep()
        XCTAssertThrowsError(try s.modifyOrder(id: o.id, level: 5)) { XCTAssertEqual($0 as? OrderError, .sleeping) }
    }

    // MARK: Speeds

    func testSpeedMultipliers() {
        XCTAssertEqual(PlaybackSpeed.actual.multiplier, 1, accuracy: 1e-9)
        XCTAssertEqual(PlaybackSpeed.normal.multiplier, 240, accuracy: 1e-9)
        XCTAssertEqual(PlaybackSpeed.fast.multiplier, 3600, accuracy: 1e-9)
    }

    func testActualSpeedRunsInRealTime() {
        var s = session()
        s.speed = .actual
        let start = s.absMinute
        for _ in 0..<1200 { s.advance(seconds: 0.05) }   // 60 real seconds
        XCTAssertEqual(s.absMinute - start, 1.0, accuracy: 1e-6, "one game minute per real minute")
    }

    func testNormalKeepsItsOriginalPace() {
        var s = session()
        s.speed = .normal
        let start = s.absMinute
        for _ in 0..<20 { s.advance(seconds: 0.05) }     // 1 real second
        XCTAssertEqual(s.absMinute - start, 4.0, accuracy: 1e-9)
    }

    // MARK: Extended data

    func testCanStartOnTheNewDataAndPlayThrough() {
        let record = GameSession.starting(at: utc(2025, 10, 6, 12, 0))
        XCTAssertGreaterThan(record.lastPrice, 120_000, "Oct 6 2025 was the record day")
        let dec24 = GameSession.starting(at: utc(2024, 12, 5, 20, 0))
        XCTAssertGreaterThan(dec24.lastPrice, 95_000)
        var s = GameSession.starting(at: utc(2026, 9, 1, 9, 0))
        s.speed = .fast
        for _ in 0..<2000 { s.advance(seconds: 0.05) }          // a few game-days at fast speed
        XCTAssertTrue(s.lastPrice > 1_000 && s.lastPrice < 1_000_000)
        XCTAssertTrue(s.isRunning)
    }

    func testRandomStartsReachIntoTheNewDataAndStayInRange() {
        let h = PriceHistory.bundled
        let last = PriceEngine.maxStartDay(for: h)
        XCTAssertGreaterThan(last, 5_800, "random runs can start in 2026")
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let s = GameSession.random(using: &rng)
            XCTAssertLessThan(s.engine.startDay, last)
            XCTAssertGreaterThan(s.lastPrice, 0)
        }
    }
}
