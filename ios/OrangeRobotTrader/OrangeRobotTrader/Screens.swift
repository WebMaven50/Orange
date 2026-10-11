import SwiftUI
import OrangeRobotKit

struct IntroView: View {
    let model: GameModel
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image("BookCover")
                .resizable().scaledToFit().frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Theme.orange.opacity(0.4), radius: 24)
            Text("ORANGE ROBOT TRADER")
                .font(.system(size: 24, weight: .black)).foregroundStyle(Theme.orange)
            Text("BITCOIN TRADING SIMULATOR")
                .font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(Theme.dim)
                .padding(.top, -10)
            (Text("You've got ") + Text("$100,000").bold().foregroundColor(.white)
             + Text(". Pick a moment in Bitcoin's real history — or let fate choose. Trade your way to ")
             + Text("$1,000,000").bold().foregroundColor(Theme.orange) + Text(" before you go broke."))
                .font(.system(size: 14)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            Button { model.showStartPicker = true } label: {
                Text("START TRADING").font(.system(size: 16, weight: .black)).tracking(1)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.orange, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
            }.padding(.horizontal, 32)
            HStack(spacing: 28) {
                Button { model.showLeaderboard = true; Activity.track(.leaderboardOpen) } label: {
                    Text("🏆 Leaderboard").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.gold)
                }
                Button { model.showPrologue = true } label: {
                    Text("🎧 Hear the prologue").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.orange)
                }
            }
            if model.totalSats > 0 {
                Text("⚡ \(model.totalSats) virtual sats banked").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.gold)
            }
            Spacer()
            Text("A game. Virtual money and historical prices — not financial advice.")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Link(destination: Theme.bookURL) {
                Text("A game from the novel THE ORANGE ROBOT by V.J. Alden — theorangerobot.com")
                    .font(.system(size: 11)).multilineTextAlignment(.center)
                    .foregroundStyle(Theme.dim).padding(.horizontal, 32)
            }
            .simultaneousGesture(TapGesture().onEnded { Activity.track(.bookLinkTap) })
            Button("How does the data work?") { model.showInfo = true }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.orange)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

