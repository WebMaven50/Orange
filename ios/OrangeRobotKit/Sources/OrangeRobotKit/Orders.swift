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
    public internal(set) var amountFraction: Double
    public let createdAtPrice: Double
    /// Limit price (limit), trigger price (stop), or trail percent (trailing).
    public internal(set) var level: Double
    /// Best price seen since placement; only used by trailing orders.
    public internal(set) var extreme: Double

    public var trailPercent: Double? { type == .trailing ? level : nil }
}

public enum OrderError: Error, Equatable, Sendable {
    case sessionOver
    case sleeping
    case amountTooSmall
    case invalidPrice
    case orderNotFound
    /// A stop on the wrong side of the market would trigger instantly (a sell stop above the
    /// price, a buy stop below it). `limit` is true when a limit order is what they meant.
    case stopOnWrongSide(side: Side)
}

public enum GameOutcome: String, Codable, Sendable {
    case win        // reached the $1M target
    case bust       // equity hit zero
    case cashout    // player cashed out
}

/// One executed trade (a market order, or a resting order that triggered).
public struct Fill: Identifiable, Equatable, Sendable {
    public let id: Int
    /// Game clock (minutes since the start of the run) when it filled.
    public let absMinute: Double
    public let side: Side
    /// How it was placed: market, or the resting order type that triggered.
    public let via: OrderType
    public let price: Double
    /// BTC bought or sold (always positive).
    public let quantity: Double
    /// Dollar size of the order, before fee.
    public let notional: Double
    public let fee: Double
}
