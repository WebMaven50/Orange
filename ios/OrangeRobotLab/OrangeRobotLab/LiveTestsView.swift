import SwiftUI
import OrangeRobotKit

struct LiveTestsView: View {
    @Environment(LabModel.self) private var lab
    @State private var choice: Strategy?
    @State private var horizon = 7
    @State private var confirm = false

    private var options: [Strategy] {
        var seen = Set<String>(); var out: [Strategy] = []
        for s in lab.saved + Strategy.templates where seen.insert(s.name).inserted { out.append(s) }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🛰 Live tests").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.text)
                        Text("Lock a robot's rules, then watch how it does on days that haven't happened yet. Nothing about the future can be tuned in, which makes this the fairest test there is. It's paper trading: no real money.")
                            .font(.system(size: 13)).foregroundStyle(Theme.dim)
                    }
                }

                startCard

                if !lab.liveTests.isEmpty {
                    SectionLabel("Your live tests")
                    ForEach(lab.liveTests) { t in
                        NavigationLink { LiveTestDetailView(testID: t.id) } label: { row(t) }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Live tests")
        .navigationBarTitleDisplayMode(.inline)
        .task { await lab.refreshLive() }
        .confirmationDialog("Start this live test?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Lock the rules and start") {
                if let c = choice { lab.startLiveTest(c, horizon: horizon) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The rules can't be changed once it starts. It will be judged on the next \(horizon) days.")
        }
    }

    private var startCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Start a new one")
                Text("Which robot?").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                ForEach(options, id: \.name) { s in
                    Button { choice = s } label: {
                        HStack(alignment: .top) {
                            Image(systemName: choice?.name == s.name ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(choice?.name == s.name ? Theme.orange : Theme.dim)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                Text(s.decisionSummary)
                                    .font(.system(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.leading)
                            }
                            Spacer()
                        }
                    }
                }
                Text("For how long?").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Picker("", selection: $horizon) {
                    Text("7 days").tag(7); Text("30").tag(30); Text("60").tag(60); Text("90").tag(90)
                }.pickerStyle(.segmented)
                if horizon < 30 {
                    Text("🏃 Sprint: a quick first look. A daily robot makes only a few decisions in a week, so this is mostly luck.")
                        .font(.system(size: 11)).foregroundStyle(Theme.orange)
                } else {
                    Text("🏁 Marathon: the long-run test. Rules that stay ahead of just holding over \(horizon) days have really withstood time.")
                        .font(.system(size: 11)).foregroundStyle(Theme.gold)
                }
                Button { confirm = true } label: {
                    Text("START LIVE TEST").font(.system(size: 15, weight: .black)).tracking(0.5)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
                }
                .disabled(choice == nil).opacity(choice == nil ? 0.4 : 1)
            }
        }
    }

    private func row(_ t: LiveTest) -> some View {
        let s = lab.liveStatus(t)
        let r = s.robotEquity.last.map { $0 / t.startCash - 1 }
        let h = s.holdEquity.last.map { $0 / t.startCash - 1 }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                Spacer()
                Text((t.track == .sprint ? "🏃 " : "🏁 ") + statusText(s)).font(.system(size: 10, weight: .black)).tracking(0.5)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((s.phase == .finished ? Theme.gold : Theme.green).opacity(0.18), in: Capsule())
                    .foregroundStyle(s.phase == .finished ? Theme.gold : Theme.green)
            }
            if let r, let h {
                Text("Robot \(Money.pct(r, digits: 1)) · holding \(Money.pct(h, digits: 1))")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            } else {
                Text("Waiting for today's close…").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            Text("Day \(s.elapsedDays) of \(t.horizonDays) · started \(Fmt.date(Date(timeIntervalSince1970: Double(t.startDay) * 86_400)))")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func statusText(_ s: LiveStatus) -> String {
        switch s.phase {
        case .waitingForFirstClose: return "STARTING"
        case .running: return "RUNNING"
        case .finished: return "DONE"
        }
    }
}

