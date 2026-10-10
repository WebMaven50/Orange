import SwiftUI
import OrangeRobotKit

enum IndicatorKind: String, CaseIterable, Identifiable {
    case ma, bollinger, rsi, macd
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ma: return "Moving averages"
        case .bollinger: return "Bollinger Bands"
        case .rsi: return "RSI"
        case .macd: return "MACD"
        }
    }
    var detail: String {
        switch self {
        case .ma: return "MA 20 and MA 50, drawn on the chart"
        case .bollinger: return "20 periods, 2 standard deviations"
        case .rsi: return "14 periods. Peek panel, 30 / 70 lines"
        case .macd: return "12 · 26 · 9. Peek panel with histogram"
        }
    }
    /// Panels slide up over the bottom of the chart; the others draw on top of it.
    var isPanel: Bool { self == .rsi || self == .macd }

    var color: Color {
        switch self {
        case .ma: return Color(hex: 0x6AA9FF)
        case .bollinger: return Color(hex: 0xB28CFF)
        case .rsi: return Theme.gold
        case .macd: return Theme.orange
        }
    }
}

/// Indicator values aligned one-to-one with the candles on screen.
struct IndicatorData {
    var ma20: [Double?] = []
    var ma50: [Double?] = []
    var bbMid: [Double?] = []
    var bbUpper: [Double?] = []
    var bbLower: [Double?] = []
    var rsi: [Double?] = []
    var macd: [Double?] = []
    var signal: [Double?] = []
    var histogram: [Double?] = []

    /// `closes` includes warm-up history; only the last `visible` values are kept.
    init(closes: [Double], visible: Int) {
        func tail(_ a: [Double?]) -> [Double?] { Array(a.suffix(visible)) }
        ma20 = tail(Indicators.sma(closes, period: 20))
        ma50 = tail(Indicators.sma(closes, period: 50))
        let b = Indicators.bollinger(closes, period: 20, deviations: 2)
        bbMid = tail(b.middle); bbUpper = tail(b.upper); bbLower = tail(b.lower)
        rsi = tail(Indicators.rsi(closes, period: 14))
        let m = Indicators.macd(closes)
        macd = tail(m.macd); signal = tail(m.signal); histogram = tail(m.histogram)
    }
}

/// Which overlays to draw on the price chart.
struct ChartOverlay {
    var data: IndicatorData
    var showMA = false
    var showBands = false
}

// MARK: - Peek panels (RSI / MACD)

private let axisColumn: CGFloat = 62

/// Maps candle index to the same x position the price chart uses.
private func slotX(_ i: Int, count: Int, slots: Int, plotWidth: CGFloat) -> CGFloat {
    let w = plotWidth / CGFloat(max(slots, count))
    return plotWidth - (CGFloat(count - i) - 0.5) * w
}

struct RSIPanel: View {
    let values: [Double?]
    var slots = 48

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 0, y: 18, width: size.width - axisColumn, height: size.height - 24)
            func y(_ v: Double) -> CGFloat { plot.minY + plot.height * CGFloat(1 - v / 100) }

            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg.opacity(0.94)))
            var top = Path(); top.move(to: .zero); top.addLine(to: CGPoint(x: size.width, y: 0))
            ctx.stroke(top, with: .color(Theme.line), lineWidth: 1)

            // 30–70 band
            let band = CGRect(x: 0, y: y(70), width: plot.width, height: y(30) - y(70))
            ctx.fill(Path(band), with: .color(Color.white.opacity(0.04)))
            for (level, color) in [(70.0, Theme.red), (30.0, Theme.green)] {
                var l = Path(); l.move(to: CGPoint(x: 0, y: y(level))); l.addLine(to: CGPoint(x: plot.width, y: y(level)))
                ctx.stroke(l, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ctx.draw(Text("\(Int(level))").font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.dim),
                         at: CGPoint(x: plot.width + 6, y: y(level)), anchor: .leading)
            }

            var line = Path(); var started = false
            for (i, v) in values.enumerated() {
                guard let v else { started = false; continue }
                let p = CGPoint(x: slotX(i, count: values.count, slots: slots, plotWidth: plot.width), y: y(v))
                if started { line.addLine(to: p) } else { line.move(to: p); started = true }
            }
            ctx.stroke(line, with: .color(Theme.gold), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))

            let now = values.last ?? nil
            ctx.draw(Text("RSI 14").font(.system(size: 10, weight: .heavy)).foregroundColor(Theme.gold),
                     at: CGPoint(x: 8, y: 9), anchor: .leading)
            if let now {
                let tint: Color = now >= 70 ? Theme.red : now <= 30 ? Theme.green : Theme.text
                let tag = now >= 70 ? "  overbought" : now <= 30 ? "  oversold" : ""
                ctx.draw(Text(String(format: "%.1f", now) + tag)
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(tint),
                         at: CGPoint(x: 62, y: 9), anchor: .leading)
            }
        }
    }
}