struct EndView: View {
    let model: GameModel
    var body: some View {
        let s = model.session
        let outcome = s.outcome ?? .cashout
        let title = outcome == .win ? "TO THE MOON!" : outcome == .cashout ? "CASHED OUT" : "REKT — LIQUIDATED"
        let color = outcome == .win ? Theme.gold : outcome == .cashout ? Theme.orange : Theme.red
        let ret = (s.equity - GameSession.startCash) / GameSession.startCash * 100

        ScrollView {
            VStack(spacing: 16) {
                Text(outcome == .win ? "🚀" : outcome == .cashout ? "💰" : "💀").font(.system(size: 64))
                Text(title).font(.system(size: 22, weight: .black)).foregroundStyle(color)
                Text(Fmt.usd(max(0, s.equity)))
                    .font(.system(size: 36, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    box("Days Traded", "\(s.daysPlayed)")
                    box("Trades Made", "\(s.trades)")
                    box("Best Equity", Fmt.compact(s.bestEquity))
                    box("Return", String(format: "%@%.1f%%", ret >= 0 ? "+" : "", ret))
                }.padding(.horizontal, 24)

                if s.isRandomStart {
                    Text("+\(s.satsEarned) VIRTUAL SATS ⚡")
                        .font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.gold)
                } else {
                    VStack(spacing: 4) {
                        Text("PRACTICE RUN").font(.system(size: 14, weight: .heavy)).tracking(1)
                            .foregroundStyle(Theme.orange)
                        Text("You chose the start date, so this run doesn't earn virtual sats or count for the leaderboard. Play a random date to compete.")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    }.padding(.horizontal, 28)
                }

                // Leaderboard
                VStack(spacing: 10) {
                    Text("🏆 TOP TRADERS").font(.system(size: 13, weight: .heavy)).tracking(1)
                        .foregroundStyle(Theme.gold)
                    LeaderboardList(limit: 5, refreshKey: model.savedInitials, highlight: model.savedInitials)
                    if s.isRandomStart { SaveScoreButton(model: model) }
                }
                .padding(14)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)

                // Book hook
                VStack(spacing: 10) {
                    Text(outcome == .bust ? "The robot saw this coming."
                                          : "The robot never trades on a hunch.")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Read how the story really goes.")
                        .font(.system(size: 13)).foregroundStyle(Theme.dim)
                    Button { model.showPrologue = true } label: {
                        Text("🎧 HEAR THE PROLOGUE")
                            .font(.system(size: 13, weight: .black)).tracking(0.5)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Theme.text)
                    }
                    Link(destination: Theme.bookURL) {
                        Text("GET THE ORANGE ROBOT →")
                            .font(.system(size: 13, weight: .black)).tracking(0.5)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.orange, lineWidth: 1.5))
                            .foregroundStyle(Theme.orange)
                    }
                    .simultaneousGesture(TapGesture().onEnded { Activity.track(.bookLinkTap) })
                }
                .padding(16)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)

                Button { model.showStartPicker = true } label: {
                    Text("PLAY AGAIN").font(.system(size: 16, weight: .black)).tracking(1)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }.padding(.horizontal, 24)
            }
            .padding(.vertical, 32)
        }
        .background(Theme.bg)
    }

    private func box(_ l: String, _ v: String) -> some View {
        VStack(spacing: 4) {
            Text(l.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.5).foregroundStyle(Theme.dim)
            Text(v).font(.system(size: 17, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Activity.settingKey) private var shareCounts = true
    @AppStorage("live_flicker") private var liveFlicker = true
    @AppStorage(Feedback.hapticsKey) private var haptics = true
    @AppStorage(Feedback.soundKey) private var sound = true
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    para("Daily & weekly candles are 100% real.",
                         "Every 1D and 1W candle comes from actual historical Bitcoin prices (2010–2024). Nothing is invented at that scale.")
                    para("15m / 1H / 4H candles are simulated within real bounds.",
                         "Minute-level history isn't available, so intraday movement is generated — but it always starts at the previous real close, touches the real high and low, and ends at the real close.")
                    para("Trading.",
                         "A 0.26% fee applies to every order, like a real exchange. Selling more BTC than you hold opens a short position — powerful, but liquidation is real.")
                    para("Sleep.",
                         "Passes 8 game-hours in 3 real seconds. Price keeps moving, and your resting limit, stop and trailing orders still fill while you sleep.")
                    para("Cash Out.",
                         "You don't have to wait for $1M or bankruptcy — cash out anytime to lock in your equity. You earn 1 virtual sat per dollar of profit.")
                    para("About virtual sats.",
                         "Virtual sats are game points. They have no cash value and cannot be redeemed for Bitcoin or money. All money in this game is simulated and prices are historical — it is a game, not financial advice.")
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $haptics) {
                            Text("Haptics").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.orange)
                        }.tint(Theme.orange)
                        Toggle(isOn: $sound) {
                            Text("Sound effects").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.orange)
                        }.tint(Theme.orange)
                        Text("Small taps and tones for trades, breaking news and results. Sounds follow your phone's silent switch.")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $liveFlicker) {
                            Text("Live price flicker")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.orange)
                        }.tint(Theme.orange)
                        Text("Adds small tick-by-tick movement between the day's real prices so the market feels alive, especially at Actual speed. The day's real open, high, low and close never change. Applies to your next run.")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $shareCounts) {
                            Text("Share anonymous usage counts")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.orange)
                        }.tint(Theme.orange)
                        Text("Counts only — like \"someone played the prologue\". No account, no device ID, no IP address, no location, no personal data of any kind is collected or stored. Turn this off and the app sends nothing.")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                    para("Order types.",
                         "Market fills instantly. Limit fills when price reaches your level. Stop triggers at your level and fills at market. Trailing stop follows the best price by a percentage.")
                }.padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("How the market works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func para(_ h: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(h).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.orange)
            Text(b).font(.system(size: 14)).foregroundStyle(Theme.text)
        }
    }
}
