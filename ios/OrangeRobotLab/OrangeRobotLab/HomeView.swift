import SwiftUI
import OrangeRobotKit

struct HomeView: View {
    @Environment(LabModel.self) private var lab

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("🤖").font(.system(size: 54))
                    Text("ORANGE ROBOT LAB").font(.system(size: 22, weight: .black)).tracking(1)
                        .foregroundStyle(Theme.orange)
                    Text("Teach the robot when to buy and sell,\nthen see how it would have done.")
                        .font(.system(size: 14)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                NavigationLink {
                    BuilderView(strategy: Strategy(name: "My rules", entry: [.rsiBelow(period: 14, level: 30)],
                                                   exit: [.rsiAbove(period: 14, level: 55)],
                                                   stopLossPercent: 10, positionPercent: 100))
                } label: {
                    bigCard(emoji: "🛠", title: "Build my own rules",
                            text: "Choose the signals, stop-losses, take-profits and limit buys, then run them over any stretch of Bitcoin history.")
                }
                NavigationLink { FinderView() } label: {
                    bigCard(emoji: "🔎", title: "Find me rules",
                            text: "Pick a period in history. The robot tries thousands of rule sets on it, then tests the best ones on time they've never seen.")
                }

                if !lab.saved.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("My robots")
                        ForEach(lab.saved, id: \.name) { s in
                            NavigationLink { BuilderView(strategy: s) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                                        Text(s.entry.map(\.summary).joined(separator: " and "))
                                            .font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
                                }
                                .padding(14)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }

                Text("History simulations only. Past results don't predict the future, and nothing here is financial advice. Intraday movement isn't used: the robot trades on real daily candles.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(18)
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
    }

    private func bigCard(emoji: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(emoji).font(.system(size: 34))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.text)
                Text(text).font(.system(size: 13)).foregroundStyle(Theme.dim).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }
}
