import SwiftUI
import OrangeRobotKit

enum ChartStyle: String, CaseIterable, Identifiable {
    case candles, hollow, bars, line, area
    var id: String { rawValue }

    var title: String {
        switch self {
        case .candles: return "Candles"
        case .hollow: return "Hollow candles"
        case .bars: return "OHLC bars"
        case .line: return "Line"
        case .area: return "Area"
        }
    }
    var symbol: String {
        switch self {
        case .candles: return "chart.bar.fill"
        case .hollow: return "chart.bar"
        case .bars: return "chart.bar.xaxis"
        case .line: return "chart.xyaxis.line"
        case .area: return "chart.line.uptrend.xyaxis"
        }
    }
}

struct CandleChart: View {
    var style: ChartStyle = .candles
    let candles: [Candle]
    let lastPrice: Double
    let orders: [PendingOrder]
    var overlay: ChartOverlay?
    /// Share of the chart's height covered by peek panels (RSI / MACD) at the bottom.
    /// The price scale fits the space above them so candles are never hidden.
    var bottomFraction: CGFloat = 0
    /// 1 = fit the data; > 1 stretches the price scale in around the current price.
    var priceZoom: Double = 1
    /// How many candle slots span the plot. Fewer candles hug the right edge,
    /// so a brand-new run reads like a real chart that is just getting started.
    var slots = 48

