import UIKit
import SwiftUI

@main
struct OrangeRobotTraderApp: App {
    @State private var model = GameModel()
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Bindable var model: GameModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch model.phase {
            case .intro: IntroView(model: model)
            case .playing: TradingView(model: model)
            case .ended: EndView(model: model)
            }
            if let q = model.quote {
                QuoteCardView(quote: q) { model.dismissQuote() }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .onAppear { Activity.track(.appOpen) }
        .onChange(of: model.anySheetOpen) { _, open in
            if open { model.autoPause() } else { model.autoResume() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pauseForBackground() }
        }
        .sheet(isPresented: $model.showStartPicker) {
            StartPickerView { choice in model.startNewRun(choice) }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $model.showInfo) { InfoView() }
        .alert("Stay in touch?", isPresented: $model.showNotifyPrompt) {
            Button("Yes, keep me posted") { Task { await GameNotifications.answerPrompt(yes: true) } }
            Button("Not now", role: .cancel) { Task { await GameNotifications.answerPrompt(yes: false) } }
        } message: {
            Text("Get a rare message when there's something worth your time, like news, a podcast or a deal. Also an alert when Bitcoin moves 5% in a day. You can change this anytime in Info.")
        }
        .sheet(isPresented: $model.showLeaderboard) { LeaderboardSheet() }
        .sheet(isPresented: $model.showPrologue) { PrologueView() }
        .sheet(isPresented: $model.showNews) { NewsView(model: model).presentationDetents([.large]) }
        .sheet(isPresented: $model.showPositions) {
            PositionsView(model: model).presentationDetents([.large])
        }
    }
}
