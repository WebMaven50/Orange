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

/// Sends the finished run to the Orange Robot Vault on theorangerobot.com:
/// adds the run's virtual sats to the player's total and puts the score on the
/// shared leaderboard.
struct SaveScoreButton: View {
    @Bindable var model: GameModel
    @State private var asking = false
    @State private var draft = ""
    @Environment(\.openURL) private var openURL

    private static let vaultURL = URL(string: "https://theorangerobot.com/games/")!

    var body: some View {
        let sats = model.session.satsEarned
        VStack(spacing: 10) {
            if model.savedInitials == nil {
                Text(sats > 0
                     ? "Send your \(sats) virtual sats to the Orange Robot Vault and your score to the leaderboard. Get your name on theorangerobot.com."
                     : "Put your score on the Orange Robot leaderboard and get your name on theorangerobot.com.")
                    .font(.system(size: 12)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            }

            Button {
                if model.savedInitials != nil {
                    openURL(Self.vaultURL)
                } else {
                    draft = model.lastInitials
                    asking = true
                }
            } label: {
                Text(label).font(.system(size: 14, weight: .heavy)).tracking(0.5)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(model.savedInitials == nil ? Theme.orange : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(model.savedInitials == nil ? Theme.orange : Theme.green, lineWidth: 1.5))
                    .foregroundStyle(model.savedInitials == nil ? Color.black : Theme.green)
            }
            .disabled(model.isSaving)

            if let who = model.savedInitials {
                VStack(spacing: 4) {
                    Text("Sent as \(who) ✓").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.green)
                    if let r = model.savedRank {
                        Text("Leaderboard rank #\(r)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.gold)
                    }
                    if let v = model.vaultTotal {
                        Text("Your Vault total: \(v.formatted()) virtual sats ⚡")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.gold)
                    }
                    Text("Tap the button to see the Vault board on theorangerobot.com.")
                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
            }
            if let e = model.saveError {
                Text(e).font(.system(size: 11)).foregroundStyle(Theme.red).multilineTextAlignment(.center)
            }
        }
        .alert("Your initials", isPresented: $asking) {
            TextField("ABC", text: $draft)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: draft) { _, v in draft = String(LeaderboardClient.cleanInitials(v) ?? "") }
            Button("Send") { Task { await model.saveScore(initials: draft) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("1–3 letters or numbers. This is shown publicly on theorangerobot.com. Nothing else about you is sent.")
        }
    }

    private var label: String {
        if model.savedInitials != nil { return "SEE THE VAULT ON THE WEBSITE →" }
        if model.isSaving { return "SENDING…" }
        return model.session.satsEarned > 0 ? "⚡ SEND MY SATS TO THE VAULT" : "🏆 PUT MY SCORE ON THE BOARD"
    }
}
