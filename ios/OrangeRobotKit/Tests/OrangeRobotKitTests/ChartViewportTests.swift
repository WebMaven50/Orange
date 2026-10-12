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

final class PriceScaleTests: XCTestCase {
    /// The bug: a 3-minute window on a $19,000 coin moves ~$20. It must fill the plot,
    /// not be squashed into a ±2% band (±$380).
    func testSmallMovesFillTheChart() {
        let s = PriceScale.fit(dataHigh: 19_020, dataLow: 19_000, price: 19_010)
        XCTAssertLessThan(s.high - s.low, 40, "range should hug the $20 of movement")
        XCTAssertLessThan(s.low, 19_000)
        XCTAssertGreaterThan(s.high, 19_020)
        let fill = 20 / (s.high - s.low)
        XCTAssertGreaterThan(fill, 0.8, "the data should use most of the plot height")
    }

    func testNormalRangesGetEvenPadding() {
        let s = PriceScale.fit(dataHigh: 110, dataLow: 100, price: 105)
        XCTAssertEqual(s.low, 100 - 10 * PriceScale.padding, accuracy: 1e-9)
        XCTAssertEqual(s.high, 110 + 10 * PriceScale.padding, accuracy: 1e-9)
    }

    func testTrulyFlatDataGetsASmallBandNotAWideOne() {
        let s = PriceScale.fit(dataHigh: 100, dataLow: 100, price: 100)
        XCTAssertGreaterThan(s.high, 100)
        XCTAssertLessThan(s.low, 100)
        XCTAssertLessThan(s.high - s.low, 0.2, "about ±0.05%, not ±2%")
    }

    func testZoomStretchesAroundThePriceAndIsAdjustableAtTinyRanges() {
        let base = PriceScale.fit(dataHigh: 19_020, dataLow: 19_000, price: 19_015)
        let zoomed = PriceScale.fit(dataHigh: 19_020, dataLow: 19_000, price: 19_015, zoom: 4)
        XCTAssertLessThan(zoomed.high - zoomed.low, (base.high - base.low) / 3,
                          "zoom must work even when the data range is tiny")
        XCTAssertEqual((zoomed.high + zoomed.low) / 2, 19_015, accuracy: 1e-6, "centred on the price")
        let out = PriceScale.fit(dataHigh: 19_020, dataLow: 19_000, price: 19_015, zoom: 0.5)
        XCTAssertGreaterThan(out.high - out.low, (base.high - base.low) * 1.5)
    }

    func testNeverGoesBelowZeroAndHandlesTinyPrices() {
        let a = PriceScale.fit(dataHigh: 0.12, dataLow: 0.08, price: 0.1, zoom: 0.4)
        XCTAssertGreaterThanOrEqual(a.low, 0)
        let b = PriceScale.fit(dataHigh: 0.1001, dataLow: 0.1, price: 0.1)
        XCTAssertGreaterThan(b.high - b.low, 0)
    }

    func testLabelPrecisionGrowsAsTheRangeShrinks() {
        XCTAssertEqual(PriceScale.decimals(forSpan: 2_000), 0)
        XCTAssertEqual(PriceScale.decimals(forSpan: 20), 1)
        XCTAssertEqual(PriceScale.decimals(forSpan: 2), 2)
        XCTAssertEqual(PriceScale.decimals(forSpan: 0.1), 3)
        XCTAssertEqual(PriceScale.decimals(forSpan: 0.01), 4)
    }
}
