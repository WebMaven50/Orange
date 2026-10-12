import Foundation

/// One real-time price, stamped with the game clock it arrived at.
public struct LiveSample: Codable, Equatable, Sendable {
    public let minute: Double
    public let price: Double
}

/// Current BTC/USD price for real-time play. Kraken first, Coinbase as the fallback.
public enum LivePrice {
    public enum Failure: Error { case unavailable }

    static func parseKrakenTicker(_ data: Data) throws -> Double {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let key = result.keys.first,
              let ticker = result[key] as? [String: Any],
              let last = (ticker["c"] as? [Any])?.first as? String,
              let price = Double(last), price > 0
        else { throw Failure.unavailable }
        return price
    }

    static func parseCoinbaseTicker(_ data: Data) throws -> Double {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["price"] as? String,
              let price = Double(text), price > 0
        else { throw Failure.unavailable }
        return price
    }

    public static func fetch(session: URLSession = .shared) async throws -> Double {
        let kraken = URL(string: "https://api.kraken.com/0/public/Ticker?pair=XBTUSD")!
        if let pair = try? await session.data(from: kraken),
           (pair.1 as? HTTPURLResponse)?.statusCode == 200,
           let price = try? parseKrakenTicker(pair.0) {
            return price
        }
        let coinbase = URL(string: "https://api.exchange.coinbase.com/products/BTC-USD/ticker")!
        let (data, _) = try await session.data(from: coinbase)
        return try parseCoinbaseTicker(data)
    }
}
