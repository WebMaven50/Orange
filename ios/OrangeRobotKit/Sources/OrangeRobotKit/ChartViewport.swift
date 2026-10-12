import Foundation

/// Which part of the market a chart is showing: how far back in time the right edge
/// is pinned, and how much the price scale has been stretched.
///
/// `end == nil` means "live": the right edge follows the game clock. Otherwise it is a
/// game-minute (same clock as `GameSession.absMinute`) and the chart stays put while the
/// game keeps running.
public struct ChartViewport: Equatable, Sendable {
    public static let minZoom = 0.4
    public static let maxZoom = 12.0

    public private(set) var end: Double?
    public private(set) var priceZoom = 1.0

    public init() {}

    public var isLive: Bool { end == nil }
    public var isDefaultZoom: Bool { abs(priceZoom - 1) < 0.001 }

    /// The minute the chart's last candle should end on, snapped to the end of a candle so
    /// every visible candle is complete (except when live, where the last one is forming).
    public func effectiveEnd(timeframe tf: Int, liveMinute: Double) -> Double {
        guard let end else { return liveMinute }
        let t = Double(tf)
        let bucket = floor(end / t)
        if bucket >= floor(liveMinute / t) { return liveMinute }
        return (bucket + 1) * t - 0.001
    }

    /// Scroll back in time (`n` > 0) or forward (`n` < 0), measured in candles.
    /// Stops at the start of the data and snaps back to live when it catches up.
    public mutating func pan(candlesBack n: Double, timeframe tf: Int, liveMinute: Double,
                             startDay: Int, visibleCandles: Int = 48) {
        let t = Double(tf)
        let current = end ?? liveMinute
        let earliest = -Double(startDay) * 1440 + Double(visibleCandles) * t
        let target = max(current - n * t, earliest)
        if floor(target / t) >= floor(liveMinute / t) { end = nil } else { end = target }
    }

    public mutating func goLive() { end = nil }

    /// Multiply the price-scale zoom (> 1 stretches the price axis in, < 1 squeezes it out).
    public mutating func zoom(by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        priceZoom = min(max(priceZoom * factor, Self.minZoom), Self.maxZoom)
    }

    public mutating func resetZoom() { priceZoom = 1 }
    public mutating func reset() { end = nil; priceZoom = 1 }
}
