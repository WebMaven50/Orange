import SwiftUI
import OrangeRobotKit

struct FinderView: View {
    @Environment(LabModel.self) private var lab
    @State private var span = DateSpan.presets[2].1
    @State private var tries = 1_500
    @State private var running = false
    @State private var progress = 0.0
    @State private var results: [Candidate] = []
    @State private var finishedSpan: DateSpan?
    @State private var task: Task<Void, Never>?
    @State private var open: Strategy?
    @State private var naming: Candidate?
    @State private var nameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Practice period")
                        Text("The robot studies this stretch of history and looks for rules that would have done well in it.")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                        DateSpanPicker(span: $span)
                        SectionLabel("How many ideas to try")
                        Picker("", selection: $tries) {
                            Text("500").tag(500); Text("1,500").tag(1_500); Text("5,000").tag(5_000)
                        }.pickerStyle(.segmented)
                    }
                }

                Button {
                    running ? cancel() : start()
                } label: {
                    Text(running ? "STOP" : "FIND RULES").font(.system(size: 16, weight: .black)).tracking(1)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(running ? Theme.panel2 : Theme.orange, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(running ? Theme.text : Color.black)
                }
                if running {
                    ProgressView(value: progress).tint(Theme.orange)
                }

                if let s = finishedSpan, !running {
                    if results.isEmpty {
                        Card { Text("Nothing trustworthy turned up for that period (too few trades, or too short). Try a longer stretch.")
                            .font(.system(size: 13)).foregroundStyle(Theme.text) }
                    } else {
                        Text("Best rules for \(Fmt.date(s.start)) – \(Fmt.date(s.end))")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
                        ForEach(results) { c in candidateCard(c) }
                        Text("A rule set that worked in the past is not a promise. That is why each one is also tried on later time and on other years it was never tuned on.")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Find rules")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $open) { strategy in
            BuilderView(strategy: strategy)
        }
        .alert("Name your robot", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Robot name", text: $nameDraft)
            Button("Save") {
                if let c = naming {
                    var st = c.strategy
                    let n = nameDraft.trimmingCharacters(in: .whitespaces)
                    st.name = n.isEmpty ? lab.uniqueName(c.strategy.name) : n
                    lab.save(st)
                }
                naming = nil
            }
            Button("Cancel", role: .cancel) { naming = nil }
        } message: {
            Text("Pick a name you'll recognise. Reports and live tests use it.")
        }
        .onDisappear { task?.cancel() }
    }

    // MARK: Running

    private func start() {
        let spanNow = span
        let range = lab.range(for: spanNow)
        guard range.count >= 60 else { results = []; finishedSpan = spanNow; return }
        running = true; progress = 0; results = []
        var req = FinderRequest(trainDays: range)
        req.candidates = tries
        req.keep = 6
        let history = lab.backtester.history
        task = Task.detached(priority: .userInitiated) {
            let finder = RuleFinder(backtester: Backtester(history: history))
            let found = finder.find(req,
                                    progress: { p in Task { @MainActor in progress = p } },
                                    isCancelled: { Task.isCancelled })
            await MainActor.run {
                if !Task.isCancelled {
                    results = found; finishedSpan = spanNow
                    lab.recordSearch(span: spanNow, tries: req.candidates, candidates: found)
                }
                running = false
            }
        }
    }

    private func cancel() {
        task?.cancel()
        running = false
    }

    // MARK: Result cards

    private func candidateCard(_ c: Candidate) -> some View {
        let color: Color = {
            switch c.verdict {
            case .holdsUp: return Theme.green
            case .steadier: return Theme.gold
            case .mixed: return Theme.orange
            case .fellApart: return Theme.red
            }
        }()
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(c.strategy.name).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(c.verdict.title.uppercased())
                        .font(.system(size: 9, weight: .black)).tracking(0.6)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(color.opacity(0.18), in: Capsule())
                        .foregroundStyle(color)
                }
                Text(describe(c.strategy)).font(.system(size: 12)).foregroundStyle(Theme.dim)
                if let v = c.validation, let vh = c.validationBuyAndHold {
                    let sc = Score.vsHold(robotReturn: v.totalReturn, holdReturn: vh.totalReturn)
                    HStack(spacing: 6) {
                        Text("Score on unseen time").font(.system(size: 11)).foregroundStyle(Theme.dim)
                        Text(Score.label(sc)).font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundStyle(abs(sc) < 3 ? Theme.dim : (sc > 0 ? Theme.green : Theme.red))
                    }
                }

                VStack(spacing: 6) {
                    row("Practice period", c.train.totalReturn, hold: c.trainBuyAndHold.totalReturn)
                    if let v = c.validation, let vh = c.validationBuyAndHold, let range = c.validationDays {
                        row("Next \(range.count > 360 ? "year" : "stretch") (unseen)", v.totalReturn, hold: vh.totalReturn)
                    }
                    if let r = c.robustness {
                        HStack {
                            Text("Other years").font(.system(size: 12)).foregroundStyle(Theme.dim)
                            Spacer()
                            Text("profitable in \(Int(r.positiveShare * 100))% · beat holding in \(Int(r.beatsHoldShare * 100))%")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                        }
                    }
                }
                Text(c.verdict.explanation).font(.system(size: 11)).foregroundStyle(color)
                if c.train.trades < 6 {
                    Text("⚠️ Only \(c.train.trades) trades in the practice period, so luck could explain a lot.")
                        .font(.system(size: 11)).foregroundStyle(Theme.orange)
                }
                HStack(spacing: 10) {
                    Button { open = c.strategy } label: {
                        Text("Open in builder").font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Theme.orange, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.black)
                    }
                    Button {
                        nameDraft = lab.uniqueName(c.strategy.name)
                        naming = c
                    } label: {
                        Text(lab.saved.contains(where: { $0.dropName == c.strategy.dropName }) ? "Saved ✓" : "Save robot")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                            .foregroundStyle(Theme.text)
                    }
                }
            }
        }
    }

    private func row(_ title: String, _ r: Double, hold: Double) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.dim)
            Spacer()
            Text(Money.pct(r)).font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(r >= 0 ? Theme.green : Theme.red)
            Text("(holding \(Money.pct(hold)))").font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
    }

    private func describe(_ s: Strategy) -> String {
        var parts: [String] = []
        if let d = s.dca { return "DCA: buys \(d.shortAmountText) \(d.label)" }
        parts.append("Buy when " + s.entry.map(\.summary).joined(separator: " and "))
        if !s.exit.isEmpty { parts.append("sell when " + s.exit.map(\.summary).joined(separator: " or ")) }
        if let v = s.stopLossPercent { parts.append("stop loss \(String(format: "%g", v))%") }
        if let v = s.takeProfitPercent { parts.append("take profit \(String(format: "%g", v))%") }
        if let v = s.trailingStopPercent { parts.append("trailing stop \(String(format: "%g", v))%") }
        if let v = s.limitEntryDiscountPercent { parts.append("limit buy \(String(format: "%g", v))% below") }
        parts.append("\(Int(s.positionPercent))% of cash")
        return parts.joined(separator: " · ")
    }
}
