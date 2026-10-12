import XCTest
@testable import OrangeRobotKit

final class RealTimeTests: XCTestCase {
    /// A run that starts `minutesBeforeEnd` before the last day of real history ends.
    private func nearEnd(minutesBeforeEnd: Double = 0.5) -> GameSession {
        let engine = PriceEngine(startDay: PriceHistory.bundled.count - 2)
        return GameSession(engine: engine, startMinute: 2 * 1440 - minutesBeforeEnd, isRandomStart: false)
    }

    private func crossTheEnd(_ s: inout GameSession) {
        for _ in 0..<40 { s.advance(seconds: 0.05) }   // 2 real seconds at 240x: well past the end
    }

    func testClockSwitchesToRealTimeAtTheEndOfTheData() {
        var s = nearEnd()
        XCTAssertFalse(s.isLive)
        XCTAssertEqual(s.dataEndMinute, 2 * 1440, accuracy: 1e-9)
        crossTheEnd(&s)
        XCTAssertTrue(s.isLive)
        XCTAssertGreaterThan(s.absMinute, 2 * 1440)
    }

    func testAfterTheEndTheClockRunsAtActualSpeed() {
        var s = nearEnd()
        crossTheEnd(&s)
        let start = s.absMinute
        for _ in 0..<1200 { s.advance(seconds: 0.05) }   // 60 real seconds
        XCTAssertEqual(s.absMinute - start, 1.0, accuracy: 0.01)
    }

    func testNoSkippingOrSleepingIntoTheFuture() {
        var s = nearEnd()
        crossTheEnd(&s)
        XCTAssertFalse(s.skipDays(1))
        XCTAssertFalse(s.startSleep())
    }

    func testLivePricesDriveThePriceAndTheChart() {
        var s = nearEnd()
        crossTheEnd(&s)
        XCTAssertTrue(s.recordLivePrice(64_250))
        s.advance(seconds: 0.05)
        XCTAssertEqual(s.lastPrice, 64_250, accuracy: 1e-9)
        let c = s.candles(timeframeMinutes: 15, count: 3, atMinute: s.absMinute)
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c.last?.close ?? 0, 64_250, accuracy: 1e-9)
    }

    func testLiveCandlesCarryTheLastPriceAcrossQuietTime() {
        var s = nearEnd()
        crossTheEnd(&s)
        s.recordLivePrice(60_000)
        for _ in 0..<1200 { s.advance(seconds: 0.05) }   // a minute of real time, no new prices
        let c = s.candles(timeframeMinutes: 15, count: 4, atMinute: s.absMinute)
        XCTAssertEqual(c.last?.close ?? 0, 60_000, accuracy: 1e-9)
        XCTAssertEqual(c.last?.high ?? 0, 60_000, accuracy: 1e-9, "flat carry, no invented wicks")
    }

    func testADaySkipStopsAtTheNewestDataInsteadOfJumpingPast() {
        var s = nearEnd(minutesBeforeEnd: 600)     // ten hours of real data left
        XCTAssertTrue(s.skipDays(1))
        XCTAssertTrue(s.isLive)
        XCTAssertEqual(s.absMinute, s.dataEndMinute, accuracy: 10)
    }

    func testRecordingIsIgnoredBeforeTheEnd() {
        var s = nearEnd(minutesBeforeEnd: 600)
        XCTAssertFalse(s.recordLivePrice(1))
    }

    func testRealTimeSurvivesASnapshot() throws {
        var s = nearEnd()
        crossTheEnd(&s)
        s.recordLivePrice(70_000)
        let snap = try XCTUnwrap(s.snapshot())
        let back = try XCTUnwrap(GameSession(snapshot: snap))
        XCTAssertTrue(back.isLive)
        XCTAssertEqual(back.lastPrice, 70_000, accuracy: 1e-9)
        XCTAssertEqual(back.liveTape.count, 1)
    }

    func testLiveTickerParsers() throws {
        let kraken = Data(#"{"error":[],"result":{"XXBTZUSD":{"c":["64123.40","0.01"]}}}"#.utf8)
        XCTAssertEqual(try LivePrice.parseKrakenTicker(kraken), 64_123.40, accuracy: 1e-9)
        let coinbase = Data(#"{"price":"64050.12","size":"0.1"}"#.utf8)
        XCTAssertEqual(try LivePrice.parseCoinbaseTicker(coinbase), 64_050.12, accuracy: 1e-9)
        XCTAssertThrowsError(try LivePrice.parseKrakenTicker(Data("{}".utf8)))
    }
}