struct LiveTestDetailView: View {
    @Environment(LabModel.self) private var lab
    @Environment(\.dismiss) private var dismiss
    let testID: UUID
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let t = lab.liveTests.first(where: { $0.id == testID }) {
                content(t, lab.liveStatus(t))
            } else {
                Text("This test was removed.").foregroundStyle(Theme.dim)
            }
        }
        .background(Theme.bg)
        .navigationTitle("Live test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await lab.refreshLive() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(lab.refreshing)
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
            }
        }
        .confirmationDialog("Remove this live test?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { lab.deleteLiveTest(testID); dismiss() }
            Button("Keep it", role: .cancel) {}
        }
        .task { await lab.refreshLive() }
    }

    @ViewBuilder
    private func content(_ t: LiveTest, _ s: LiveStatus) -> some View {
        let r = s.robotEquity.last.map { $0 / t.startCash - 1 }
        let h = s.holdEquity.last.map { $0 / t.startCash - 1 }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(t.name).font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.text)
                            Spacer()
                            if lab.refreshing { ProgressView().tint(Theme.orange) }
                        }
                        ProgressView(value: Double(s.elapsedDays), total: Double(t.horizonDays)).tint(Theme.orange)
                        Text(s.phase == .finished ? "Finished after \(t.horizonDays) days."
                             : "Day \(s.elapsedDays) of \(t.horizonDays). \(t.horizonDays - s.elapsedDays) to go.")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                SectionLabel("Robot")
                                Text(r.map { Money.pct($0, digits: 1) } ?? "–")
                                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                                    .foregroundStyle((r ?? 0) >= 0 ? Theme.green : Theme.red)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                SectionLabel("Just holding")
                                Text(h.map { Money.pct($0, digits: 1) } ?? "–")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(Theme.dim)
                            }
                        }
                        if t.horizonDays <= 14 || s.elapsedDays < 10 {
                            Text("Early days: with so little time and few trades, this tells you very little yet.")
                                .font(.system(size: 11)).foregroundStyle(Theme.orange)
                        }
                    }
                }

                if s.robotEquity.count > 1 {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 14) {
                                dot(Theme.orange, "Your robot"); dot(Theme.dim, "Just holding")
                            }
                            EquityChart(robot: s.robotEquity, hold: s.holdEquity).frame(height: 150)
                        }
                    }
                }

                if let robot = s.robot, let hist = s.history, let days = s.days {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Trades (\(robot.trades.count))")
                            if robot.trades.isEmpty {
                                Text("No trades yet. The robot is waiting for its signal.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
                            }
                            ForEach(robot.trades) { tr in
                                HStack {
                                    Text("\(Fmt.date(Backtester(history: hist).date(forDay: tr.entryDay))) → \(Fmt.date(Backtester(history: hist).date(forDay: tr.exitDay)))")
                                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Text(String(format: "%+.1f%%", tr.returnPercent))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(tr.returnPercent >= 0 ? Theme.green : Theme.red)
                                }
                            }
                        }
                    }
                    NavigationLink {
                        ReplayView(strategy: t.strategy,
                                   span: DateSpan(start: Date(), end: Date()),
                                   engine: Backtester(history: hist), fixedRange: days, startCash: t.startCash)
                    } label: {
                        Label("Watch it day by day", systemImage: "play.circle.fill")
                            .font(.system(size: 14, weight: .black))
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Theme.orange, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Locked rules")
                        if let d = t.strategy.dca {
                            Text("BUY \(d.shortAmountText) \(d.label), whatever the price")
                                .font(.system(size: 12)).foregroundStyle(Theme.green)
                        }
                        ForEach(t.strategy.entry, id: \.self) {
                            Text("BUY when " + $0.summary).font(.system(size: 12)).foregroundStyle(Theme.green)
                        }
                        ForEach(t.strategy.exit, id: \.self) {
                            Text("SELL when " + $0.summary).font(.system(size: 12)).foregroundStyle(Theme.red)
                        }
                        if let v = t.strategy.stopLossPercent { Text("Stop loss \(String(format: "%g", v))%").font(.system(size: 12)).foregroundStyle(Theme.text) }
                        if let v = t.strategy.takeProfitPercent { Text("Take profit \(String(format: "%g", v))%").font(.system(size: 12)).foregroundStyle(Theme.text) }
                        if let v = t.strategy.trailingStopPercent { Text("Trailing stop \(String(format: "%g", v))%").font(.system(size: 12)).foregroundStyle(Theme.text) }
                        Divider().overlay(Theme.line)
                        HStack {
                            Image(systemName: t.isIntact ? "lock.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(t.isIntact ? Theme.green : Theme.red)
                            Text(t.isIntact ? "Rules unchanged since \(t.createdAt.formatted(date: .abbreviated, time: .shortened))"
                                            : "These rules no longer match what was locked")
                                .font(.system(size: 11)).foregroundStyle(Theme.dim)
                        }
                        Text("Fingerprint \(t.fingerprint.prefix(16))…")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.dim)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let e = lab.refreshError { Text(e).font(.system(size: 11)).foregroundStyle(Theme.orange) }
                    if let u = lab.candlesUpdated, let src = lab.candleSource {
                        Text("Prices from \(src), updated \(u.formatted(date: .omitted, time: .shortened)). Only finished UTC days count. Paper trading with 0.26% fees and 0.1% slippage; not financial advice.")
                            .font(.system(size: 10)).foregroundStyle(Theme.dim)
                    }
                }
            }
            .padding(16)
        }
    }

    private func dot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
        }
    }
}
