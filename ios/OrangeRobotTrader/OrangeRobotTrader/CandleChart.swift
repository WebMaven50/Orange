import SwiftUI
import OrangeRobotKit

struct CandleChart: View {
    let candles: [Candle]
    let lastPrice: Double
    let orders: [PendingOrder]
    /// How many candle slots span the plot. Fewer candles hug the right edge,
    /// so a brand-new run reads like a real chart that is just getting started.
    var slots = 48

    var body: some View {
        Canvas { ctx, size in
            guard !candles.isEmpty else { return }
            let labelW: CGFloat = 62
            let plot = CGRect(x: 0, y: 6, width: size.width - labelW, height: size.height - 12)

            var hi = candles.map(\.high).max()!
            var lo = candles.map(\.low).min()!
            for o in orders where o.type != .trailing { hi = max(hi, o.level); lo = min(lo, o.level) }
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

            // Candles
            let w = plot.width / CGFloat(max(slots, candles.count))
            for (i, c) in candles.enumerated() {
                let x = plot.maxX - (CGFloat(candles.count - i) - 0.5) * w
                let up = c.close >= c.open
                let color = up ? Theme.green : Theme.red
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(c.high)))
                wick.addLine(to: CGPoint(x: x, y: y(c.low)))
                ctx.stroke(wick, with: .color(color), lineWidth: 1)
                let top = y(max(c.open, c.close)), bottom = y(min(c.open, c.close))
                let body = CGRect(x: x - w * 0.34, y: top, width: w * 0.68, height: max(1, bottom - top))
                ctx.fill(Path(body), with: .color(color))
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
