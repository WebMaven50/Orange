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
        XCTAssertEqual(s.btc, 10_000 * (1 - 0.0026) / (p * 1.5), accuracy: 1e-9)
    }

    func testStopSellFillsWhenPriceFalls() throws {
        var s = session()
        try s.place(side: .buy, type: .market, amountUSD: 50_000)
        try s.place(side: .sell, type: .stop, amountUSD: 50_000, level: s.lastPrice * 2)
        s.advance(seconds: 0.016) // price already below trigger
        XCTAssertTrue(s.pendingOrders.isEmpty)
        XCTAssertEqual(s.btc, 0, accuracy: 1e-9) // 100% sells the whole position, no dust
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
}
