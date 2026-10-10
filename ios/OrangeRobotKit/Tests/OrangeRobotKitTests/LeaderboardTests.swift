import XCTest
@testable import OrangeRobotKit

final class LeaderboardTests: XCTestCase {
    func testInitialsMatchWorkerRules() {
        XCTAssertEqual(LeaderboardClient.cleanInitials("vj"), "VJ")
        XCTAssertEqual(LeaderboardClient.cleanInitials(" a-b_c d"), "ABC")
        XCTAssertEqual(LeaderboardClient.cleanInitials("abcdef"), "ABC")
        XCTAssertNil(LeaderboardClient.cleanInitials("  !! "))
        XCTAssertNil(LeaderboardClient.cleanInitials(""))
    }

    func testRequestShapeMatchesWebClient() throws {
        let c = LeaderboardClient()
        let req = c.submitRequest(game: "trader", initials: "VJ", score: 133162, sats: 33162)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString, "https://orange-robot-leaderboard.victor-cb4.workers.dev/submit")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any])
        XCTAssertEqual(obj["game"] as? String, "trader")
        XCTAssertEqual(obj["initials"] as? String, "VJ")
        XCTAssertEqual(obj["score"] as? Int, 133162)
        XCTAssertEqual(obj["sats"] as? Int, 33162)
    }

    func testTopURL() {
        let u = LeaderboardClient().topURL(game: "trader", limit: 5)
        XCTAssertEqual(u.absoluteString,
                       "https://orange-robot-leaderboard.victor-cb4.workers.dev/leaderboard?game=trader&limit=5")
    }

    func testDecodesRealWorkerPayload() throws {
        let json = #"{"game":"trader","entries":[{"initials":"JK","score":1000671,"sats":900671,"ts":1783205243049},{"initials":"H","score":115624,"sats":15624,"ts":1784350674346}]}"#
        struct R: Decodable { let entries: [LeaderboardEntry] }
        let r = try JSONDecoder().decode(R.self, from: Data(json.utf8))
        XCTAssertEqual(r.entries.map(\.initials), ["JK", "H"])
        XCTAssertEqual(r.entries[0].score, 1000671)
    }

    func testInvalidInitialsRejectedBeforeNetwork() async {
        do {
            _ = try await LeaderboardClient().submit(initials: "!!", score: 1, sats: 0)
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? LeaderboardError, .invalidInitials)
        }
    }
}
