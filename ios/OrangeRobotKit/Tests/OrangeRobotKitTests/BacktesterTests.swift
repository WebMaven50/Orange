import XCTest
@testable import OrangeRobotKit

final class BacktesterTests: XCTestCase {
    private typealias B = (o: Double, h: Double, l: Double, c: Double)

    private func history(_ bars: [B]) -> PriceHistory {
        PriceHistory(startDate: Date(timeIntervalSince1970: 1_600_000_000),
                     bars: bars.map { DayBar(open: $0.o, high: $0.h, low: $0.l, close: $0.c) })
    }
    private func flat(_ p: Double, _ n: Int) -> [B] { Array(repeating: (p, p, p, p), count: n) }

    /// No costs, so expected numbers are easy to check by hand.
    private var free: BacktestSettings {
        var s = BacktestSettings(); s.fee = 0; s.slippage = 0; return s
    }
    private let trigger = Strategy(name: "t", entry: [.priceAboveMA(period: 3)], positionPercent: 100)

    /// 5 flat days at 100, then a jump to 110 on day 5 (signal fires at that close).
    private func jump(then rest: [B]) -> [B] { flat(100, 5) + [(100, 110, 100, 110)] + rest }

    func testBuysAtTheNextOpenNotTheSignalCandle() throws {
        let h = history(jump(then: [(112, 113, 111, 112), (112, 114, 111, 113)]))
        let r = Backtester(history: h).run(trigger, days: 0..<h.count, settings: free)
        let t = try XCTUnwrap(r.trades.first)
        XCTAssertEqual(t.entryDay, 6)                       // signal on day 5, fill on day 6
        XCTAssertEqual(t.entryPrice, 112, accuracy: 1e-9)   // at that day's open
    }

    func testStopLossFillsAtTheStopPrice() throws {
        var s = trigger; s.stopLossPercent = 10
        let h = history(jump(then: [(110, 110, 110, 110), (110, 110, 95, 96), (96, 96, 96, 96)]))
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        let t = try XCTUnwrap(r.trades.first)
        XCTAssertEqual(t.reason, .stopLoss)
        XCTAssertEqual(t.exitPrice, 99, accuracy: 1e-9)      // 110 * 0.9
        XCTAssertEqual(t.returnPercent, -10, accuracy: 1e-6)
    }

    func testGapThroughTheStopFillsAtTheOpen() throws {
        var s = trigger; s.stopLossPercent = 10
        let h = history(jump(then: [(110, 110, 110, 110), (90, 92, 88, 89)]))
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        let t = try XCTUnwrap(r.trades.first)
        XCTAssertEqual(t.exitPrice, 90, accuracy: 1e-9, "a gap below the stop fills at the open, not the stop")
    }

    func testTakeProfitFillsAtTheTarget() throws {
        var s = trigger; s.takeProfitPercent = 20
        let h = history(jump(then: [(110, 110, 110, 110), (110, 140, 109, 130)]))
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        let t = try XCTUnwrap(r.trades.first)
        XCTAssertEqual(t.reason, .takeProfit)
        XCTAssertEqual(t.exitPrice, 132, accuracy: 1e-9)
    }

    func testStopBeatsTakeProfitWhenBothTouchInOneCandle() throws {
        var s = trigger; s.stopLossPercent = 10; s.takeProfitPercent = 20
        let h = history(jump(then: [(110, 110, 110, 110), (110, 140, 90, 120)]))
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        XCTAssertEqual(r.trades.first?.reason, .stopLoss, "assume the worse outcome")
    }

    func testTrailingStopFollowsTheHigh() throws {
        var s = trigger; s.trailingStopPercent = 10
        let rise: [B] = [(110, 110, 110, 110), (110, 150, 110, 150), (150, 150, 150, 150), (150, 150, 130, 131)]
        let h = history(jump(then: rise))
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        let t = try XCTUnwrap(r.trades.first)
        XCTAssertEqual(t.reason, .trailingStop)
        XCTAssertEqual(t.exitPrice, 135, accuracy: 1e-9)    // 150 * 0.9
    }

    func testLimitEntryWaitsForTheDip() throws {
        var s = trigger; s.limitEntryDiscountPercent = 5     // 110 * 0.95 = 104.5
        let h = history(jump(then: [(112, 113, 111, 112), (111, 112, 104, 108), (108, 109, 107, 108)]))
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        let t = try XCTUnwrap(r.trades.first)
        XCTAssertEqual(t.entryDay, 7)
        XCTAssertEqual(t.entryPrice, 104.5, accuracy: 1e-9)
    }

    func testLimitEntryExpires() {
        var s = trigger; s.limitEntryDiscountPercent = 5
        let up: [B] = Array(repeating: (112, 114, 111, 113), count: 6)      // never dips to 104.5
        let h = history(jump(then: up))
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        XCTAssertTrue(r.trades.isEmpty)
    }

    func testSignalThatStaysOnBuysOnlyOnce() {
        var s = trigger; s.maxHoldDays = 2
        var up: [B] = []
        for k in 0..<10 {
            let base = Double(111 + k)
            up.append((base, base + 1, base - 1, base))
        }
        let h = history(jump(then: up))
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        XCTAssertEqual(r.trades.count, 1, "no re-buying while the same signal remains on")
    }

