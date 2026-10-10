import Foundation
import OrangeRobotKit

/// App-wide anonymous activity counters. See `ActivityClient` for exactly what
/// is (and is not) sent. Players can switch it off in the info screen.
enum Activity {
    static let settingKey = "share_usage_counts"

    private static let client = ActivityClient(isEnabled: {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    })

    static func track(_ event: ActivityEvent) { client.track(event) }
}
