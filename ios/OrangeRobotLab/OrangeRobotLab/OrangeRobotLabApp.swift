import SwiftUI
import UserNotifications
import BackgroundTasks

@main
struct OrangeRobotLabApp: App {
    @State private var lab = LabModel()
    private let notificationDelegate = LabNotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        BGTaskScheduler.shared.register(forTaskWithIdentifier: LabNotifications.refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            let work = Task { @MainActor in
                let model = LabModel()            // loads the saved tests from disk
                await model.backgroundRefresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { HomeView() }
                .environment(lab)
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
        }
    }
}
