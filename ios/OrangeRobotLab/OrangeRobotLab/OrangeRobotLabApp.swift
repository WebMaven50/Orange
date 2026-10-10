import SwiftUI

@main
struct OrangeRobotLabApp: App {
    @State private var lab = LabModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack { HomeView() }
                .environment(lab)
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
        }
    }
}
