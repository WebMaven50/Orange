import XCTest
@testable import OrangeRobotKit

final class MomentTests: XCTestCase {
    private func run(_ m: inout MomentMonitor, equity: Double, price: Double = 100, minute: Double = 0,
                     orders: [(id: Int, price: Double)] = [], swing: Bool = true) -> [GameMoment] {
        m.update(equity: equity, price: price, absMinute: minute, orderTriggers: orders, allowSwing: swing)
    }

    func testMilestoneFiresOnceOnTheWayUp() {
        var m = MomentMonitor()
        XCTAssertTrue(run(&m, equity: 120_000).isEmpty)
        XCTAssertEqual(run(&m, equity: 152_000), [.milestone(level: 150_000)])
        XCTAssertTrue(run(&m, equity: 160_000).isEmpty)
        _ = run(&m, equity: 140_000)                       // falls back
        XCTAssertTrue(run(&m, equity: 155_000).isEmpty, "already reached")
        XCTAssertEqual(run(&m, equity: 260_000), [.milestone(level: 250_000)])
    }

    func testJumpingPastSeveralLevelsReportsOnlyTheHighest() {
        var m = MomentMonitor()
        XCTAssertEqual(run(&m, equity: 600_000), [.milestone(level: 500_000)])
    }

    func testDangerFiresOnceAndRearmsAfterRecovery() {
        var m = MomentMonitor()
        XCTAssertEqual(run(&m, equity: 24_000), [.danger])
        XCTAssertTrue(run(&m, equity: 20_000).isEmpty, "still in danger: no repeat")
        XCTAssertTrue(run(&m, equity: 30_000).isEmpty, "not recovered enough to re-arm")
        _ = run(&m, equity: 45_000)                        // re-armed
        XCTAssertEqual(run(&m, equity: 22_000), [.danger])
    }

    func testBustIsNotADangerPulse() {
        var m = MomentMonitor()
        XCTAssertTrue(run(&m, equity: 0).isEmpty)          // the bust cue handles it
    }

    func testNearFiresWhenPriceApproachesAnOrderAndRearmsAfterMovingAway() {
        var m = MomentMonitor()
        let order = [(id: 7, price: 100.0)]
        XCTAssertTrue(run(&m, equity: 100_000, price: 105, orders: order).isEmpty)
        XCTAssertEqual(run(&m, equity: 100_000, price: 100.3, orders: order), [.near(orderID: 7)])
        XCTAssertTrue(run(&m, equity: 100_000, price: 100.2, orders: order).isEmpty, "no repeat while close")
        _ = run(&m, equity: 100_000, price: 102, orders: order)     // moved away (>1.2%)
        XCTAssertEqual(run(&m, equity: 100_000, price: 100.1, orders: order), [.near(orderID: 7)])
    }

    func testCancelledOrdersAreForgotten() {
        var m = MomentMonitor()
        _ = run(&m, equity: 100_000, price: 100.1, orders: [(id: 3, price: 100)])
        _ = run(&m, equity: 100_000, price: 100.1, orders: [])
        XCTAssertEqual(run(&m, equity: 100_000, price: 100.1, orders: [(id: 3, price: 100)]), [.near(orderID: 3)])
    }

    func testSwingNeedsAFastMove() {
        var m = MomentMonitor()
        _ = run(&m, equity: 100_000, price: 100, minute: 0)
        XCTAssertTrue(run(&m, equity: 100_000, price: 101, minute: 30).isEmpty)       // +1%
        let r = run(&m, equity: 100_000, price: 103.5, minute: 55)                   // +3.5% in 55 min
        XCTAssertEqual(r.count, 1)
        if case let .swing(p) = r.first { XCTAssertGreaterThan(p, 3) } else { XCTFail() }
    }

    func testSlowDriftIsNotASwing() {
        var m = MomentMonitor()
        var fired = 0
        for k in 0..<200 {      // +0.05% per 5 minutes ≈ +0.6% an hour
            let p = 100 * pow(1.0005, Double(k))
            if !run(&m, equity: 100_000, price: p, minute: Double(k) * 5).isEmpty { fired += 1 }
        }
        XCTAssertEqual(fired, 0)
    }

    func testSwingCooldownAndFallsCount() {
        var m = MomentMonitor()
        _ = run(&m, equity: 100_000, price: 100, minute: 0)
        XCTAssertFalse(run(&m, equity: 100_000, price: 96, minute: 40).isEmpty)       // −4%
        XCTAssertTrue(run(&m, equity: 100_000, price: 90, minute: 80).isEmpty, "cooling down")
        _ = run(&m, equity: 100_000, price: 90, minute: 500)
        XCTAssertFalse(run(&m, equity: 100_000, price: 94, minute: 520).isEmpty, "cooldown over")
    }

    func testSwingCanBeSuppressedAndResetAfterSleep() {
        var m = MomentMonitor()
        _ = run(&m, equity: 100_000, price: 100, minute: 0)
        XCTAssertTrue(run(&m, equity: 100_000, price: 110, minute: 30, swing: false).isEmpty)
        m.resetSwing(at: 30)
        XCTAssertTrue(run(&m, equity: 100_000, price: 111, minute: 35).isEmpty, "history was reset")
    }
}
