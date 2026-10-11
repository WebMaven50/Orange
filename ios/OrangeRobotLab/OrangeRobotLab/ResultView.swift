import SwiftUI
import OrangeRobotKit

/// Shows how a rule set would have done over a period, next to simply holding.
struct ResultView: View {
    @Environment(LabModel.self) private var lab
    let strategy: Strategy
    let span: DateSpan

    var body: some View {
        let range = lab.range(for: span)
        let robot = lab.backtester.run(strategy, days: range)
        let hold = lab.backtester.buyAndHold(days: range)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline(robot, hold)
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            legend(Theme.orange, "Your robot")
                            legend(Theme.dim, "Just holding")
                            Spacer()
                        }
                        EquityChart(robot: robot.equity, hold: hold.equity)
                            .frame(height: 190)
                        HStack {
                            Text(Fmt.date(lab.backtester.date(forDay: range.lowerBound)))
                            Spacer()
                            Text(Fmt.date(lab.backtester.date(forDay: max(range.upperBound - 1, 0))))
                        }
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.dim)
                    }
                }
                NavigationLink {
                    ReplayView(strategy: strategy, span: span)
                } label: {
                    Label("WATCH THE ROBOT TRADE", systemImage: "play.circle.fill")
                        .font(.system(size: 15, weight: .black)).tracking(0.5)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                statsGrid(robot.metrics, hold.metrics)
                tradeList(robot.trades)
                Text("Signals are read at each day's close and traded at the next open. Stops and targets use each day's real high and low, and a stop wins if both are touched in one day. Costs: 0.26% fee plus 0.1% slippage. Past results don't predict the future.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            .padding(16)
        }
        .background(Theme.bg)
        .onAppear {
            // Every test goes in the notebook automatically.
            let range = lab.range(for: span)
            let r = lab.backtester.run(strategy, days: range)
            let h = lab.backtester.buyAndHold(days: range)
            lab.recordTest(strategy: strategy, span: span, result: r.metrics, hold: h.metrics)
        }
        .navigationTitle(strategy.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headline(_ r: BacktestResult, _ h: BacktestResult) -> some View {
        let diff = r.metrics.totalReturn - h.metrics.totalReturn
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("Your robot")
                        Text(Money.pct(r.metrics.totalReturn))
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .foregroundStyle(r.metrics.totalReturn >= 0 ? Theme.green : Theme.red)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        SectionLabel("Just holding")
                        Text(Money.pct(h.metrics.totalReturn))
                            .font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(Theme.dim)
                    }
                }
                Text(diff >= 0
                     ? "The robot beat holding by \(Int((diff * 100).rounded())) points."
                     : "Holding beat the robot by \(Int((-diff * 100).rounded())) points. The robot's worst fall was \(Int(r.metrics.maxDrawdown * 100))% against \(Int(h.metrics.maxDrawdown * 100))% for holding.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text)
                if r.metrics.trades < 6 {
                    Text("⚠️ Only \(r.metrics.trades) trade\(r.metrics.trades == 1 ? "" : "s"): too few to say much about skill.")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.orange)
                }
            }
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
        }
    }

    private func statsGrid(_ m: Metrics, _ h: Metrics) -> some View {
        let items: [(String, String, String)] = [
            ("Biggest fall", "\(Int(m.maxDrawdown * 100))%", "hold \(Int(h.maxDrawdown * 100))%"),
            ("Trades", "\(m.trades)", ""),
            ("Winning trades", m.trades == 0 ? "–" : "\(Int(m.winRate * 100))%", ""),
            ("Time invested", "\(Int(m.exposure * 100))%", ""),
            ("Per year", Money.pct(m.annualizedReturn), "hold \(Money.pct(h.annualizedReturn))"),
            ("Steadiness", String(format: "%.2f", m.sharpe), "hold \(String(format: "%.2f", h.sharpe))"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { it in
                VStack(spacing: 3) {
                    Text(it.0.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.5).foregroundStyle(Theme.dim)
                    Text(it.1).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
                    Text(it.2).font(.system(size: 10)).foregroundStyle(Theme.dim).frame(height: 12)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func tradeList(_ trades: [Trade]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Trades (\(trades.count))")
            if trades.isEmpty {
                Text("The robot never found a signal in this period.").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            ForEach(trades.prefix(60)) { t in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Fmt.date(lab.backtester.date(forDay: t.entryDay))) → \(Fmt.date(lab.backtester.date(forDay: t.exitDay)))")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                        Text("\(Fmt.usd(t.entryPrice, decimals: 0)) → \(Fmt.usd(t.exitPrice, decimals: 0)) · \(t.reason.title)")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Text(String(format: "%+.1f%%", t.returnPercent))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(t.returnPercent >= 0 ? Theme.green : Theme.red)
                }
                .padding(10).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct EquityChart: View {
    let robot: [Double]
    let hold: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard robot.count > 1 else { return }
            let all = robot + hold
            let lo = all.min()!, hi = all.max()!
            let span = max(hi - lo, 1)
            func pt(_ i: Int, _ v: Double, _ n: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(max(n - 1, 1)),
                        y: size.height * CGFloat(1 - (v - lo) / span))
            }
            // starting-equity guide
            if let start = robot.first {
                var g = Path(); let y = pt(0, start, 2).y
                g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(g, with: .color(Theme.line), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            func line(_ v: [Double]) -> Path {
                var p = Path()
                for (i, x) in v.enumerated() { i == 0 ? p.move(to: pt(i, x, v.count)) : p.addLine(to: pt(i, x, v.count)) }
                return p
            }
            ctx.stroke(line(hold), with: .color(Theme.dim), lineWidth: 1.4)
            ctx.stroke(line(robot), with: .color(Theme.orange), lineWidth: 2)
        }
    }
}
