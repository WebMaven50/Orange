import Foundation

/// Everything needed to put a run back exactly where it was after the app was closed.
/// Prices are a pure function of (start day, minute), so only the player's state is stored.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = SessionSnapshot.currentVersion
    public var startDay: Int
    public var microMoves: Bool
    public var isRandomStart: Bool
    public var absMinute: Double
    public var cash: Double
    public var btc: Double
    public var bestEquity: Double
    public var trades: Int
    public var averageEntry: Double?
    public var realizedPL: Double
    public var feesPaid: Double
    public var fills: [Fill]
    public var pendingOrders: [PendingOrder]
    public var speed: PlaybackSpeed
    public var nextOrderID: Int
    public var nextFillID: Int
    /// When it was saved (wall clock), for showing "last played".
    public var savedAt: Date
}

extension GameSession {
    /// Snapshot of a run in progress. A sleep in flight is completed so nothing is lost.
    public func snapshot(savedAt: Date = Date()) -> SessionSnapshot? {
        guard isRunning else { return nil }
        return SessionSnapshot(
            startDay: engine.startDay, microMoves: engine.microMoves, isRandomStart: isRandomStart,
            absMinute: sleepTargetMinute ?? absMinute, cash: cash, btc: btc, bestEquity: bestEquity,
            trades: trades, averageEntry: averageEntry, realizedPL: realizedPL, feesPaid: feesPaid,
            fills: fills, pendingOrders: pendingOrders, speed: speed,
            nextOrderID: nextOrderIDValue, nextFillID: nextFillIDValue, savedAt: savedAt)
    }

    /// Rebuild a run from a snapshot; nil if it no longer fits the bundled history.
    public init?(snapshot s: SessionSnapshot, history: PriceHistory = .bundled) {
        guard s.version == SessionSnapshot.currentVersion,
              s.startDay >= 0, s.startDay < history.count,
              s.absMinute.isFinite, s.cash.isFinite, s.btc.isFinite else { return nil }
        self.init(engine: PriceEngine(history: history, startDay: s.startDay, microMoves: s.microMoves),
                  startMinute: s.absMinute, isRandomStart: s.isRandomStart)
        restore(from: s)
    }
}
