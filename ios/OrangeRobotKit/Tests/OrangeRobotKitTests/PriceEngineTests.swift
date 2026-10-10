import XCTest
@testable import OrangeRobotKit

private struct Golden: Decodable {
    struct P: Decodable { let startDay: Int; let minute: Double; let price: Double }
    struct C: Decodable {
        struct K: Decodable { let o, h, l, c: Double }
        let startDay: Int; let absMinute: Double; let tf: Int; let count: Int; let candles: [K]
    }
    let prices: [P]
    let candles: [C]
}

final class PriceEngineTests: XCTestCase {
    private func golden() throws -> Golden {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "golden", withExtension: "json"))
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    func testHistoryLoads() {
        let h = PriceHistory.bundled
        XCTAssertEqual(h.count, 5176)
        XCTAssertEqual(h.bars.last?.close, 60309.1)
    }

    /// The Swift port must reproduce the web game's prices exactly.
    func testPricesMatchWebGame() throws {
        for g in try golden().prices {
            let e = PriceEngine(startDay: g.startDay)
            XCTAssertEqual(e.price(atMinute: g.minute), g.price, accuracy: 1e-6,
                           "startDay \(g.startDay) minute \(g.minute)")
        }
    }

    /// The web game only showed candles from the run's start onward. The Swift
    /// port also shows real history before the start, so the web game's candles
    /// must appear unchanged as the *tail* of what we return.
    func testCandlesMatchWebGame() throws {
        for g in try golden().candles {
            let e = PriceEngine(startDay: g.startDay)
            let got = e.candles(timeframeMinutes: g.tf, count: g.count, atMinute: g.absMinute)
            XCTAssertGreaterThanOrEqual(got.count, g.candles.count, "tf \(g.tf)")
            for (a, b) in zip(got.suffix(g.candles.count), g.candles) {
                XCTAssertEqual(a.open, b.o, accuracy: 1e-6)
                XCTAssertEqual(a.high, b.h, accuracy: 1e-6)
                XCTAssertEqual(a.low, b.l, accuracy: 1e-6)
                XCTAssertEqual(a.close, b.c, accuracy: 1e-6)
            }
        }
    }

    func testChartIsFullFromTheFirstSecond() {
        let e = PriceEngine(startDay: 3000)
        for tf in [3, 15, 60, 240, 1440, 10080] {
            let c = e.candles(timeframeMinutes: tf, count: 48, atMinute: 500)
            XCTAssertEqual(c.count, 48, "tf \(tf) should have a full chart at the start of a run")
            XCTAssertTrue(c.allSatisfy { $0.low <= $0.high && $0.low > 0 })
        }
    }

    func testHistoryNeverReachesBeforeTheDataset() {
        let e = PriceEngine(startDay: 2) // two days of data exist before the start
        let c = e.candles(timeframeMinutes: 1440, count: 48, atMinute: 500)
        XCTAssertEqual(c.count, 3, "days -2, -1 and today only")
        let h = e.candles(timeframeMinutes: 15, count: 500, atMinute: 500)
        XCTAssertEqual(h.count, 2 * 96 + 500 / 15 + 1)
    }

    func testDailyCandleIsRealAtDayEnd() {
        let e = PriceEngine(startDay: 3000)
        let bar = e.history.bar(at: 3000)
        // Just before midnight the forming candle must close at the real close.
        let c = e.candles(timeframeMinutes: 1440, count: 1, atMinute: 1439.999).last!
        XCTAssertEqual(c.open, bar.open)
        XCTAssertEqual(c.close, bar.close, accuracy: 0.01)
    }

    func testDateOffset() {
        let e = PriceEngine(startDay: 0)
        let d = e.date(forDayOffset: 0)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        XCTAssertEqual([c.year, c.month, c.day], [2010, 7, 18])
    }
}
