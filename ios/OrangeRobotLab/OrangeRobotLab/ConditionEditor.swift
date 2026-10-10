import SwiftUI
import OrangeRobotKit

enum ConditionKind: String, CaseIterable, Identifiable {
    case rsiBelow, rsiAbove, priceAboveMA, priceBelowMA, maAbove, maBelow
    case dropFromHigh, breakout, belowLowerBand, aboveUpperBand, macdAbove, macdBelow
    var id: String { rawValue }

    var title: String {
        switch self {
        case .rsiBelow: return "RSI is below…"
        case .rsiAbove: return "RSI is above…"
        case .priceAboveMA: return "Price is above its average"
        case .priceBelowMA: return "Price is below its average"
        case .maAbove: return "Fast average above slow average"
        case .maBelow: return "Fast average below slow average"
        case .dropFromHigh: return "Price has dropped from a recent high"
        case .breakout: return "Price breaks above a recent high"
        case .belowLowerBand: return "Price below the lower Bollinger band"
        case .aboveUpperBand: return "Price above the upper Bollinger band"
        case .macdAbove: return "MACD is above its signal line"
        case .macdBelow: return "MACD is below its signal line"
        }
    }

    /// (label, range, step) for up to two numbers.
    var params: [(String, ClosedRange<Double>, Double)] {
        switch self {
        case .rsiBelow, .rsiAbove: return [("RSI days", 2...50, 1), ("Level", 5...95, 1)]
        case .priceAboveMA, .priceBelowMA: return [("Average days", 2...300, 1)]
        case .maAbove, .maBelow: return [("Fast days", 2...100, 1), ("Slow days", 5...300, 1)]
        case .dropFromHigh: return [("Look back (days)", 3...200, 1), ("Drop (%)", 1...60, 1)]
        case .breakout: return [("Look back (days)", 5...200, 1)]
        case .belowLowerBand, .aboveUpperBand: return [("Band days", 5...100, 1), ("Width (σ)", 0.5...4, 0.5)]
        case .macdAbove, .macdBelow: return []
        }
    }

    var defaults: [Double] {
        switch self {
        case .rsiBelow: return [14, 30]
        case .rsiAbove: return [14, 60]
        case .priceAboveMA, .priceBelowMA: return [50]
        case .maAbove, .maBelow: return [20, 50]
        case .dropFromHigh: return [30, 15]
        case .breakout: return [30]
        case .belowLowerBand, .aboveUpperBand: return [20, 2]
        case .macdAbove, .macdBelow: return []
        }
    }

    func make(_ v: [Double]) -> Condition {
        let a = Int(v.first ?? 0), b = v.count > 1 ? v[1] : 0
        switch self {
        case .rsiBelow: return .rsiBelow(period: a, level: b)
        case .rsiAbove: return .rsiAbove(period: a, level: b)
        case .priceAboveMA: return .priceAboveMA(period: a)
        case .priceBelowMA: return .priceBelowMA(period: a)
        case .maAbove: return .maAbove(fast: a, slow: max(Int(b), a + 1))
        case .maBelow: return .maBelow(fast: a, slow: max(Int(b), a + 1))
        case .dropFromHigh: return .dropFromHigh(days: a, percent: b)
        case .breakout: return .breakout(days: a)
        case .belowLowerBand: return .belowLowerBand(period: a, deviations: b)
        case .aboveUpperBand: return .aboveUpperBand(period: a, deviations: b)
        case .macdAbove: return .macdAboveSignal
        case .macdBelow: return .macdBelowSignal
        }
    }

    static func decompose(_ c: Condition) -> (ConditionKind, [Double]) {
        switch c {
        case let .rsiBelow(p, l): return (.rsiBelow, [Double(p), l])
        case let .rsiAbove(p, l): return (.rsiAbove, [Double(p), l])
        case let .priceAboveMA(p): return (.priceAboveMA, [Double(p)])
        case let .priceBelowMA(p): return (.priceBelowMA, [Double(p)])
        case let .maAbove(f, s): return (.maAbove, [Double(f), Double(s)])
        case let .maBelow(f, s): return (.maBelow, [Double(f), Double(s)])
        case let .dropFromHigh(d, p): return (.dropFromHigh, [Double(d), p])
        case let .breakout(d): return (.breakout, [Double(d)])
        case let .belowLowerBand(p, k): return (.belowLowerBand, [Double(p), k])
        case let .aboveUpperBand(p, k): return (.aboveUpperBand, [Double(p), k])
        case .macdAboveSignal: return (.macdAbove, [])
        case .macdBelowSignal: return (.macdBelow, [])
        }
    }
}

/// Add or edit one condition.
struct ConditionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let initial: Condition?
    let onSave: (Condition) -> Void

    @State private var kind: ConditionKind = .rsiBelow
    @State private var values: [Double] = ConditionKind.rsiBelow.defaults

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel("Type")
                    ForEach(ConditionKind.allCases) { k in
                        Button {
                            kind = k
                            values = k.defaults
                        } label: {
                            HStack {
                                Image(systemName: kind == k ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(kind == k ? Theme.orange : Theme.dim)
                                Text(k.title).foregroundStyle(Theme.text)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    if !kind.params.isEmpty {
                        SectionLabel("Settings")
                        ForEach(Array(kind.params.enumerated()), id: \.offset) { i, p in
                            HStack {
                                Text(p.0).foregroundStyle(Theme.text)
                                Spacer()
                                Text(String(format: "%g", values[i]))
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.orange)
                                Stepper("", value: Binding(get: { values[i] }, set: { values[i] = $0 }),
                                        in: p.1, step: p.2).labelsHidden()
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel("The robot checks")
                            Text(kind.make(values).summary).font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                .padding(18)
            }
            .background(Theme.bg)
            .navigationTitle(initial == nil ? "Add condition" : "Edit condition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onSave(kind.make(values)); dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let c = initial {
                let (k, v) = ConditionKind.decompose(c)
                kind = k; values = v
            }
        }
    }
}
