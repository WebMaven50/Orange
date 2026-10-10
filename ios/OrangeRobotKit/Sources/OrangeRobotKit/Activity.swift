import Foundation

/// The complete list of things the app ever reports. Each is a bare counter on
/// the server: no identifiers, no parameters, no personal data.
public enum ActivityEvent: String, CaseIterable, Sendable {
    case appOpen = "app_open"
    case gameStart = "game_start"
    case gameEnd = "game_end"
    case gameWin = "game_win"
    case scoreSaved = "score_saved"
    case leaderboardOpen = "leaderboard_open"
    case prologuePlay = "prologue_play"
    case prologueComplete = "prologue_complete"
    case bookLinkTap = "book_link_tap"
    case audiobookLinkTap = "audiobook_link_tap"
}

/// Sends anonymous aggregate counters to the store Worker.
///
/// Privacy by construction: the request body is only `{"event": "<name>"}`.
/// There is no install ID, no device info, no timestamp, no session, and the
/// session is ephemeral (no cookies, no cache). The server stores only a
/// per-day count per event name.
public struct ActivityClient: Sendable {
    public static let baseURL = URL(string: "https://orange-robot-store.victor-cb4.workers.dev")!

    private let base: URL
    private let session: URLSession
    private let isEnabled: @Sendable () -> Bool

    public init(base: URL = Self.baseURL,
                session: URLSession? = nil,
                isEnabled: @escaping @Sendable () -> Bool = { true }) {
        self.base = base
        self.isEnabled = isEnabled
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpCookieStorage = nil
            cfg.urlCache = nil
            cfg.timeoutIntervalForRequest = 8
            cfg.waitsForConnectivity = false
            self.session = URLSession(configuration: cfg)
        }
    }

    func request(for event: ActivityEvent) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent("app-event"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["event": event.rawValue])
        req.httpShouldHandleCookies = false
        return req
    }

    /// Fire and forget. Failures are ignored on purpose: analytics must never
    /// affect the game.
    public func track(_ event: ActivityEvent) {
        guard isEnabled() else { return }
        let req = request(for: event)
        let session = self.session
        Task.detached(priority: .utility) {
            _ = try? await session.data(for: req)
        }
    }
}
