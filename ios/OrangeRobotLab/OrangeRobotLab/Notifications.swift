import Foundation
import UserNotifications
import BackgroundTasks
import OrangeRobotKit

/// Local notifications for live tests. Everything here is opt-in and on-device.
enum LabNotifications {
    static let refreshTaskID = "com.theorangerobot.lab.refresh"
    private static let dailyID = "lab.daily-close"

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func post(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// A once-a-day nudge shortly after the UTC daily close, so there's a reliable
    /// reminder even if iOS never grants background time.
    static func setDailyReminder(_ on: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])
        guard on else { return }
        var comps = DateComponents()
        comps.hour = 0; comps.minute = 30
        comps.timeZone = TimeZone(identifier: "UTC")
        let c = UNMutableNotificationContent()
        c.title = "Daily close is in 🤖"
        c.body = "See what your robots did today."
        c.sound = .default
        center.add(UNNotificationRequest(identifier: dailyID, content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }

    /// Ask iOS to wake the app just after the next daily close. iOS decides if and when.
    static func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        var comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: Date())
        comps.day = (comps.day ?? 1) + 1; comps.hour = 0; comps.minute = 10; comps.second = 0
        req.earliestBeginDate = Calendar(identifier: .gregorian).date(from: comps)
        try? BGTaskScheduler.shared.submit(req)
    }
}

/// Shows banners even while the app is open.
final class LabNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}