    func testExitSignalSellsAtTheNextOpen() throws {
        var s = trigger; s.exit = [.priceBelowMA(period: 3)]
        // jump, hold, then a drop that pushes price below its 3-day average
        let h = history(jump(then: [(112, 113, 111, 112), (112, 113, 111, 112), (100, 101, 90, 92), (91, 92, 90, 91)]))
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        let t = try XCTUnwrap(r.trades.first)
        XCTAssertEqual(t.reason, .signal)
        XCTAssertEqual(t.exitDay, 9)                        // signal at day 8's close, sell day 9's open
        XCTAssertEqual(t.exitPrice, 91, accuracy: 1e-9)
    }

    func testFeesAndSlippageReduceReturn() throws {
        let h = history(jump(then: [(112, 113, 111, 112), (112, 114, 111, 113)]))
        let a = Backtester(history: h).run(trigger, days: 0..<h.count, settings: free)
        let b = Backtester(history: h).run(trigger, days: 0..<h.count)
        XCTAssertLessThan(b.metrics.totalReturn, a.metrics.totalReturn)
    }

    func testMaxDrawdownAndExposure() {
        let m = Backtester.metrics(equity: [120, 90, 95], trades: [], daysIn: 2, start: 100)
        XCTAssertEqual(m.maxDrawdown, 0.25, accuracy: 1e-12)     // 120 -> 90
        XCTAssertEqual(m.exposure, 2.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(m.totalReturn, -0.05, accuracy: 1e-12)
    }

    func testBuyAndHoldOnRealDataMatchesThePriceMove() throws {
        let bt = Backtester()
        let a = bt.dayIndex(for: Date(timeIntervalSince1970: 1_483_228_800))   // 2017-01-01
        let b = bt.dayIndex(for: Date(timeIntervalSince1970: 1_514_678_400))   // 2017-12-31
        let r = bt.buyAndHold(days: a..<(b + 1), settings: free)
        let bars = bt.history.bars
        let expected = bars[b].close / bars[a].open - 1
        XCTAssertEqual(r.metrics.totalReturn, expected, accuracy: 1e-9)
        XCTAssertGreaterThan(expected, 10, "2017 was a >1000% year")
    }

    func testCheckingASignalNeverPeeksAhead() {
        // The same strategy on a truncated history must make the same trades
        // up to the truncation point (a lookahead bug would change them).
        let bt = Backtester()
        let s = Strategy.templates[0]
        let full = bt.run(s, days: 1500..<2500)
        let cut = bt.run(s, days: 1500..<2000)
        let early = full.trades.filter { $0.exitDay < 1990 }
        let cutEarly = cut.trades.filter { $0.exitDay < 1990 }
        XCTAssertEqual(early, cutEarly)
    }

    func testConditionSummariesAreReadable() {
        XCTAssertEqual(Condition.rsiBelow(period: 14, level: 30).summary, "RSI(14) is below 30")
        XCTAssertEqual(Condition.dropFromHigh(days: 30, percent: 15).summary, "Price is 15% below its 30-day high")
    }

    func testStrategiesAreCodable() throws {
        let s = Strategy.templates[0]
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(Strategy.self, from: data), s)
    }
}

final class ReplayHelperTests: XCTestCase {
    private func trade(_ id: Int, _ a: Int, _ b: Int, _ r: Double = 5) -> Trade {
        Trade(id: id, entryDay: a, exitDay: b, entryPrice: 100, exitPrice: 105, returnPercent: r, reason: .signal)
    }
    private func result(_ t: [Trade]) -> BacktestResult {
        BacktestResult(days: 10..<40, equity: Array(repeating: 100, count: 30), trades: t,
                       metrics: Backtester.metrics(equity: [100], trades: t, daysIn: 1, start: 100))
    }

    func testHoldingBetweenEntryAndExit() {
        let r = result([trade(0, 12, 20), trade(1, 25, 30)])
        XCTAssertNil(r.holding(atCloseOf: 11))
        XCTAssertEqual(r.holding(atCloseOf: 12)?.id, 0)    // bought at that day's open
        XCTAssertEqual(r.holding(atCloseOf: 19)?.id, 0)
        XCTAssertNil(r.holding(atCloseOf: 20))             // sold during the 20th
        XCTAssertEqual(r.holding(atCloseOf: 27)?.id, 1)
    }

    func testClosedTradesAccumulate() {
        let r = result([trade(0, 12, 20), trade(1, 25, 30)])
        XCTAssertEqual(r.closedTrades(through: 19).count, 0)
        XCTAssertEqual(r.closedTrades(through: 20).map(\.id), [0])
        XCTAssertEqual(r.closedTrades(through: 35).map(\.id), [0, 1])
    }

    func testLatestEventIsTheRightOne() throws {
        let r = result([trade(0, 12, 20), trade(1, 25, 30)])
        XCTAssertNil(r.latestEvent(through: 11))
        var e = try XCTUnwrap(r.latestEvent(through: 15))
        XCTAssertEqual(e.trade.id, 0); XCTAssertFalse(e.isExit)
        e = try XCTUnwrap(r.latestEvent(through: 22))
        XCTAssertEqual(e.trade.id, 0); XCTAssertTrue(e.isExit)
        e = try XCTUnwrap(r.latestEvent(through: 26))
        XCTAssertEqual(e.trade.id, 1); XCTAssertFalse(e.isExit)
    }

    func testEquityLookupUsesAbsoluteDays() {
        let r = result([])
        XCTAssertEqual(r.equity(atDay: 10), 100)
        XCTAssertNil(r.equity(atDay: 9))
        XCTAssertNil(r.equity(atDay: 40))
    }
}
