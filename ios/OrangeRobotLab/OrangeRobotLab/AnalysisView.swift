import SwiftUI
import OrangeRobotKit

/// "What did the rules do right and wrong?" for one test.
struct AnalysisView: View {
    @Environment(LabModel.self) private var lab
    let strategy: Strategy
    let span: DateSpan

    var body: some View {
        let range = lab.range(for: span)
        let robot = lab.backtester.run(strategy, days: range)
        let hold = lab.backtester.buyAndHold(days: range)
        let a = Analyzer.analyze(strategy: strategy, result: robot, hold: hold, history: lab.backtester.history)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScoreBanner(score: a.score, headline: a.headline)

                let right = a.findings.filter { $0.kind == .right }
                let wrong = a.findings.filter { $0.kind == .wrong }
                let notes = a.findings.filter { $0.kind == .note }

                if !right.isEmpty { group("What it did right", "✅", Theme.green, right) }
                if !wrong.isEmpty { group("What cost it", "⚠️", Theme.red, wrong) }
                if !notes.isEmpty { group("Worth knowing", "ℹ️", Theme.dim, notes) }
                if right.isEmpty && wrong.isEmpty && notes.isEmpty {
                    Card { Text("Nothing stood out in this period.").font(.system(size: 13)).foregroundStyle(Theme.dim) }
                }

                if !a.suggestions.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Things to try")
                            ForEach(Array(a.suggestions.enumerated()), id: \.offset) { _, t in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("→").foregroundStyle(Theme.orange)
                                    Text(t).font(.system(size: 13)).foregroundStyle(Theme.text)
                                }
                            }
                        }
                    }
                }

                Text("Score: 0 = same money as holding · +100 = 100% more money than holding · −50 = 50% less. This describes what happened in this period only; it doesn't predict anything and isn't financial advice.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ title: String, _ icon: String, _ color: Color, _ items: [Finding]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(icon) \(title.uppercased())").font(.system(size: 11, weight: .heavy)).tracking(1)
                .foregroundStyle(color)
            ForEach(items) { f in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(f.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                        Spacer()
                        if let p = f.points, abs(p) >= 1 {
                            Text(String(format: "%+.0f pts", p)).font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(p >= 0 ? Theme.green : Theme.red)
                        }
                    }
                    Text(f.detail).font(.system(size: 12)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 8)
                }
            }
        }
    }
}

/// Big "score vs holding" readout.
struct ScoreBanner: View {
    let score: Double
    let headline: String

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 2) {
                    Text(Score.label(score))
                        .font(.system(size: 40, weight: .black, design: .monospaced))
                        .foregroundStyle(abs(score) < 3 ? Theme.dim : (score > 0 ? Theme.green : Theme.red))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("SCORE VS HOLDING").font(.system(size: 8, weight: .heavy)).tracking(1).foregroundStyle(Theme.dim)
                }
                .frame(width: 120)
                Text(headline).font(.system(size: 13)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
