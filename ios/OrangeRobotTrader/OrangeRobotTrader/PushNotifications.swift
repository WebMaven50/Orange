import SwiftUI
import UIKit
import UserNotifications

/// Game messages and price alerts. Off until the player turns them on in Info.
///
/// The server only ever gets a random push token, whether it's a test build, and the two
/// choices. Turning both off deletes the token on the server.
enum GameNotifications {
    static let messagesKey = "notify_messages"
    static let alertsKey = "notify_price_alerts"
    /// Set once the player has been asked after a finished game. The question is never repeated.
    static let askedKey = "notify_asked"
    /// The move, in percent, that triggers a price alert. Default 5.
    static let thresholdKey = "notify_alert_percent"
    static let thresholdChoices = [2, 3, 5, 10]
    private static let tokenKey = "push_token"

    /// The notify Worker. Set once it's deployed.
    static let endpoint = URL(string: "https://orange-robot-notify.victor-cb4.workers.dev")!

    private static var messages: Bool { UserDefaults.standard.bool(forKey: messagesKey) }
    private static var alerts: Bool { UserDefaults.standard.bool(forKey: alertsKey) }
    private static var storedToken: String? { UserDefaults.standard.string(forKey: tokenKey) }
    private static var threshold: Int {
        let v = UserDefaults.standard.integer(forKey: thresholdKey)
        return thresholdChoices.contains(v) ? v : 5
    }

    /// The one-time question: both on, or both off. Returns false if iOS refused permission.
    @discardableResult
    static func answerPrompt(yes: Bool) async -> Bool {
        UserDefaults.standard.set(yes, forKey: messagesKey)
        UserDefaults.standard.set(yes, forKey: alertsKey)
        let ok = await apply()
        if !ok {
            UserDefaults.standard.set(false, forKey: messagesKey)
            UserDefaults.standard.set(false, forKey: alertsKey)
        }
        return ok
    }

    /// Apply the two switches. Registers when either is on, removes the token when both are off.
    @discardableResult
    static func apply() async -> Bool {
        guard messages || alerts else {
            await removeFromServer()
            return true
        }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        // The token arrives in PushAppDelegate, which uploads it with the current choices.
        if storedToken != nil { await upload() }
        return true
    }

    /// Called by the app delegate when iOS hands over a token.
    static func received(token data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        Task { await upload() }
    }

    private static func upload() async {
        guard let token = storedToken else { return }
        #if DEBUG
        let sandbox = true   // Xcode builds use the development push service
        #else
        let sandbox = false  // TestFlight and App Store builds use production
        #endif
        await post("device", [
            "token": token,
            "sandbox": sandbox,
            "messages": messages,
            "alerts": alerts,
            "threshold": threshold,
        ])
    }

    private static func removeFromServer() async {
        guard let token = storedToken else { return }
        await post("device/remove", ["token": token])
        UserDefaults.standard.removeObject(forKey: tokenKey)
        await MainActor.run { UIApplication.shared.unregisterForRemoteNotifications() }
    }

    private static func post(_ path: String, _ body: [String: Any]) async {
        var req = URLRequest(url: endpoint.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}

/// Receives the push token from iOS and shows banners while the game is open.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        GameNotifications.received(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Nothing to show the player: notifications simply stay off.
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    /// Tapping a message with a link opens that link.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) {
            await MainActor.run { UIApplication.shared.open(url) }
        }
    }
}
