import XCTest
@testable import OrangeRobotKit

final class ActivityTests: XCTestCase {
    func testBodyContainsOnlyTheEventName() throws {
        for ev in ActivityEvent.allCases {
            let req = ActivityClient().request(for: ev)
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.path, "/app-event")
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: String])
            XCTAssertEqual(obj, ["event": ev.rawValue], "body must carry nothing but the event name")
            XCTAssertFalse(req.httpShouldHandleCookies)
            // Only the content type is set explicitly: no IDs, tokens or custom headers.
            XCTAssertEqual(req.allHTTPHeaderFields, ["Content-Type": "application/json"])
        }
    }

    /// Must stay in lock-step with the Worker's APP_EVENTS allowlist.
    func testEventNamesMatchServerAllowlist() {
        let server: Set<String> = ["app_open", "game_start", "game_end", "game_win", "score_saved",
                                   "leaderboard_open", "prologue_play", "prologue_complete",
                                   "book_link_tap", "audiobook_link_tap"]
        XCTAssertEqual(Set(ActivityEvent.allCases.map(\.rawValue)), server)
    }

    func testDisabledSendsNothing() async throws {
        CountingProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [CountingProtocol.self]

        ActivityClient(session: URLSession(configuration: cfg), isEnabled: { false }).track(.appOpen)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(CountingProtocol.hits, 0, "disabled client must not touch the network")

        ActivityClient(session: URLSession(configuration: cfg), isEnabled: { true }).track(.appOpen)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(CountingProtocol.hits, 1)
    }
}

private final class CountingProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _hits = 0
    static var hits: Int { lock.lock(); defer { lock.unlock() }; return _hits }
    static func reset() { lock.lock(); _hits = 0; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self._hits += 1; Self.lock.unlock()
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
