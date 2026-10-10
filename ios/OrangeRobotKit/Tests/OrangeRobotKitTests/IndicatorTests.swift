import XCTest
@testable import OrangeRobotKit

final class IndicatorTests: XCTestCase {
    /// The classic worked RSI example prices (Wilder smoothing, 14 periods).
    /// Expected values below were computed independently (separate Python
    /// implementation of Wilder's method) on these exact rounded prices.
    private let sample: [Double] = [
        44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42, 45.84, 46.08, 45.89, 46.03,
        45.61, 46.28, 46.28, 46.00, 46.03, 46.41, 46.22, 45.64, 46.21, 46.25, 45.71, 46.45,
        45.78, 45.35, 44.03, 44.18, 44.22, 44.57, 43.42, 42.66, 43.13,
    ]

    func testSMA() {
        let r = Indicators.sma([1, 2, 3, 4, 5], period: 3)
        XCTAssertEqual(r.map { $0 ?? -1 }, [-1, -1, 2, 3, 4])
    }

    func testEMASeededWithSMA() throws {
        let r = Indicators.ema([1, 2, 3, 4, 5], period: 3)
        XCTAssertNil(r[1])
        XCTAssertEqual(try XCTUnwrap(r[2]), 2, accuracy: 1e-12)          // SMA seed
        XCTAssertEqual(try XCTUnwrap(r[3]), 3, accuracy: 1e-12)          // 4*0.5 + 2*0.5
        XCTAssertEqual(try XCTUnwrap(r[4]), 4, accuracy: 1e-12)
    }

    func testRSIMatchesTheTextbookExample() throws {
        let r = Indicators.rsi(sample, period: 14)
        XCTAssertNil(r[13])
        XCTAssertEqual(try XCTUnwrap(r[14]), 70.46, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r[15]), 66.25, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r[16]), 66.48, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r.last ?? nil), 37.79, accuracy: 0.01)
    }

    func testRSIBounds() {
        let up = Indicators.rsi((0..<40).map { Double($0) }, period: 14)
        XCTAssertEqual(up.last!!, 100)
        let down = Indicators.rsi((0..<40).map { Double(100 - $0) }, period: 14)
        XCTAssertEqual(down.last!!, 0, accuracy: 1e-9)
        for v in Indicators.rsi(sample).compactMap({ $0 }) { XCTAssertTrue((0...100).contains(v)) }
    }

    func testBollingerOnConstantSeriesCollapses() throws {
        let b = Indicators.bollinger([10, 10, 10, 10, 10, 10], period: 3)
        XCTAssertEqual(try XCTUnwrap(b.upper[5]), 10, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(b.lower[5]), 10, accuracy: 1e-12)
    }

    func testBollingerBandWidth() throws {
        // [1,2,3]: mean 2, population sd = sqrt(2/3)
        let b = Indicators.bollinger([1, 2, 3], period: 3, deviations: 2)
        let sd = (2.0 / 3.0).squareRoot()
        XCTAssertEqual(try XCTUnwrap(b.upper[2]), 2 + 2 * sd, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(b.lower[2]), 2 - 2 * sd, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(b.middle[2]), 2, accuracy: 1e-12)
    }

    func testMACDStructure() throws {
        let closes = (0..<120).map { 100 + 10 * sin(Double($0) / 7) + Double($0) * 0.1 }
        let m = Indicators.macd(closes)
        XCTAssertEqual(m.macd.count, closes.count)
        XCTAssertNil(m.macd[24])
        XCTAssertNotNil(m.macd[25])                 // 26th value is the first MACD
        XCTAssertNil(m.signal[32])
        XCTAssertNotNil(m.signal[33])               // 9 MACD values later
        for i in closes.indices {
            if let a = m.macd[i], let s = m.signal[i], let h = m.histogram[i] {
                XCTAssertEqual(h, a - s, accuracy: 1e-12)
            }
        }
    }

    func testShortSeriesAreSafe() {
        XCTAssertEqual(Indicators.sma([], period: 3).count, 0)
        XCTAssertEqual(Indicators.ema([1, 2], period: 5).compactMap { $0 }.count, 0)
        XCTAssertEqual(Indicators.rsi([1, 2, 3], period: 14).compactMap { $0 }.count, 0)
        XCTAssertEqual(Indicators.macd([1, 2, 3]).macd.compactMap { $0 }.count, 0)
    }
}