    var body: some View {
        Canvas { ctx, size in
            guard !candles.isEmpty else { return }
            let labelW: CGFloat = 62
            let plot = CGRect(x: 0, y: 6, width: size.width - labelW,
                              height: size.height * (1 - bottomFraction) - 12)

            var hi = candles.map(\.high).max()!
            var lo = candles.map(\.low).min()!
            for o in orders where o.type != .trailing { hi = max(hi, o.level); lo = min(lo, o.level) }
            // Keep indicator lines on screen too
            if let ov = overlay {
                var extra: [Double?] = []
                if ov.showBands { extra += ov.data.bbUpper + ov.data.bbLower }
                if ov.showMA { extra += ov.data.ma20 + ov.data.ma50 }
                for v in extra.compactMap({ $0 }) { hi = max(hi, v); lo = min(lo, v) }
            }
            if abs(priceZoom - 1) > 0.001 {
                let mid = lastPrice
                let half = max(hi - lo, mid * 0.002) / 2 / priceZoom
                hi = mid + half
                lo = max(0, mid - half)
            }
            if hi - lo < hi * 0.002 {          // flat market: give it a visible band
                let mid = (hi + lo) / 2
                hi = mid * 1.02; lo = mid * 0.98
            }
            let pad = (hi - lo) * 0.06
            hi += pad; lo = max(0, lo - pad)  // a price axis never goes below zero
            func y(_ p: Double) -> CGFloat { plot.minY + plot.height * CGFloat(1 - (p - lo) / (hi - lo)) }

            // Grid + axis labels
            for k in 0...4 {
                let p = lo + (hi - lo) * Double(k) / 4
                let gy = y(p)
                var g = Path(); g.move(to: CGPoint(x: 0, y: gy)); g.addLine(to: CGPoint(x: plot.maxX, y: gy))
                ctx.stroke(g, with: .color(Theme.line.opacity(0.6)), lineWidth: 0.5)
                ctx.draw(Text(Fmt.axis(p)).font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.dim),
                         at: CGPoint(x: plot.maxX + 4, y: gy), anchor: .leading)
            }

            // Price series
            let w = plot.width / CGFloat(max(slots, candles.count))
            func x(_ i: Int) -> CGFloat { plot.maxX - (CGFloat(candles.count - i) - 0.5) * w }

            switch style {
            case .candles, .hollow:
                for (i, c) in candles.enumerated() {
                    let up = c.close >= c.open
                    let color = up ? Theme.green : Theme.red
                    let cx = x(i)
                    var wick = Path()
                    wick.move(to: CGPoint(x: cx, y: y(c.high)))
                    wick.addLine(to: CGPoint(x: cx, y: y(c.low)))
                    ctx.stroke(wick, with: .color(color), lineWidth: 1)
                    let top = y(max(c.open, c.close)), bottom = y(min(c.open, c.close))
                    let body = CGRect(x: cx - w * 0.34, y: top, width: w * 0.68, height: max(1, bottom - top))
                    if style == .hollow && up {
                        // rising candles are outlined, falling ones are solid
                        ctx.stroke(Path(body.insetBy(dx: 0.5, dy: 0.5)), with: .color(color), lineWidth: 1.2)
                    } else {
                        ctx.fill(Path(body), with: .color(color))
                    }
                }

            case .bars:
                for (i, c) in candles.enumerated() {
                    let color = c.close >= c.open ? Theme.green : Theme.red
                    let cx = x(i), tick = max(2, w * 0.4)
                    var p = Path()
                    p.move(to: CGPoint(x: cx, y: y(c.high))); p.addLine(to: CGPoint(x: cx, y: y(c.low)))
                    p.move(to: CGPoint(x: cx - tick, y: y(c.open))); p.addLine(to: CGPoint(x: cx, y: y(c.open)))
                    p.move(to: CGPoint(x: cx, y: y(c.close))); p.addLine(to: CGPoint(x: cx + tick, y: y(c.close)))
                    ctx.stroke(p, with: .color(color), lineWidth: max(1, min(2, w * 0.18)))
                }

            case .line, .area:
                // Closes, ending on the live price so the line meets the price tag.
                var pts = candles.enumerated().map { CGPoint(x: x($0.offset), y: y($0.element.close)) }
                if let last = pts.indices.last { pts[last].y = y(lastPrice) }
                guard let first = pts.first, let last = pts.last else { break }
                let rising = lastPrice >= candles[0].open
                let color = rising ? Theme.green : Theme.red
                var line = Path()
                line.move(to: first)
                for pt in pts.dropFirst() { line.addLine(to: pt) }
                if style == .area {
                    var fill = line
                    fill.addLine(to: CGPoint(x: last.x, y: plot.maxY))
                    fill.addLine(to: CGPoint(x: first.x, y: plot.maxY))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .linearGradient(
                        Gradient(colors: [color.opacity(0.35), color.opacity(0.02)]),
                        startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
                }
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(color))
            }

            // Indicator overlays, clipped to the plot area
            if let o = overlay {
                var c = ctx
                c.clip(to: Path(plot))
                func line(_ vals: [Double?]) -> Path {
                    var p = Path(); var started = false
                    for (i, v) in vals.enumerated() where i < candles.count {
                        guard let v else { started = false; continue }
                        let pt = CGPoint(x: x(i), y: y(v))
                        if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                    }
                    return p
                }
                if o.showBands {
                    // light fill between the bands, then the three lines
                    var fill = Path(); var started = false
                    var back: [CGPoint] = []
                    for i in candles.indices {
                        guard i < o.data.bbUpper.count, let u = o.data.bbUpper[i], let l = o.data.bbLower[i] else { continue }
                        let pu = CGPoint(x: x(i), y: y(u))
                        if started { fill.addLine(to: pu) } else { fill.move(to: pu); started = true }
                        back.append(CGPoint(x: x(i), y: y(l)))
                    }
                    for p in back.reversed() { fill.addLine(to: p) }
                    if started { fill.closeSubpath(); c.fill(fill, with: .color(Color(hex: 0xB28CFF).opacity(0.10))) }
                    c.stroke(line(o.data.bbUpper), with: .color(Color(hex: 0xB28CFF)), lineWidth: 1)
                    c.stroke(line(o.data.bbLower), with: .color(Color(hex: 0xB28CFF)), lineWidth: 1)
                    c.stroke(line(o.data.bbMid), with: .color(Color(hex: 0xB28CFF).opacity(0.7)),
                             style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if o.showMA {
                    c.stroke(line(o.data.ma50), with: .color(Color(hex: 0xFFD166)), lineWidth: 1.4)
                    c.stroke(line(o.data.ma20), with: .color(Color(hex: 0x6AA9FF)), lineWidth: 1.4)
                }
            }

            // Resting orders
            for o in orders where o.type != .trailing {
                let oy = y(o.level)
                var l = Path(); l.move(to: CGPoint(x: 0, y: oy)); l.addLine(to: CGPoint(x: plot.maxX, y: oy))
                let c = o.side == .buy ? Theme.green : Theme.red
                ctx.stroke(l, with: .color(c.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            // Last price
            let ly = y(lastPrice)
            var line = Path(); line.move(to: CGPoint(x: 0, y: ly)); line.addLine(to: CGPoint(x: plot.maxX, y: ly))
            ctx.stroke(line, with: .color(Theme.orange),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            let tag = CGRect(x: plot.maxX + 1, y: ly - 8, width: labelW - 2, height: 16)
            ctx.fill(Path(roundedRect: tag, cornerRadius: 3), with: .color(Theme.orange))
            ctx.draw(Text(Fmt.axis(lastPrice)).font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.black), at: CGPoint(x: tag.midX, y: tag.midY))
        }
        .background(Theme.panel)
    }
}
