import Foundation

/// One row on a leaderboard.
public struct LeaderboardEntry: Decodable, Equatable, Identifiable, Sendable {
    public let initials: String
    public let score: Double?
    public let sats: Double?
    public let ts: Double?

    public var id: String { "\(initials)-\(score ?? 0)-\(ts ?? 0)" }
}

public struct SubmitResult: Equatable, Sendable {
    /// 1-based rank of the submitted score, if it made the stored board.
    public let rank: Int?
}

public enum LeaderboardError: Error, Equatable, Sendable {
    case invalidInitials
    case server(Int)
    case network
}

/// Talks to the shared Orange Robot leaderboard Worker — the same service the
/// website uses, so scores from the app and the site land on one board.
public struct LeaderboardClient: Sendable {
    public static let baseURL = URL(string: "https://orange-robot-leaderboard.victor-cb4.workers.dev")!
    public static let traderGame = "trader"

    private let base: URL
    private let session: URLSession

    public init(base: URL = Self.baseURL, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    /// Matches the Worker's own rule: 1–3 characters, A–Z and 0–9.
    public static func cleanInitials(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { ($0 >= "A" && $0 <= "Z") || ($0 >= "0" && $0 <= "9") }
        let three = String(cleaned.prefix(3))
        return three.isEmpty ? nil : three
    }

    func topURL(game: String, limit: Int) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("leaderboard"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "game", value: game),
                        URLQueryItem(name: "limit", value: String(limit))]
        return c.url!
    }

    /// Top scores, best first. Throws if the board can't be reached.
    public func top(game: String = traderGame, limit: Int = 10) async throws -> [LeaderboardEntry] {
        struct Response: Decodable { let entries: [LeaderboardEntry] }
        do {
            let (data, resp) = try await session.data(from: topURL(game: game, limit: limit))
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LeaderboardError.server(http.statusCode)
            }
            return try JSONDecoder().decode(Response.self, from: data).entries
        } catch let e as LeaderboardError {
            throw e
        } catch {
            throw LeaderboardError.network
        }
    }

    func submitRequest(game: String, initials: String, score: Int, sats: Int) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent("submit"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["game": game, "initials": initials, "score": score, "sats": sats]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }

    /// Save a finished run. `score` is final equity in whole dollars (same as the website).
    @discardableResult
    public func submit(game: String = traderGame, initials rawInitials: String,
                       score: Int, sats: Int) async throws -> SubmitResult {
        guard let initials = Self.cleanInitials(rawInitials) else { throw LeaderboardError.invalidInitials }
        struct Response: Decodable { let ok: Bool?; let rank: Int? }
        do {
            let req = submitRequest(game: game, initials: initials, score: max(0, score), sats: max(0, sats))
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LeaderboardError.server(http.statusCode)
            }
            let r = try JSONDecoder().decode(Response.self, from: data)
            return SubmitResult(rank: r.rank)
        } catch let e as LeaderboardError {
            throw e
        } catch {
            throw LeaderboardError.network
        }
    }
}
