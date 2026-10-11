import XCTest
@testable import OrangeRobotKit

final class AnalysisTests: XCTestCase {
    private typealias B = (o: Double, h: Double, l: Double, c: Double)
    private func history(_ bars: [B]) -> PriceHistory {
        PriceHistory(startDate: Date(timeIntervalSince1970: 1_600_000_000),
                     bars: bars.map { DayBar(open: $0.o, high: $0.h, low: $0.l, close: $0.c) })
    }
    private func flat(_ p: Double, _ n: Int) -> [B] { Array(repeating: (p, p, p, p), count: n) }
    private var free: BacktestSettings { var s = BacktestSettings(); s.fee = 0; s.slippage = 0; return s }

    // MARK: Score

    func testScoreDefinition() {
        XCTAssertEqual(Score.vsHold(robotReturn: 0.5, holdReturn: 0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(Score.vsHold(robotReturn: 1.0, holdReturn: 0.0), 100, accuracy: 1e-9)   // doubled the money
        XCTAssertEqual(Score.vsHold(robotReturn: 0.0, holdReturn: 1.0), -50, accuracy: 1e-9)   // half the money
        XCTAssertEqual(Score.vsHold(robotReturn: 0.2, holdReturn: -0.2), 50, accuracy: 1e-9)   // 1.2 vs 0.8
        XCTAssertEqual(Score.label(-50), "−50")
        XCTAssertEqual(Score.label(100), "+100")
    }

    // MARK: New conditions

    func testNewConditionSummaries() {
        XCTAssertEqual(Condition.priceAbove(price: 60_000).summary, "Price is at or above $60,000")
        XCTAssertEqual(Condition.upPercent(days: 7, percent: 10).summary, "Price is up 10% or more over 7 days")
        XCTAssertEqual(Condition.percentBelowMA(period: 50, percent: 5).summary, "Price is 5% or more below its 50-day average")
        XCTAssertEqual(Condition.riseFromLow(days: 30, percent: 20).summary, "Price is 20% or more above its 30-day low")
    }

    func testPercentConditionsEvaluate() {
        // 10 flat days at 100, then 120
        let h = history(flat(100, 10) + [(120, 120, 120, 120)])
        let bt = Backtester(history: h)
        XCTAssertTrue(bt.isTrue(.upPercent(days: 3, percent: 15), at: 10))
        XCTAssertFalse(bt.isTrue(.upPercent(days: 3, percent: 25), at: 10))
        XCTAssertTrue(bt.isTrue(.priceAbove(price: 110), at: 10))
        XCTAssertFalse(bt.isTrue(.priceAbove(price: 110), at: 9))
        XCTAssertTrue(bt.isTrue(.priceBelow(price: 110), at: 9))
        XCTAssertTrue(bt.isTrue(.percentAboveMA(period: 5, percent: 10), at: 10))   // 120 vs avg 104
        XCTAssertTrue(bt.isTrue(.riseFromLow(days: 5, percent: 20), at: 10))
        XCTAssertFalse(bt.isTrue(.downPercent(days: 3, percent: 5), at: 10))
    }

    func testRobotCanBuyOnAPercentRise() throws {
        let h = history(flat(100, 10) + [(100, 125, 100, 125)] + flat(125, 4))
        var s = Strategy(name: "Momentum", entry: [.upPercent(days: 1, percent: 20)], positionPercent: 100)
        s.maxHoldDays = 2
        let r = Backtester(history: h).run(s, days: 0..<h.count, settings: free)
        XCTAssertEqual(r.trades.count, 1)
    }

    // MARK: DCA

    func testDCABuysOnAScheduleAndSpreadsTheMoney() throws {
        let h = history(flat(100, 28))
        let s = Strategy(name: "DCA", dca: DCAPlan(intervalDays: 7))
        let r = Backtester(history: h).run(s, days: 0..<28, settings: free)
        XCTAssertEqual(r.purchases.count, 4)
        XCTAssertEqual(r.purchases.map(\.day), [0, 7, 14, 21])
        XCTAssertEqual(r.purchases.map(\.amount).reduce(0, +), 100_000, accuracy: 1e-6)
        XCTAssertEqual(r.metrics.totalReturn, 0, accuracy: 1e-9)       // flat price, no costs
    }

    func testDCAInARisingMarketTrailsLumpSumHolding() throws {
        var bars: [B] = []
        for i in 0..<60 { let p = 100.0 + Double(i); bars.append((p, p, p, p)) }
        let h = history(bars)
        let bt = Backtester(history: h)
        let dca = bt.run(Strategy(name: "DCA", dca: DCAPlan(intervalDays: 7)), days: 0..<60, settings: free)
        let hold = bt.buyAndHold(days: 0..<60, settings: free)
        XCTAssertLessThan(dca.metrics.totalReturn, hold.metrics.totalReturn)
        XCTAssertGreaterThan(dca.metrics.totalReturn, 0)
    }

    func testDCAInAFallingMarketBeatsLumpSumHolding() throws {
        var bars: [B] = []
        for i in 0..<60 { let p = 200.0 - Double(i); bars.append((p, p, p, p)) }
        let h = history(bars)
        let bt = Backtester(history: h)
        let dca = bt.run(Strategy(name: "DCA", dca: DCAPlan(intervalDays: 7)), days: 0..<60, settings: free)
        let hold = bt.buyAndHold(days: 0..<60, settings: free)
        XCTAssertGreaterThan(dca.metrics.totalReturn, hold.metrics.totalReturn)
    }

    func testDCACostsFeesOnEveryBuy() throws {
        let h = history(flat(100, 28))
        let s = Strategy(name: "DCA", dca: DCAPlan(intervalDays: 7))
        let r = Backtester(history: h).run(s, days: 0..<28)   // default fee + slippage
        XCTAssertLessThan(r.metrics.totalReturn, 0)
    }

    func testStrategyWithoutDCAFieldStillDecodes() throws {
        let s = Strategy.templates[0]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        json.removeValue(forKey: "dca")
        let back = try JSONDecoder().decode(Strategy.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.dca)
        XCTAssertEqual(back.name, s.name)
    }

    // MARK: Analyzer

    private func analyze(_ s: Strategy, _ bars: [B]) -> (Analysis, BacktestResult, BacktestResult) {
        let h = history(bars)
        let bt = Backtester(history: h)
        let r = bt.run(s, days: 0..<h.count, settings: free)
        let hold = bt.buyAndHold(days: 0..<h.count, settings: free)
        return (Analyzer.analyze(strategy: s, result: r, hold: hold, history: h, settings: free), r, hold)
    }

    func testReportsAMissedRallyWhenTheRobotStaysInCash() {
        // Flat, then a long rally the robot's impossible condition never catches
        var bars = flat(100, 10)
        for i in 1...40 { let p = 100.0 + Double(i) * 3; bars.append((p - 1, p + 1, p - 2, p)) }
        let s = Strategy(name: "Never", entry: [.priceAbove(price: 1_000_000)], positionPercent: 100)
        let (a, _, _) = analyze(s, bars)
        XCTAssertLessThan(a.score, -50)
        XCTAssertTrue(a.findings.contains { $0.kind == .wrong && $0.title.contains("Missed a rise") })
        XCTAssertTrue(a.findings.contains { $0.title.contains("never traded") })
    }

    func testReportsADodgedFall() {
        var bars = flat(100, 10)
        for i in 1...30 { let p = 100.0 - Double(i) * 1.5; bars.append((p + 1, p + 2, p - 1, p)) }
        let s = Strategy(name: "Never", entry: [.priceAbove(price: 1_000_000)], positionPercent: 100)
        let (a, _, _) = analyze(s, bars)
        XCTAssertGreaterThan(a.score, 20)
        XCTAssertTrue(a.findings.contains { $0.kind == .right && $0.title.contains("Dodged a fall") })
    }

    func testFlagsAStopThatWasFollowedByARecovery() {
        // up, sharp one-day dip that trips a 10% stop, then recovery
        var bars = flat(100, 8)
        bars += [(100, 112, 100, 112)]                    // signal day (>5% up)
        bars += [(112, 112, 112, 112)]                    // buy at open
        bars += [(112, 112, 95, 100)]                     // wick through the stop
        for _ in 0..<12 { bars.append((115, 120, 114, 118)) }
        var s = Strategy(name: "Mom", entry: [.upPercent(days: 1, percent: 5)], positionPercent: 100)
        s.stopLossPercent = 10
        let (a, r, _) = analyze(s, bars)
        XCTAssertEqual(r.trades.first?.reason, .stopLoss)
        XCTAssertTrue(a.findings.contains { $0.kind == .wrong && $0.title.contains("Stopped out") })
        XCTAssertTrue(a.suggestions.contains { $0.contains("wider stop") })
    }

    func testDCAAnalysisExplainsAveragingIn() {
        var bars: [B] = []
        for i in 0..<60 { let p = 200.0 - Double(i); bars.append((p, p, p, p)) }
        let (a, _, _) = analyze(Strategy(name: "DCA", dca: DCAPlan(intervalDays: 7)), bars)
        XCTAssertGreaterThan(a.score, 0)
        XCTAssertTrue(a.findings.contains { $0.kind == .right })
    }

    func testHeadlineMatchesTheScoreSign() {
        var bars = flat(100, 10)
        for i in 1...20 { let p = 100.0 + Double(i); bars.append((p, p, p, p)) }
        let (a, _, _) = analyze(Strategy(name: "Never", entry: [.priceAbove(price: 9e9)]), bars)
        XCTAssertTrue(a.headline.contains("less money"))
    }
}

final class DCAContributionTests: XCTestCase {
    private func history(_ n: Int, price: Double = 100) -> PriceHistory {
        PriceHistory(startDate: Date(timeIntervalSince1970: 1_600_000_000),
                     bars: Array(repeating: DayBar(open: price, high: price, low: price, close: price), count: n))
    }
    private var free: BacktestSettings { var s = BacktestSettings(); s.fee = 0; s.slippage = 0; return s }

    func testFixedDollarAmountEachTime() {
        let h = history(28)
        let r = Backtester(history: h).run(Strategy(name: "d", dca: DCAPlan(intervalDays: 7, dollarsPerBuy: 1_000)),
                                           days: 0..<28, settings: free)
        XCTAssertEqual(r.purchases.map(\.amount), [1000, 1000, 1000, 1000])
        XCTAssertEqual(r.metrics.totalReturn, 0, accuracy: 1e-9)       // flat price: idle cash is still counted
    }

    func testPercentOfStartingCash() {
        let h = history(28)
        let r = Backtester(history: h).run(Strategy(name: "d", dca: DCAPlan(intervalDays: 7, percentOfStart: 10)),
                                           days: 0..<28, settings: free)
        XCTAssertEqual(r.purchases.map(\.amount), [10_000, 10_000, 10_000, 10_000])
    }

    func testStopsWhenTheCashRunsOut() {
        let h = history(28)
        let r = Backtester(history: h).run(Strategy(name: "d", dca: DCAPlan(intervalDays: 7, dollarsPerBuy: 40_000)),
                                           days: 0..<28, settings: free)
        XCTAssertEqual(r.purchases.map(\.amount), [40_000, 40_000, 20_000])
    }

    func testEvenSpreadStillSpendsEverything() {
        let h = history(28)
        let r = Backtester(history: h).run(Strategy(name: "d", dca: DCAPlan(intervalDays: 7)), days: 0..<28, settings: free)
        XCTAssertEqual(r.purchases.map(\.amount).reduce(0, +), 100_000, accuracy: 1e-6)
    }

    func testSummaryStatesAmountCountAndTotal() {
        let p = DCAPlan(intervalDays: 7, dollarsPerBuy: 1_000)
        let s = p.summary(startCash: 100_000, days: 365)
        XCTAssertTrue(s.contains("$1,000 every week"))
        XCTAssertTrue(s.contains("53 purchases"))
        XCTAssertTrue(s.contains("$53,000 in total"))
        XCTAssertTrue(s.contains("$47,000 stays in cash"))
        let even = DCAPlan(intervalDays: 30).summary(startCash: 100_000, days: 360)
        XCTAssertTrue(even.contains("12 purchases"))
        XCTAssertFalse(even.contains("stays in cash"))
        XCTAssertTrue(DCAPlan(intervalDays: 7, dollarsPerBuy: 5_000).summary(startCash: 100_000, days: 365).contains("stops when cash runs out"))
    }

    func testAnalysisSaysHowMuchWasPaidAndFlagsIdleCash() {
        let h = history(60)
        let bt = Backtester(history: h)
        let s = Strategy(name: "d", dca: DCAPlan(intervalDays: 7, dollarsPerBuy: 500))
        let r = bt.run(s, days: 0..<60, settings: free)
        let hold = bt.buyAndHold(days: 0..<60, settings: free)
        let a = Analyzer.analyze(strategy: s, result: r, hold: hold, history: h, settings: free)
        XCTAssertTrue(a.findings.contains { $0.detail.contains("$500") })
        XCTAssertTrue(a.findings.contains { $0.title.contains("never went in") })
    }

    func testOldSavedPlansStillDecode() throws {
        let json = #"{"intervalDays":7}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(DCAPlan.self, from: json)
        XCTAssertEqual(p.mode, .evenSpread)
        XCTAssertEqual(p.intervalDays, 7)
    }
}

final class DCAReinvestTests: XCTestCase {
    private func rising(_ n: Int) -> PriceHistory {
        PriceHistory(startDate: Date(timeIntervalSince1970: 1_600_000_000),
                     bars: (0..<n).map { i in
                         let p = 100.0 + Double(i) * 2
                         return DayBar(open: p, high: p, low: p, close: p)
                     })
    }
    private var free: BacktestSettings { var s = BacktestSettings(); s.fee = 0; s.slippage = 0; return s }

    func testFirstBuyHasNoBonusLaterBuysDo() {
        let h = rising(28)
        let plan = DCAPlan(intervalDays: 7, dollarsPerBuy: 1_000, reinvestPercent: 50)
        let r = Backtester(history: h).run(Strategy(name: "d", dca: plan), days: 0..<28, settings: free)
        XCTAssertEqual(r.purchases.count, 4)
        XCTAssertEqual(r.purchases[0].bonus, 0, accuracy: 1e-9)       // no profit yet
        XCTAssertGreaterThan(r.purchases[1].bonus, 0)
        XCTAssertGreaterThan(r.purchases[3].amount, r.purchases[1].amount, "contributions grow with profit")
    }

    func testBonusIsTheChosenShareOfProfit() throws {
        let h = rising(28)
        let plan = DCAPlan(intervalDays: 7, dollarsPerBuy: 1_000, reinvestPercent: 50)
        let r = Backtester(history: h).run(Strategy(name: "d", dca: plan), days: 0..<28, settings: free)
        // Before the 2nd buy (day 7): 10 BTC-equivalents bought at 100 -> shares = 10, price now 114.
        let profit = 10 * (114 - 100)
        XCTAssertEqual(r.purchases[1].bonus, Double(profit) * 0.5, accuracy: 1e-6)
    }

    func testNoProfitMeansNoBonus() {
        let flat = PriceHistory(startDate: Date(timeIntervalSince1970: 1_600_000_000),
                                bars: Array(repeating: DayBar(open: 100, high: 100, low: 100, close: 100), count: 28))
        let plan = DCAPlan(intervalDays: 7, dollarsPerBuy: 1_000, reinvestPercent: 100)
        let r = Backtester(history: flat).run(Strategy(name: "d", dca: plan), days: 0..<28, settings: free)
        XCTAssertEqual(r.purchases.map(\.bonus), [0, 0, 0, 0])
    }

    func testBonusNeverSpendsMoreThanTheCashLeft() {
        let h = rising(28)
        let plan = DCAPlan(intervalDays: 7, dollarsPerBuy: 20_000, reinvestPercent: 100)
        let r = Backtester(history: h).run(Strategy(name: "d", dca: plan), days: 0..<28, settings: free)
        XCTAssertLessThanOrEqual(r.purchases.map(\.amount).reduce(0, +), 100_000 + 1e-6)
    }

    func testOffByDefaultAndOldPlansDecode() throws {
        XCTAssertFalse(DCAPlan().reinvests)
        let json = #"{"intervalDays":7,"dollarsPerBuy":500}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(DCAPlan.self, from: json)
        XCTAssertFalse(p.reinvests)
        XCTAssertEqual(p.dollarsPerBuy, 500)
    }

    func testSummaryMentionsReinvesting() {
        let p = DCAPlan(intervalDays: 7, dollarsPerBuy: 1_000, reinvestPercent: 50)
        XCTAssertTrue(p.summary(startCash: 100_000, days: 365).contains("plus 50% of the profit so far"))
        XCTAssertTrue(p.shortAmountText.contains("+ 50% of profit"))
    }
}
