import SwiftUI
import OrangeRobotKit

/// Plays a backtest back day by day: candles appear, the robot buys and sells,
/// and you can see its stops and targets and why it acted.
struct ReplayView: View {
    @Environment(LabModel.self) private var lab
    let strategy: Strategy
    let span: DateSpan

    @State private var robot: BacktestResult?
    @State private var hold: BacktestResult?
    @State private var cursor = 0                // index within the tested range
    @State private var playing = true
    @State private var speedIndex = 1
    @State private var carry = 0.0

    private static let speeds: [(String, Double)] = [("1 week / sec", 7), ("2 weeks / sec", 14),
                                                    ("1 month / sec", 30), ("3 months / sec", 90)]
    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let robot, let hold, !robot.equity.isEmpty {
                content(robot, hold)
            } else {
                Text("Nothing to replay for that period.").foregroundStyle(Theme.dim)
            }
        }
        .background(Theme.bg)
        .navigationTitle("Watch the robot")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard robot == nil else { return }
            let range = lab.range(for: span)
            robot = lab.backtester.run(strategy, days: range)
            hold = lab.backtester.buyAndHold(days: range)
        }
        .onReceive(tick) { _ in advance() }
    }

    // MARK: Layout

    private func content(_ r: BacktestResult, _ h: BacktestResult) -> some View {
        let day = r.days.lowerBound + cursor                       // absolute history day
        let bars = lab.backtester.history.bars
        let bar = bars[day]
        let held = r.holding(atCloseOf: day)
        let rEq = r.equity[cursor], hEq = h.equity[min(cursor, h.equity.count - 1)]
        let start = BacktestSettings().startCash

        return ScrollView {
            VStack(spacing: 12) {
                header(day: day, price: bar.close, held: held, total: r.days.count)
                headline(day: day)

                ReplayChart(history: lab.backtester.history, range: r.days, cursor: cursor, trades: r.trades,
                            strategy: strategy, held: held)
                    .frame(height: 280)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))

                eventCaption(r, day: day)
                controls(total: r.days.count)

                HStack(spacing: 10) {
                    valueBox("Your robot", rEq, start, color: Theme.orange)
                    valueBox("Just holding", hEq, start, color: Theme.dim)
                }

                LiveEquityChart(robot: r.equity, hold: h.equity, upTo: cursor)
                    .frame(height: 90)
                    .padding(10)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))

                tradeLog(r, day: day, held: held)
            }
            .padding(14)
        }
    }

    private func header(day: Int, price: Double, held: Trade?, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.date(lab.backtester.date(forDay: day)))
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                Text("Day \(cursor + 1) of \(total)").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.usd(price, decimals: 0))
                    .font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
                Text(held == nil ? "💵 In cash" : "₿ Holding Bitcoin")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(held == nil ? Theme.dim : Theme.green)
            }
        }
    }

    /// A significant real headline from the last two weeks, for context.
    @ViewBuilder
    private func headline(day: Int) -> some View {
        let today = Int((lab.backtester.date(forDay: day).timeIntervalSince1970 / 86_400).rounded())
        if let item = NewsFeed.bundled.items(upTo: today).first(where: { $0.significant && today - $0.dayNumber <= 14 }) {
            HStack(alignment: .top, spacing: 8) {
                Text("📰")
                Text(item.title).font(.system(size: 12)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func eventCaption(_ r: BacktestResult, day: Int) -> some View {
        Group {
            if let e = r.latestEvent(through: day) {
                let t = e.trade
                let when = Fmt.date(lab.backtester.date(forDay: e.isExit ? t.exitDay : t.entryDay))
                VStack(alignment: .leading, spacing: 3) {
                    if e.isExit {
                        Text("▼ SOLD \(when) at \(Fmt.usd(t.exitPrice, decimals: 0))")
                            .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.red)
                        Text("\(t.reason.title) · \(String(format: "%+.1f%%", t.returnPercent)) on this trade")
                            .font(.system(size: 12)).foregroundStyle(Theme.text)
                    } else {
                        Text("▲ BOUGHT \(when) at \(Fmt.usd(t.entryPrice, decimals: 0))")
                            .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.green)
                        Text(strategy.entry.map(\.summary).joined(separator: " and "))
                            .font(.system(size: 12)).foregroundStyle(Theme.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Waiting for the first signal…").font(.system(size: 12)).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func controls(total: Int) -> some View {
        VStack(spacing: 8) {
            Slider(value: Binding(get: { Double(cursor) },
                                  set: { cursor = Int($0); carry = 0 }),
                   in: 0...Double(max(total - 1, 1))).tint(Theme.orange)
            HStack(spacing: 14) {
                Button { cursor = 0; carry = 0; playing = true } label: {
                    Image(systemName: "backward.end.fill").frame(width: 40, height: 40)
                }
                Button {
                    if cursor >= total - 1 { cursor = 0 }
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 56, height: 44)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.black)
                }
                Menu {
                    ForEach(Array(Self.speeds.enumerated()), id: \.offset) { i, s in
                        Button { speedIndex = i } label: {
                            if i == speedIndex { Label(s.0, systemImage: "checkmark") } else { Text(s.0) }
                        }
                    }
                } label: {
                    Text(Self.speeds[speedIndex].0).font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Theme.text)
                }
                Spacer()
            }
            .foregroundStyle(Theme.text)
        }
    }

    private func valueBox(_ title: String, _ eq: Double, _ start: Double, color: Color) -> some View {
        let r = eq / start - 1
        return VStack(spacing: 3) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.5).foregroundStyle(color)
            Text(Fmt.usd(eq, decimals: 0)).font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)
            Text(Money.pct(r, digits: 1)).font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(r >= 0 ? Theme.green : Theme.red)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func tradeLog(_ r: BacktestResult, day: Int, held: Trade?) -> some View {
        let closed = r.closedTrades(through: day)
        let wins = closed.filter { $0.returnPercent > 0 }.count
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Trades so far: \(closed.count)" + (closed.isEmpty ? "" : "  ·  \(wins) won"))
            if let t = held {
                row(t, openPrice: lab.backtester.history.bars[day].close, isOpen: true)
            }
            ForEach(closed.reversed().prefix(12)) { row($0, openPrice: nil, isOpen: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ t: Trade, openPrice: Double?, isOpen: Bool) -> some View {
        let pct = openPrice.map { ($0 / t.entryPrice - 1) * 100 } ?? t.returnPercent
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isOpen ? "Open since \(Fmt.date(lab.backtester.date(forDay: t.entryDay)))"
                            : "\(Fmt.date(lab.backtester.date(forDay: t.entryDay))) → \(Fmt.date(lab.backtester.date(forDay: t.exitDay)))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                Text(isOpen ? "Bought at \(Fmt.usd(t.entryPrice, decimals: 0))"
                            : "\(Fmt.usd(t.entryPrice, decimals: 0)) → \(Fmt.usd(t.exitPrice, decimals: 0)) · \(t.reason.title)")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Spacer()
            Text(String(format: "%+.1f%%", pct)).font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(pct >= 0 ? Theme.green : Theme.red)
        }
        .padding(10)
        .background(isOpen ? Theme.green.opacity(0.10) : Theme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Playback

    private func advance() {
        guard playing, let r = robot else { return }
        let last = r.days.count - 1
        carry += Self.speeds[speedIndex].1 / 30.0
        let whole = Int(carry)
        if whole > 0 {
            carry -= Double(whole)
            cursor = min(cursor + whole, last)
            if cursor >= last { playing = false }
        }
    }
}

// MARK: - Chart

private struct ReplayChart: View {
    let history: PriceHistory
    let range: Range<Int>
    let cursor: Int
    let trades: [Trade]
    let strategy: Strategy
    let held: Trade?

    var body: some View {
        Canvas { ctx, size in
            let bars = history.bars
            let windowMax = min(range.count, 120)
            let lastDay = range.lowerBound + cursor
            let firstDay = max(range.lowerBound, lastDay - windowMax + 1)
            let slice = Array(bars[firstDay...lastDay])
            guard !slice.isEmpty else { return }

            let labelW: CGFloat = 54
            let plot = CGRect(x: 0, y: 8, width: size.width - labelW, height: size.height - 16)
            let w = plot.width / CGFloat(windowMax)

            // protective levels while holding
            var stop: Double?, target: Double?
            if let t = held {
                var s: Double?
                if let sl = strategy.stopLossPercent { s = t.entryPrice * (1 - sl / 100) }
                if let tr = strategy.trailingStopPercent, t.entryDay <= lastDay {
                    let high = bars[t.entryDay...lastDay].map(\.high).max() ?? t.entryPrice
                    let level = high * (1 - tr / 100)
                    if s == nil || level > s! { s = level }
                }
                stop = s
                target = strategy.takeProfitPercent.map { t.entryPrice * (1 + $0 / 100) }
            }

            var hi = slice.map(\.high).max()!, lo = slice.map(\.low).min()!
            if let s = stop, s > lo * 0.75 { lo = min(lo, s) }
            if let t = target, t < hi * 1.3 { hi = max(hi, t) }
            let pad = (hi - lo) * 0.08
            hi += pad; lo = max(0, lo - pad)
            func y(_ p: Double) -> CGFloat { plot.minY + plot.height * CGFloat(1 - (p - lo) / max(hi - lo, 1e-9)) }
            func x(_ day: Int) -> CGFloat { (CGFloat(day - firstDay) + 0.5) * w }

            // grid + labels
            for k in 0...3 {
                let p = lo + (hi - lo) * Double(k) / 3
                var g = Path(); g.move(to: CGPoint(x: 0, y: y(p))); g.addLine(to: CGPoint(x: plot.width, y: y(p)))
                ctx.stroke(g, with: .color(Theme.line.opacity(0.6)), lineWidth: 0.5)
                ctx.draw(Text(Fmt.axis(p)).font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.dim),
                         at: CGPoint(x: plot.width + 4, y: y(p)), anchor: .leading)
            }

            // shade the days the robot is holding
            for t in trades {
                let a = max(t.entryDay, firstDay), b = min(t.exitDay, lastDay)
                guard a <= b, a < t.exitDay || t.entryDay == t.exitDay else { continue }
                let r = CGRect(x: x(a) - w / 2, y: plot.minY, width: CGFloat(b - a + 1) * w, height: plot.height)
                ctx.fill(Path(r), with: .color(Theme.green.opacity(0.09)))
            }

            // candles (real daily data)
            for day in firstDay...lastDay {
                let b = bars[day]
                let color = b.close >= b.open ? Theme.green : Theme.red
                let cx = x(day)
                var wick = Path(); wick.move(to: CGPoint(x: cx, y: y(b.high))); wick.addLine(to: CGPoint(x: cx, y: y(b.low)))
                ctx.stroke(wick, with: .color(color), lineWidth: 1)
                let top = y(max(b.open, b.close)), bottom = y(min(b.open, b.close))
                ctx.fill(Path(CGRect(x: cx - w * 0.34, y: top, width: max(w * 0.68, 1), height: max(1, bottom - top))),
                         with: .color(color))
            }

            // stop / target lines
            func level(_ price: Double, _ color: Color, _ text: String) {
                var l = Path(); l.move(to: CGPoint(x: 0, y: y(price))); l.addLine(to: CGPoint(x: plot.width, y: y(price)))
                ctx.stroke(l, with: .color(color), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                ctx.draw(Text(text).font(.system(size: 9, weight: .heavy)).foregroundColor(color),
                         at: CGPoint(x: 6, y: y(price) - 7), anchor: .leading)
            }
            if let s = stop { level(s, Theme.red, "STOP") }
            if let t = target { level(t, Theme.green, "TARGET") }
            if let t = held {
                level(t.entryPrice, Theme.orange.opacity(0.9), "BOUGHT")
            }

            // buy / sell markers
            for t in trades {
                if t.entryDay >= firstDay, t.entryDay <= lastDay {
                    let p = CGPoint(x: x(t.entryDay), y: y(bars[t.entryDay].low) + 11)
                    var tri = Path()
                    tri.move(to: CGPoint(x: p.x, y: p.y - 7)); tri.addLine(to: CGPoint(x: p.x - 6, y: p.y + 5))
                    tri.addLine(to: CGPoint(x: p.x + 6, y: p.y + 5)); tri.closeSubpath()
                    ctx.fill(tri, with: .color(Theme.green))
                }
                if t.exitDay >= firstDay, t.exitDay <= lastDay {
                    let p = CGPoint(x: x(t.exitDay), y: y(bars[t.exitDay].high) - 11)
                    var tri = Path()
                    tri.move(to: CGPoint(x: p.x, y: p.y + 7)); tri.addLine(to: CGPoint(x: p.x - 6, y: p.y - 5))
                    tri.addLine(to: CGPoint(x: p.x + 6, y: p.y - 5)); tri.closeSubpath()
                    ctx.fill(tri, with: .color(Theme.red))
                }
            }
        }
    }
}

/// Robot vs holding, drawn up to `upTo` on a scale fixed by the whole run.
private struct LiveEquityChart: View {
    let robot: [Double]
    let hold: [Double]
    let upTo: Int

    var body: some View {
        Canvas { ctx, size in
            guard robot.count > 1 else { return }
            let all = robot + hold
            let lo = all.min()!, hi = all.max()!
            let span = max(hi - lo, 1)
            func pt(_ i: Int, _ v: Double) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(robot.count - 1),
                        y: size.height * CGFloat(1 - (v - lo) / span))
            }
            func line(_ v: [Double]) -> Path {
                var p = Path()
                for i in 0...min(upTo, v.count - 1) { i == 0 ? p.move(to: pt(0, v[0])) : p.addLine(to: pt(i, v[i])) }
                return p
            }
            ctx.stroke(line(hold), with: .color(Theme.dim), lineWidth: 1.3)
            ctx.stroke(line(robot), with: .color(Theme.orange), lineWidth: 2)
        }
    }
}
