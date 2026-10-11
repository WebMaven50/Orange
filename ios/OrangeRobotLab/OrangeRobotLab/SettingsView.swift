import SwiftUI
import UserNotifications
import OrangeRobotKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LabModel.self) private var lab
    @AppStorage(Feedback.hapticsKey) private var haptics = true
    @AppStorage(Feedback.soundKey) private var sound = true
    @AppStorage(ActivityLab.settingKey) private var shareCounts = true
    @State private var permission: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("Feel")
                            Toggle(isOn: $haptics) {
                                label("Haptics", "A small tap when a robot buys or sells and when a test ends.")
                            }.tint(Theme.orange)
                            Toggle(isOn: $sound) {
                                label("Sound effects", "Short tones. They follow your phone's silent switch.")
                            }.tint(Theme.orange)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("Notifications")
                            Toggle(isOn: Binding(
                                get: { lab.notificationsEnabled },
                                set: { on in
                                    if on {
                                        Task {
                                            let ok = await LabNotifications.requestPermission()
                                            lab.notificationsEnabled = ok
                                            permission = await LabNotifications.status()
                                        }
                                    } else { lab.notificationsEnabled = false }
                                })) {
                                label("Robot alerts", "A note when a live-test robot paper-buys or paper-sells, and a daily reminder after the market's daily close.")
                            }.tint(Theme.orange)
                            if permission == .denied {
                                Text("Notifications are switched off for this app in the iPhone's Settings.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.red)
                            }
                            Text("Robots decide once a day, at the daily close (00:00 UTC). iOS decides when an app may check in the background, so an alert can arrive late; the result is always there when you open the app. Paper trading only, no real money.")
                                .font(.system(size: 11)).foregroundStyle(Theme.dim)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Privacy")
                            Text("Everything in the Lab stays on this phone: your rules, reports and live tests. Prices come from a public exchange feed. There is no account.")
                                .font(.system(size: 12)).foregroundStyle(Theme.dim)
                            Toggle(isOn: $shareCounts) {
                                label("Share anonymous usage counts", "Counts only, like \"someone tapped the book link\". No device ID, no IP address, nothing personal. Turn off and the app sends nothing.")
                            }.tint(Theme.orange)
                        }
                    }
                    WebsiteCallout()
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { permission = await LabNotifications.status() }
        }
        .preferredColorScheme(.dark)
    }

    private func label(_ t: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
            Text(d).font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
    }
}
