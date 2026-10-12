import XCTest
@testable import OrangeRobotKit

final class SessionSnapshotTests: XCTestCase {
    private func played() throws -> GameSession {
        var rng = SplitMix64(seed: 21)
        var s = GameSession.random(microMoves: true, using: &rng)
        try s.place(side: .buy, type: .market, amountUSD: 40_000)
        try s.place(side: .sell, type: .limit, amountUSD: 20_000, level: s.lastPrice * 3)
        for _ in 0..<600 { s.advance(seconds: 0.05) }
        return s
    }

    func testRoundTripRestoresThePlayersState() throws {
        let s = try played()
        let snap = try XCTUnwrap(s.snapshot())
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        let r = try XCTUnwrap(GameSession(snapshot: back))
        XCTAssertEqual(r.cash, s.cash, accuracy: 1e-9)
        XCTAssertEqual(r.btc, s.btc, accuracy: 1e-12)
        XCTAssertEqual(r.absMinute, s.absMinute, accuracy: 1e-9)
        XCTAssertEqual(r.lastPrice, s.lastPrice, accuracy: 1e-6)
        XCTAssertEqual(r.pendingOrders, s.pendingOrders)
        XCTAssertEqual(r.fills, s.fills)
        XCTAssertEqual(r.averageEntry, s.averageEntry)
        XCTAssertEqual(r.isRandomStart, s.isRandomStart)
        XCTAssertTrue(r.isPaused, "a restored run waits for the player")
    }

    func testRestoredRunKeepsPlayingAndNumbersNewOrdersAfterOldOnes() throws {
        let s = try played()
        var r = try XCTUnwrap(GameSession(snapshot: try XCTUnwrap(s.snapshot())))
        r.resume()
        let o = try XCTUnwrap(try r.place(side: .sell, type: .limit, amountUSD: 1_000, level: r.lastPrice * 4))
        XCTAssertFalse(s.pendingOrders.contains { $0.id == o.id }, "order ids must not collide")
        let before = r.absMinute
        r.advance(seconds: 0.05)
        XCTAssertGreaterThan(r.absMinute, before)
    }

    func testFinishedRunsAreNotSaved() throws {
        var s = try played()
        s.cashOut()
        XCTAssertNil(s.snapshot())
    }

    func testSleepInFlightIsCompletedInTheSnapshot() throws {
        var s = try played()
        let start = s.absMinute
        XCTAssertTrue(s.skipDays(1))
        let snap = try XCTUnwrap(s.snapshot())
        XCTAssertEqual(snap.absMinute, start + 1440, accuracy: 1e-9)
    }

    func testBadSnapshotsAreRejected() throws {
        var snap = try XCTUnwrap(try played().snapshot())
        snap.startDay = 99_999_999
        XCTAssertNil(GameSession(snapshot: snap))
    }

    func testDaySkipIsInstantAndNotASleep() throws {
        var s = try played()
        let start = s.absMinute
        XCTAssertTrue(s.skipDays(1))
        XCTAssertFalse(s.isSleeping, "a day skip is not a sleep")
        XCTAssertEqual(s.absMinute, start + 1440, accuracy: 1e-6)
    }

    func testSeveralPressesStackDays() throws {
        var s = try played()
        let start = s.absMinute
        for _ in 0..<7 { XCTAssertTrue(s.skipDays(1)) }
        XCTAssertEqual(s.absMinute, start + 7 * 1440, accuracy: 1e-6)
    }

    func testSkipFillsALimitThatWouldHaveTriggeredOnTheWay() throws {
        var s = GameSession.starting(at: Date(timeIntervalSince1970: 1_580_000_000))
        try s.place(side: .buy, type: .market, amountUSD: 10_000)
        let now = s.absMinute
        // The real intraday peak of the next day, sampled on the same path the skip walks.
        let peak = (0...144).map { s.engine.price(atMinute: now + Double($0) * 10) }.max()!
        XCTAssertGreaterThan(peak, s.lastPrice, "pick a day that rises, or the test proves nothing")
        try s.place(side: .sell, type: .limit, amountUSD: 10_000, level: peak * 0.9999)
        XCTAssertEqual(s.pendingOrders.count, 1)
        XCTAssertTrue(s.skipDays(1))
        XCTAssertTrue(s.pendingOrders.isEmpty, "the limit should have filled during the skipped day")
        XCTAssertEqual(s.fills.first?.via, .limit)
    }

    func testSkipDoesNothingWhilePaused() throws {
        var s = try played()
        s.pause()
        XCTAssertFalse(s.skipDays(1))
    }
}