struct MACDPanel: View {
    let macd: [Double?]
    let signal: [Double?]
    let histogram: [Double?]
    var slots = 48

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 0, y: 18, width: size.width - axisColumn, height: size.height - 24)
            let all = (macd + signal + histogram).compactMap { $0 }
            let m = max(all.map { abs($0) }.max() ?? 1, 1e-9) * 1.1
            func y(_ v: Double) -> CGFloat { plot.midY - plot.height / 2 * CGFloat(v / m) }

            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg.opacity(0.94)))
            var top = Path(); top.move(to: .zero); top.addLine(to: CGPoint(x: size.width, y: 0))
            ctx.stroke(top, with: .color(Theme.line), lineWidth: 1)

            var zero = Path(); zero.move(to: CGPoint(x: 0, y: y(0))); zero.addLine(to: CGPoint(x: plot.width, y: y(0)))
            ctx.stroke(zero, with: .color(Theme.line), lineWidth: 1)

            let count = histogram.count
            let w = plot.width / CGFloat(max(slots, count))
            for (i, h) in histogram.enumerated() {
                guard let h else { continue }
                let x = slotX(i, count: count, slots: slots, plotWidth: plot.width)
                let r = CGRect(x: x - w * 0.3, y: min(y(0), y(h)), width: w * 0.6, height: max(1, abs(y(h) - y(0))))
                ctx.fill(Path(r), with: .color((h >= 0 ? Theme.green : Theme.red).opacity(0.75)))
            }
            func stroke(_ s: [Double?], _ color: Color) {
                var p = Path(); var started = false
                for (i, v) in s.enumerated() {
                    guard let v else { started = false; continue }
                    let pt = CGPoint(x: slotX(i, count: s.count, slots: slots, plotWidth: plot.width), y: y(v))
                    if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                }
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            stroke(macd, Theme.orange)
            stroke(signal, Color(hex: 0x6AA9FF))

            ctx.draw(Text("MACD 12·26·9").font(.system(size: 10, weight: .heavy)).foregroundColor(Theme.orange),
                     at: CGPoint(x: 8, y: 9), anchor: .leading)
            if let m = macd.last ?? nil, let s = signal.last ?? nil {
                ctx.draw(Text(String(format: "MACD %.1f  Signal %.1f", m, s))
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Theme.text),
                         at: CGPoint(x: 100, y: 9), anchor: .leading)
            }
        }
    }
}

// MARK: - Picker card

struct IndicatorMenuCard: View {
    @Bindable var model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INDICATORS").font(.system(size: 10, weight: .heavy)).tracking(1.5)
                .foregroundStyle(Theme.dim).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ForEach(IndicatorKind.allCases) { k in
                Button { model.toggleIndicator(k) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.indicators.contains(k) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundStyle(model.indicators.contains(k) ? k.color : Theme.dim)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(k.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                            Text(k.detail).font(.system(size: 11)).foregroundStyle(Theme.dim)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
            }
            if !model.indicators.isEmpty {
                Button { model.clearIndicators() } label: {
                    Text("Turn all off").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
        }
        .frame(width: 270)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}
