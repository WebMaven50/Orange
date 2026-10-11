import XCTest
@testable import OrangeRobotKit

final class ReportTests: XCTestCase {
    private func metrics(_ r: Double) -> Metrics {
        Metrics(totalReturn: r, annualizedReturn: r, maxDrawdown: 0.2, winRate: 0.5, trades: 4, exposure: 0.4, sharpe: 1)
    }
    private func test(_ name: String = "Dip buyer", at t: Double = 0, start: Double = 1_000, ret: Double = 0.3) -> Report {
        var s = Strategy.templates[0]; s.name = name
        return Report.test(strategy: s, start: Date(timeIntervalSince1970: start),
                           end: Date(timeIntervalSince1970: start + 86_400 * 365),
                           result: metrics(ret), hold: metrics(1.0), now: Date(timeIntervalSince1970: t))
    }

    func testReportRoundTripsThroughJSON() throws {
        let r = test()
        let data = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(Report.self, from: data), r)
    }

    func testBookRoundTrips() throws {
        var b = ReportBook(); b.add(test()); b.add(test("Other", at: 500))
        let data = try JSONEncoder().encode(b)
        XCTAssertEqual(try JSONDecoder().decode(ReportBook.self, from: data), b)
    }

    func testNewestFirst() {
        var b = ReportBook()
        b.add(test("First", at: 0)); b.add(test("Second", at: 100))
        XCTAssertEqual(b.reports.map(\.title), ["Second", "First"])
    }

    func testReopeningTheSameResultDoesNotDuplicate() {
        var b = ReportBook()
        XCTAssertTrue(b.add(test(at: 0)))
        XCTAssertFalse(b.add(test(at: 20)), "same rules, same period, seconds apart")
        XCTAssertTrue(b.add(test(at: 500)), "a later run is a new entry")
        XCTAssertTrue(b.add(test(at: 505, start: 2_000)), "a different period is a new entry")
        XCTAssertEqual(b.reports.count, 3)
    }

    func testNotesStarDeleteAndTitle() {
        var b = ReportBook(); let r = test(); b.add(r)
        b.setNotes(r.id, "Tried tightening the stop; worse in 2018.")
        b.toggleStar(r.id)
        b.setTitle(r.id, "Dip v2")
        let got = b.report(r.id)!
        XCTAssertEqual(got.notes, "Tried tightening the stop; worse in 2018.")
        XCTAssertTrue(got.starred)
        XCTAssertEqual(got.title, "Dip v2")
        b.delete(r.id)
        XCTAssertNil(b.report(r.id))
    }

    func testFilterAndSearch() {
        var b = ReportBook()
        let a = test("Dip buyer", at: 0); let c = test("Trend", at: 100, start: 5_000)
        b.add(a); b.add(c)
        b.toggleStar(a.id)
        XCTAssertEqual(b.filtered(.starred).map(\.title), ["Dip buyer"])
        XCTAssertEqual(b.filtered(.searches).count, 0)
        XCTAssertEqual(b.filtered(.all, query: "trend").map(\.title), ["Trend"])
        b.setNotes(c.id, "worked in a bear market")
        XCTAssertEqual(b.filtered(.all, query: "bear").map(\.title), ["Trend"])
    }

    func testCapacityDropsOldestButKeepsStarred() {
        var b = ReportBook()
        let keeper = test("Keeper", at: 0, start: 1)
        b.add(keeper); b.toggleStar(keeper.id)
        for i in 1...ReportBook.capacity + 5 { b.add(test("t\(i)", at: Double(i) * 100, start: Double(i) + 10)) }
        XCTAssertEqual(b.reports.count, ReportBook.capacity)
        XCTAssertNotNil(b.report(keeper.id), "starred reports are never dropped")
    }

    func testTextSummaryIncludesRulesResultAndNotes() {
        var r = test("Dip buyer")
        r.notes = "Only 4 trades, so treat with care."
        let s = r.textSummary
        XCTAssertTrue(s.contains("Dip buyer"))
        XCTAssertTrue(s.contains("Buy when"))
        XCTAssertTrue(s.contains("Just holding"))
        XCTAssertTrue(s.contains("Only 4 trades"))
        XCTAssertTrue(s.contains("Not financial advice"))
    }

    func testSearchReportCapturesVerdicts() {
        let bt = Backtester()
        var req = FinderRequest(trainDays: 2500..<3000); req.candidates = 150; req.keep = 4
        let found = RuleFinder(backtester: bt).find(req)
        let rep = Report.search(start: bt.date(forDay: 2500), end: bt.date(forDay: 3000), tries: 150, candidates: found)
        XCTAssertEqual(rep.kind, .search)
        XCTAssertEqual(rep.found.count, found.count)
        XCTAssertEqual(rep.found.map(\.verdict), found.map(\.verdict))
        XCTAssertFalse(rep.headline.isEmpty)
        XCTAssertTrue(rep.textSummary.contains("Ideas tried: 150"))
    }
}
