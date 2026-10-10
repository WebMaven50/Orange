import SwiftUI
import OrangeRobotKit

/// Top scores from the shared board. Reloads when `refreshKey` changes.
struct LeaderboardList: View {
    var limit = 10
    var refreshKey: String? = nil
    var highlight: String? = nil

    @State private var entries: [LeaderboardEntry] = []
    @State private var state: LoadState = .loading
    private enum LoadState { case loading, loaded, failed }

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .loading:
                Text("Loading…").foregroundStyle(Theme.dim).padding(.vertical, 18)
            case .failed:
                VStack(spacing: 8) {
                    Text("Leaderboard unavailable right now.").foregroundStyle(Theme.dim)
                    Button("Retry") { Task { await load() } }.foregroundStyle(Theme.orange)
                }.padding(.vertical, 14)
            case .loaded where entries.isEmpty:
                Text("No scores yet — be the first!").foregroundStyle(Theme.dim).padding(.vertical, 18)
            case .loaded:
                header
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in row(i + 1, e) }
            }
        }
        .font(.system(size: 13))
        .task(id: refreshKey) { await load() }
    }

    private var header: some View {
        HStack {
            Text("#").frame(width: 34, alignment: .leading)
            Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
            Text("EQUITY").frame(width: 92, alignment: .trailing)
            Text("SATS").frame(width: 84, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .bold)).tracking(0.5).foregroundStyle(Theme.dim)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func row(_ rank: Int, _ e: LeaderboardEntry) -> some View {
        let medal = rank == 1 ? "🥇" : rank == 2 ? "🥈" : rank == 3 ? "🥉" : "\(rank)"
        let mine = highlight != nil && e.initials == highlight
        return HStack {
            Text(medal).frame(width: 34, alignment: .leading)
            Text(e.initials).font(.system(size: 14, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.usd(e.score ?? 0, decimals: 0))
                .font(.system(size: 13, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 92, alignment: .trailing)
            Text(Self.sats(e.sats ?? 0) + " ⚡").foregroundStyle(Theme.gold)
                .font(.system(size: 12, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 84, alignment: .trailing)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(mine ? Theme.orange.opacity(0.18) : (rank <= 3 ? Theme.panel2 : Color.clear))
    }

    private static func sats(_ n: Double) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", n / 1_000) }
        return String(format: "%.0f", n)
    }

    private func load() async {
        state = .loading
        do {
            entries = try await LeaderboardClient().top(limit: limit)
            state = .loaded
        } catch {
            state = .failed
        }
    }
}

/// Full-screen board, opened from the intro.
struct LeaderboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LeaderboardList(limit: 25)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    Text("Shared with theorangerobot.com — scores from the app and the website are one board. Virtual sats are game points with no cash value.")
                        .font(.system(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }.padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("🏆 Top Traders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

/// Save-score control used on the end screen.
struct SaveScoreButton: View {
    @Bindable var model: GameModel
    @State private var asking = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 6) {
            Button {
                draft = model.lastInitials
                asking = true
            } label: {
                Text(label).font(.system(size: 14, weight: .heavy)).tracking(0.5)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(model.savedInitials == nil ? Theme.orange : Theme.green, lineWidth: 1.5))
                    .foregroundStyle(model.savedInitials == nil ? Theme.orange : Theme.green)
            }
            .disabled(model.savedInitials != nil || model.isSaving)

            if let e = model.saveError {
                Text(e).font(.system(size: 11)).foregroundStyle(Theme.red).multilineTextAlignment(.center)
            }
            if let r = model.savedRank {
                Text("You placed #\(r) on the board").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.gold)
            }
        }
        .alert("Enter your initials", isPresented: $asking) {
            TextField("ABC", text: $draft)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: draft) { _, v in draft = String(LeaderboardClient.cleanInitials(v) ?? "") }
            Button("Submit") { Task { await model.saveScore(initials: draft) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("1–3 letters or numbers. Shown on the public leaderboard.")
        }
    }

    private var label: String {
        if let i = model.savedInitials { return "SAVED AS \(i) ✓" }
        return model.isSaving ? "SAVING…" : "SAVE MY SCORE"
    }
}
