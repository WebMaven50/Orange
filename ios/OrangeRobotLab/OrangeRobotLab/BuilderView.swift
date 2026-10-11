import SwiftUI
import OrangeRobotKit

private struct EditTarget: Identifiable {
    enum Where { case entry, exit }
    let id = UUID()
    let list: Where
    let index: Int?       // nil = adding
}

struct BuilderView: View {
    @Environment(LabModel.self) private var lab
    @State var strategy: Strategy
    @State private var span = DateSpan.presets[2].1
    @State private var editing: EditTarget?
    @State private var showResult = false
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                templates
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Name your robot")
                        HStack {
                            Text("🤖")
                            TextField("e.g. Trend follower", text: $strategy.name)
                                .font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.text)
                                .textInputAutocapitalization(.words)
                            if !strategy.name.isEmpty {
                                Button { strategy.name = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim)
                                }
                            }
                        }
                        Text("Reports and live tests are named after your robot.")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("How does it decide?")
                        Picker("", selection: Binding(
                            get: { strategy.dca != nil },
                            set: { on in
                                if on { strategy.dca = DCAPlan(intervalDays: 7) }
                                else {
                                    strategy.dca = nil
                                    if strategy.entry.isEmpty { strategy.entry = [.rsiBelow(period: 14, level: 30)] }
                                }
                            })) {
                            Text("Signals").tag(false)
                            Text("DCA schedule").tag(true)
                        }.pickerStyle(.segmented)
                        if strategy.dca != nil {
                            Text("Dollar-cost averaging: buy on a schedule, whatever the price. Choose below how much goes in each time.")
                                .font(.system(size: 12)).foregroundStyle(Theme.dim)
                        }
                    }
                }

                if let plan = strategy.dca {
                    let days = lab.range(for: span).count
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("How often")
                            HStack(spacing: 8) {
                                ForEach([(1, "Daily"), (7, "Weekly"), (14, "2 weeks"), (30, "Monthly")], id: \.0) { d, t in
                                    Button {
                                        var p = plan; p.intervalDays = d; strategy.dca = p
                                    } label: {
                                        Text(t).font(.system(size: 13, weight: .bold))
                                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                                            .background(plan.intervalDays == d ? Theme.orange : Theme.panel2,
                                                        in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(plan.intervalDays == d ? Color.black : Theme.text)
                                    }
                                }
                            }
                            HStack {
                                Text("Or every").foregroundStyle(Theme.dim)
                                Spacer()
                                Text("\(plan.intervalDays) days")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(Theme.orange)
                                Stepper("", value: Binding(get: { plan.intervalDays },
                                                           set: { var p = plan; p.intervalDays = $0; strategy.dca = p }),
                                        in: 1...90).labelsHidden()
                            }
                            .font(.system(size: 13))
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("How much each time")
                            Picker("", selection: Binding(
                                get: { plan.mode },
                                set: { m in
                                    var p = plan
                                    switch m {
                                    case .evenSpread: p.dollarsPerBuy = nil; p.percentOfStart = nil
                                    case .dollars: p.dollarsPerBuy = p.dollarsPerBuy ?? 1_000; p.percentOfStart = nil
                                    case .percent: p.percentOfStart = p.percentOfStart ?? 5; p.dollarsPerBuy = nil
                                    }
                                    strategy.dca = p
                                })) {
                                Text("Spread evenly").tag(DCAPlan.Mode.evenSpread)
                                Text("Fixed $").tag(DCAPlan.Mode.dollars)
                                Text("% of cash").tag(DCAPlan.Mode.percent)
                            }.pickerStyle(.segmented)

                            switch plan.mode {
                            case .evenSpread:
                                Text("Your starting cash is divided equally across every purchase, so all of it ends up invested by the last buy.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
                            case .dollars:
                                HStack(spacing: 8) {
                                    ForEach([100.0, 500, 1_000, 5_000], id: \.self) { v in
                                        Button {
                                            var p = plan; p.dollarsPerBuy = v; strategy.dca = p
                                        } label: {
                                            Text("$\(Int(v).formatted())").font(.system(size: 13, weight: .bold))
                                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                                .background(plan.dollarsPerBuy == v ? Theme.orange : Theme.panel2,
                                                            in: RoundedRectangle(cornerRadius: 10))
                                                .foregroundStyle(plan.dollarsPerBuy == v ? Color.black : Theme.text)
                                        }
                                    }
                                }
                                HStack {
                                    Text("Each purchase").foregroundStyle(Theme.dim)
                                    Spacer()
                                    Text("$\(Int(plan.dollarsPerBuy ?? 0).formatted())")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(Theme.orange)
                                    Stepper("", value: Binding(get: { plan.dollarsPerBuy ?? 1_000 },
                                                               set: { var p = plan; p.dollarsPerBuy = $0; strategy.dca = p }),
                                            in: 50...50_000, step: 50).labelsHidden()
                                }
                                .font(.system(size: 13))
                            case .percent:
                                HStack {
                                    Text("Each purchase").foregroundStyle(Theme.dim)
                                    Spacer()
                                    Text(String(format: "%g%% of starting cash", plan.percentOfStart ?? 0))
                                        .font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(Theme.orange)
                                    Stepper("", value: Binding(get: { plan.percentOfStart ?? 5 },
                                                               set: { var p = plan; p.percentOfStart = $0; strategy.dca = p }),
                                            in: 0.5...100, step: 0.5).labelsHidden()
                                }
                                .font(.system(size: 13))
                            }

                            Divider().overlay(Theme.line)

                            // Reinvest a share of the profit so far into each purchase.
                            Toggle(isOn: Binding(
                                get: { plan.reinvests },
                                set: { on in
                                    var p = plan
                                    p.reinvestPercent = on ? (p.reinvestPercent ?? 50) : nil
                                    strategy.dca = p
                                })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Reinvest profits").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                    Text("Add a share of the profit so far to each purchase")
                                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                                }
                            }.tint(Theme.orange)
                            if plan.reinvests {
                                HStack {
                                    Text("Share of profit").foregroundStyle(Theme.dim)
                                    Spacer()
                                    Text(String(format: "%g%%", plan.reinvestPercent ?? 0))
                                        .font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(Theme.orange)
                                    Stepper("", value: Binding(get: { plan.reinvestPercent ?? 50 },
                                                               set: { var p = plan; p.reinvestPercent = $0; strategy.dca = p }),
                                            in: 10...100, step: 10).labelsHidden()
                                }
                                .font(.system(size: 13))
                                Text("Your gains are held in Bitcoin, so the extra comes from cash still waiting. With no cash left, nothing extra is added. Works best with Fixed $ or % of cash, which leave cash waiting.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                            }

                            // The plain-English bottom line, always visible.
                            VStack(alignment: .leading, spacing: 4) {
                                Text("WHAT THIS MEANS").font(.system(size: 9, weight: .heavy)).tracking(1)
                                    .foregroundStyle(Theme.gold)
                                Text(plan.summary(startCash: BacktestSettings().startCash, days: days))
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Based on \(BacktestSettings().startCash.formatted(.currency(code: "USD").precision(.fractionLength(0)))) starting cash over \(days) days. Holding is compared using the same dollars you invest.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                } else {
                    conditionCard(title: "BUY when ALL of these are true", subtitle: "The robot buys the moment they all become true together.",
                                  list: \.entry, kind: .entry, color: Theme.green)
                    conditionCard(title: "SELL when ANY of these is true", subtitle: "Optional. The robot also has the stops below.",
                                  list: \.exit, kind: .exit, color: Theme.red)
                    riskCard
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Test it over")
                        DateSpanPicker(span: $span)
                    }
                }

                Button { showResult = true } label: {
                    Text("RUN THE ROBOT").font(.system(size: 16, weight: .black)).tracking(1)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                .disabled(strategy.entry.isEmpty && strategy.dca == nil)
                .opacity(strategy.entry.isEmpty && strategy.dca == nil ? 0.4 : 1)
                if strategy.entry.isEmpty && strategy.dca == nil {
                    Text("Add at least one BUY condition.").font(.system(size: 12)).foregroundStyle(Theme.red)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Build rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(saved ? "Saved ✓" : "Save") {
                    if strategy.name.trimmingCharacters(in: .whitespaces).isEmpty { strategy.name = "My robot" }
                    lab.save(strategy); saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                }
            }
        }
        .navigationDestination(isPresented: $showResult) {
            ResultView(strategy: strategy, span: span)
        }
        .sheet(item: $editing) { target in
            let current: Condition? = target.index.map {
                target.list == .entry ? strategy.entry[$0] : strategy.exit[$0]
            }
            ConditionEditor(initial: current) { c in
                switch (target.list, target.index) {
                case (.entry, let i?): strategy.entry[i] = c
                case (.entry, nil): strategy.entry.append(c)
                case (.exit, let i?): strategy.exit[i] = c
                case (.exit, nil): strategy.exit.append(c)
                }
            }
        }
    }

    // MARK: Pieces

    private var templates: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Start from a template")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Strategy.templates, id: \.name) { t in
                        Button { strategy = t } label: {
                            Text(t.name).font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Theme.panel2, in: Capsule())
                                .overlay(Capsule().stroke(Theme.line))
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
            }
        }
    }

    private func conditionCard(title: String, subtitle: String, list: WritableKeyPath<Strategy, [Condition]>,
                               kind: EditTarget.Where, color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 13, weight: .heavy)).foregroundStyle(color)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.dim)
                ForEach(Array(strategy[keyPath: list].enumerated()), id: \.offset) { i, c in
                    HStack {
                        Button { editing = EditTarget(list: kind, index: i) } label: {
                            Text(c.summary).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Button { strategy[keyPath: list].remove(at: i) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(10)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                }
                Button { editing = EditTarget(list: kind, index: nil) } label: {
                    Label("Add a condition", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.orange)
                }
            }
        }
    }

    private var riskCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("RISK & ORDERS").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.gold)
                optionalPercent("Stop loss", detail: "Sell if the price falls this far below the buy price",
                                value: $strategy.stopLossPercent, defaultValue: 10, range: 1...80)
                optionalPercent("Take profit", detail: "Sell with a limit order this far above the buy price",
                                value: $strategy.takeProfitPercent, defaultValue: 25, range: 2...500)
                optionalPercent("Trailing stop", detail: "Sell if the price falls this far from its high since buying",
                                value: $strategy.trailingStopPercent, defaultValue: 15, range: 2...80)
                optionalPercent("Limit buy", detail: "Buy this far below the signal price instead of at the next open (waits 3 days)",
                                value: $strategy.limitEntryDiscountPercent, defaultValue: 4, range: 1...30)
                optionalInt("Max holding time", detail: "Sell after this many days",
                            value: $strategy.maxHoldDays, defaultValue: 30, range: 2...365)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Position size").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("Share of cash used on each buy").font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Text("\(Int(strategy.positionPercent))%")
                        .font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(Theme.orange)
                    Stepper("", value: $strategy.positionPercent, in: 10...100, step: 10).labelsHidden()
                }
            }
        }
    }

    private func optionalPercent(_ title: String, detail: String, value: Binding<Double?>,
                                 defaultValue: Double, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { value.wrappedValue != nil },
                                 set: { value.wrappedValue = $0 ? defaultValue : nil })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
            }
            .tint(Theme.orange)
            if let v = value.wrappedValue {
                HStack {
                    Spacer()
                    Text(String(format: "%g%%", v)).font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.orange)
                    Stepper("", value: Binding(get: { v }, set: { value.wrappedValue = $0 }), in: range, step: 1)
                        .labelsHidden()
                }
            }
        }
    }

    private func optionalInt(_ title: String, detail: String, value: Binding<Int?>,
                             defaultValue: Int, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { value.wrappedValue != nil },
                                 set: { value.wrappedValue = $0 ? defaultValue : nil })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
            }
            .tint(Theme.orange)
            if let v = value.wrappedValue {
                HStack {
                    Spacer()
                    Text("\(v) days").font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.orange)
                    Stepper("", value: Binding(get: { v }, set: { value.wrappedValue = $0 }), in: range)
                        .labelsHidden()
                }
            }
        }
    }
}
