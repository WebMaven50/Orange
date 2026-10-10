import Foundation

public enum Side: String, Codable, Sendable { case buy, sell }

public enum OrderType: String, Codable, Sendable { case market, limit, stop, trailing }

/// A resting limit / stop / trailing-stop order.
///
/// `amountFraction` is stored as a share of whatever is tradable *when it
/// fills*, so a "100%" order always means "everything" even if the balance
/// changed while it waited.
public struct PendingOrder: Identifiable, Equatable, Sendable {
    public let id: Int
    public let type: OrderType
    public let side: Side
    public let amountFraction: Double
    public let createdAtPrice: Double
    /// Limit price (limit), trigger price (stop), or trail percent (trailing).
    public let level: Double
    /// Best price seen since placement; only used by trailing orders.
    public internal(set) var extreme: Double

    public var trailPercent: Double? { type == .trailing ? level : nil }
}

public enum OrderError: Error, Equatable, Sendable {
    case sessionOver
    case sleeping
    case amountTooSmall
    case invalidPrice
}

public enum GameOutcome: String, Codable, Sendable {
    case win        // reached the $1M target
    case bust       // equity hit zero
    case cashout    // player cashed out
}
