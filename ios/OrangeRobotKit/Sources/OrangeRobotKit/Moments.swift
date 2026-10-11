import Foundation

/// Things that happen during a run that are worth a little physical nudge.
public enum GameMoment: Equatable, Sendable {
    /// Equity climbed past a notable level (first time only).
    case milestone(level: Double)
    /// Equity fell to a dangerous level.
    case danger
    /// Price came close to one of the player's resting orders.
    case near(orderID: Int)
    /// A fast price move over the last hour of game time.
    case swing(percent: Double)
}

/// Watches a run and reports moments, each at most once at a time, so haptics
/// stay meaningful instead of buzzing constantly. Pure logic: feed it numbers.
public struct MomentMonitor: Sendable {
    public static let milestones: [Double] = [150_000, 250_000, 500_000, 750_000]
    /// Equity at or below this triggers the danger pulse (25% of the $100k start).
    public static let dangerLevel = 25_000.0
    /// Danger re-arms once equity is back above this.
    public static let dangerRearm = 40_000.0
    /// How close (as a share of price) before an order counts as "near" / re-arms.
    public static let nearEnter = 0.004
    public static let nearLeave = 0.012
    /// A swing is a move of at least this share within `swingWindow` game-minutes.
    public static let swingThreshold = 0.025
    public static let swingWindow = 60.0
    /// Minimum game-minutes between swing pulses.
    public static let swingCooldown = 360.0

    private var reached: Set<Double> = []
    private var dangerArmed = true
    private var nearActive: Set<Int> = []
    private var samples: [(minute: Double, price: Double)] = []
    private var lastSwingMinute = -Double.infinity

    public init() {}

    /// Forget recent price history (e.g. after sleeping) so a skipped stretch
    /// isn't reported as one giant swing.
    public mutating func resetSwing(at minute: Double? = nil) {
        samples.removeAll()
        if let minute { lastSwingMinute = minute }
    }

    public mutating func update(equity: Double,
                                price: Double,
                                absMinute: Double,
                                orderTriggers: [(id: Int, price: Double)],
                                allowSwing: Bool = true) -> [GameMoment] {
        var out: [GameMoment] = []

        // Milestones: first time only, report only the highest newly reached.
        var newest: Double?
        for level in Self.milestones where equity >= level && !reached.contains(level) {
            reached.insert(level)
            newest = level
        }
        if let newest { out.append(.milestone(level: newest)) }

        // Danger, with hysteresis.
        if dangerArmed, equity <= Self.dangerLevel, equity > 0 {
            dangerArmed = false
            out.append(.danger)
        } else if !dangerArmed, equity >= Self.dangerRearm {
            dangerArmed = true
        }

        // Near a resting order.
        let ids = Set(orderTriggers.map(\.id))
        nearActive.formIntersection(ids)                      // drop orders that are gone
        if price > 0 {
            for o in orderTriggers {
                let d = abs(price - o.price) / price
                if !nearActive.contains(o.id), d <= Self.nearEnter {
                    nearActive.insert(o.id)
                    out.append(.near(orderID: o.id))
                } else if nearActive.contains(o.id), d >= Self.nearLeave {
                    nearActive.remove(o.id)                  // re-arm
                }
            }
        }

        // Swings over the last hour.
        samples.append((absMinute, price))
        samples.removeAll { absMinute - $0.minute > Self.swingWindow * 2 }
        if allowSwing, price > 0, absMinute - lastSwingMinute >= Self.swingCooldown,
           let ref = samples.first(where: { absMinute - $0.minute <= Self.swingWindow }),
           ref.minute < absMinute, ref.price > 0 {
            let change = (price - ref.price) / ref.price
            if abs(change) >= Self.swingThreshold {
                lastSwingMinute = absMinute
                out.append(.swing(percent: change * 100))
            }
        }
        return out
    }
}
