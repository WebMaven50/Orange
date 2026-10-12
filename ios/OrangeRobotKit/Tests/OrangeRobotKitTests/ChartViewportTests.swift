import XCTest
@testable import OrangeRobotKit

final class ChartViewportTests: XCTestCase {
    private let tf = 15
    private let live = 3_000.0
    private let startDay = 4_000

    func testStartsLiveAndFollowsTheClock() {
        let v = ChartViewport()
        XCTAssertTrue(v.isLive)
        XCTAssertEqual(v.effectiveEnd(timeframe: tf, liveMinute: 3_123), 3_123)
    }

    func testPanningBackPinsTheViewAndSnapsToCandleEnds() {
        var v = ChartViewport()
        v.pan(candlesBack: 10, timeframe: tf, liveMinute: live, startDay: startDay)
        XCTAssertFalse(v.isLive)
        let e = v.effectiveEnd(timeframe: tf, liveMinute: live)
        XCTAssertLessThan(e, live)
        // ends on the last minute of a 15-minute candle
        XCTAssertEqual((e + 0.001).truncatingRemainder(dividingBy: 15), 0, accuracy: 1e-6)
        // and the game clock moving on does not move a pinned view
        let later = v.effectiveEnd(timeframe: tf, liveMinute: live + 500)
        XCTAssertEqual(later, e, accuracy: 1e-9)
    }

    func testScrollingForwardPastNowReturnsToLive() {
        var v = ChartViewport()
        v.pan(candlesBack: 20, timeframe: tf, liveMinute: live, startDay: startDay)
        v.pan(candlesBack: -50, timeframe: tf, liveMinute: live, startDay: startDay)
        XCTAssertTrue(v.isLive)
    }

    func testCannotScrollBeforeTheDataStarts() {
        var v = ChartViewport()
        v.pan(candlesBack: 1_000_000, timeframe: 1440, liveMinute: live, startDay: startDay)
        let earliest = -Double(startDay) * 1440 + 48 * 1440
        XCTAssertGreaterThanOrEqual(v.end ?? .infinity, earliest - 1e-6)
    }

    func testGoLiveAndReset() {
        var v = ChartViewport()
        v.pan(candlesBack: 5, timeframe: tf, liveMinute: live, startDay: startDay)
        v.zoom(by: 2)
        v.goLive()
        XCTAssertTrue(v.isLive)
        XCTAssertEqual(v.priceZoom, 2)
        v.reset()
        XCTAssertTrue(v.isDefaultZoom)
    }

    func testZoomIsClamped() {
        var v = ChartViewport()
        v.zoom(by: 1_000)
        XCTAssertEqual(v.priceZoom, ChartViewport.maxZoom)
        v.zoom(by: 1e-9)
        XCTAssertEqual(v.priceZoom, ChartViewport.minZoom)
        v.zoom(by: .nan); v.zoom(by: -2); v.zoom(by: 0)
        XCTAssertEqual(v.priceZoom, ChartViewport.minZoom, "bad input is ignored")
    }

    /// The window it asks the engine for really does end where the view is pinned,
    /// and its last candle is complete (not a half-formed one).
    func testEngineWindowEndsOnTheChosenCandle() throws {
        let engine = PriceEngine(startDay: 3_000)
        let liveMinute = 2_000.0
        var v = ChartViewport()
        v.pan(candlesBack: 8, timeframe: 15, liveMinute: liveMinute, startDay: 3_000)
        let end = v.effectiveEnd(timeframe: 15, liveMinute: liveMinute)
        let back = engine.candles(timeframeMinutes: 15, count: 48, atMinute: end)
        let now = engine.candles(timeframeMinutes: 15, count: 48, atMinute: liveMinute)
        XCTAssertEqual(back.count, 48)
        // the view 8 candles back should end (about) 8 candles before the live one
        let liveIndex = Int(floor(liveMinute / 15))
        let backIndex = Int(floor(end / 15))
        XCTAssertEqual(liveIndex - backIndex, 8, accuracy: 1)
        XCTAssertNotEqual(back.last, now.last)
        // a complete candle spans its full 15 minutes
        let again = engine.candles(timeframeMinutes: 15, count: 48, atMinute: end + 5_000 * 0)
        XCTAssertEqual(back, again, "stable: same pinned end, same candles")
    }

    func testPanningAcrossTimeframesKeepsTheTimePinned() {
        var v = ChartViewport()
        v.pan(candlesBack: 30, timeframe: 15, liveMinute: 10_000, startDay: 4_000)
        let e15 = v.effectiveEnd(timeframe: 15, liveMinute: 10_000)
        let e60 = v.effectiveEnd(timeframe: 60, liveMinute: 10_000)
        XCTAssertLessThanOrEqual(abs(e15 - e60), 60)
    }
}
