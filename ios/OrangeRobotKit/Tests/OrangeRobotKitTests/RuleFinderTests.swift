import XCTest
@testable import OrangeRobotKit

final class RuleFinderTests: XCTestCase {
    private func request(_ a: Int, _ b: Int, n: Int = 120) -> FinderRequest {
        var r = FinderRequest(trainDays: a..<b); r.candidates = n; r.keep = 5; return r
    }

    func testFindsRulesAndReportsThemSortedByTrainingScore() {
        let found = RuleFinder().find(request(2500, 3000))
        XCTAssertFalse(found.isEmpty)
        XCTAssertLessThanOrEqual(found.count, 5)
        func fit(_ c: Candidate) -> Double { c.train.totalReturn - 0.5 * c.train.maxDrawdown }
        for (a, b) in zip(found, found.dropFirst()) { XCTAssertGreaterThanOrEqual(fit(a), fit(b)) }
        for c in found { XCTAssertGreaterThanOrEqual(c.train.trades, 3) }
    }

    func testSameRequestGivesTheSameAnswer() {
        let a = RuleFinder().find(request(2500, 3000)).map(\.strategy)
        let b = RuleFinder().find(request(2500, 3000)).map(\.strategy)
        XCTAssertEqual(a, b)
    }

    func testValidationPeriodsAreNeverTheTrainingPeriod() {
        let found = RuleFinder().find(request(2500, 3000))
        for c in found {
            let v = try? XCTUnwrap(c.validationDays)
            if let v { XCTAssertTrue(v.upperBound <= 2500 || v.lowerBound >= 3000) }
        }
    }

    func testOtherWindowsDontOverlapTraining() {
        let train = 2500..<3000
        let w = RuleFinder.otherWindows(length: 500, avoiding: train, total: 5176, count: 6)
        XCTAssertFalse(w.isEmpty)
        for r in w {
            XCTAssertEqual(r.count, 500)
            XCTAssertTrue(r.upperBound <= train.lowerBound || r.lowerBound >= train.upperBound)
        }
    }

    func testValidationRangePrefersTheFutureThenThePast() {
        XCTAssertEqual(RuleFinder.validationRange(after: 1000..<1400, total: 5000), 1400..<1765)
        XCTAssertEqual(RuleFinder.validationRange(after: 4700..<5100, total: 5176), 4335..<4700)
        XCTAssertNil(RuleFinder.validationRange(after: 0..<5176, total: 5176))
    }

    func testTooShortAPeriodReturnsNothing() {
        XCTAssertTrue(RuleFinder().find(request(2500, 2530)).isEmpty)
    }

    func testCancelStopsTheSearch() {
        var calls = 0
        let found = RuleFinder().find(request(2500, 3000, n: 5000), isCancelled: { calls += 1; return calls > 3 })
        XCTAssertLessThan(calls, 50)
        _ = found
    }

    func testVerdictRules() {
        func m(_ r: Double, dd: Double = 0.2) -> Metrics {
            Metrics(totalReturn: r, annualizedReturn: r, maxDrawdown: dd, winRate: 0.5, trades: 5, exposure: 0.5, sharpe: 1)
        }
        func rob(pos: Double, beats: Double) -> Robustness {
            Robustness(windows: 6, medianReturn: 0.1, positiveShare: pos, beatsHoldShare: beats)
        }
        // makes money AND beats holding in most periods
        XCTAssertEqual(RuleFinder.verdict(validation: m(0.3), validationHold: m(0.1), robustness: rob(pos: 0.8, beats: 0.67)), .holdsUp)
        // makes money, but holding made more; smaller drawdown -> smoother ride
        XCTAssertEqual(RuleFinder.verdict(validation: m(0.3, dd: 0.1), validationHold: m(1.5, dd: 0.4),
                                          robustness: rob(pos: 0.8, beats: 0.1)), .steadier)
        // makes money, holding made more, and it was no smoother -> just mixed
        XCTAssertEqual(RuleFinder.verdict(validation: m(0.3, dd: 0.5), validationHold: m(1.5, dd: 0.3),
                                          robustness: rob(pos: 0.8, beats: 0.1)), .mixed)
        // losing money next period and in most other periods
        XCTAssertEqual(RuleFinder.verdict(validation: m(-0.2), validationHold: m(0.5), robustness: rob(pos: 0.1, beats: 0)), .fellApart)
        // profitable next period but mostly unprofitable elsewhere
        XCTAssertEqual(RuleFinder.verdict(validation: m(0.3), validationHold: m(0.1), robustness: rob(pos: 0.2, beats: 0.2)), .mixed)
    }

    func testGeneratedRulesAreSane() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<500 {
            let s = RuleGenerator.random(using: &rng)
            XCTAssertFalse(s.entry.isEmpty)
            XCTAssertTrue((1...100).contains(s.positionPercent))
            for c in s.entry + s.exit {
                if case let .maAbove(f, sl) = c { XCTAssertLessThan(f, sl) }
                if case let .maBelow(f, sl) = c { XCTAssertLessThan(f, sl) }
            }
            XCTAssertTrue(!s.exit.isEmpty || s.stopLossPercent != nil || s.takeProfitPercent != nil
                          || s.trailingStopPercent != nil)
        }
    }
}
