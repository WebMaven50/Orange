import SwiftUI

@main
struct OrangeRobotTraderApp: App {
    @State private var model = GameModel()

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
        .sheet(isPresented: $model.showLeaderboard) { LeaderboardSheet() }
        .sheet(isPresented: $model.showPrologue) { PrologueView() }
        .sheet(isPresented: $model.showNews) { NewsView(model: model).presentationDetents([.large]) }
        .sheet(isPresented: $model.showPositions) {
            PositionsView(model: model).presentationDetents([.large])
        }
    }
}
