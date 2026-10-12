import SwiftUI
import OrangeRobotKit

struct TradingView: View {
    @Bindable var model: GameModel
    @State private var panLast: CGFloat = 0
    @State private var zoomLast: CGFloat = 0
    @State private var crosshair: CGPoint?
    @State private var crosshairIndex = -1

    var body: some View {
        let s = model.session
        // Indicators need history before the visible window to warm up.
        let wanted = model.indicators.isEmpty ? 48 : 48 + 130
        let series = model.visibleCandles(count: wanted)
        let shown = Array(series.suffix(48))
        let displayPrice = model.viewport.isLive ? s.lastPrice : (shown.last?.close ?? s.lastPrice)
        let panelCount = (model.indicators.contains(.rsi) ? 1 : 0) + (model.indicators.contains(.macd) ? 1 : 0)
        let panelShare = CGFloat(panelCount) * 0.22
        let ind: IndicatorData? = model.indicators.isEmpty ? nil
            : IndicatorData(closes: series.map(\.close), visible: shown.count)
        VStack(spacing: 0) {
            topBar
            priceRow(s)
            controls
            ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
            ZStack {
                CandleChart(style: model.chartStyle,
                            candles: shown,
                            lastPrice: displayPrice, orders: s.pendingOrders,
                            overlay: ind.map {
                                ChartOverlay(data: $0,
                                             showMA: model.indicators.contains(.ma),
                                             showBands: model.indicators.contains(.bollinger))
                            },
                            bottomFraction: panelShare,
                            priceZoom: model.viewport.priceZoom,
                            crosshair: crosshair,
                            candleStarts: crosshair == nil ? [] : model.visibleCandleStarts(count: shown.count),
                            timeLabel: { model.timeLabel(forMinute: $0) })
                chartGestures
                if s.isLive { realTimeBanner }
                // RSI / MACD peek panels slide up over the bottom of the chart
                if let ind, model.indicators.contains(.rsi) || model.indicators.contains(.macd) {
                    GeometryReader { g in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            if model.indicators.contains(.rsi) {
                                RSIPanel(values: ind.rsi).frame(height: g.size.height * 0.22)
                            }
                            if model.indicators.contains(.macd) {
                                MACDPanel(macd: ind.macd, signal: ind.signal, histogram: ind.histogram)
                                    .frame(height: g.size.height * 0.22)
                            }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            model.showIndicatorMenu.toggle()
                            Feedback.play(.select)
                        } label: {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 30, height: 28)
                                .background((model.indicators.isEmpty ? Theme.panel2 : Theme.orange).opacity(0.9),
                                            in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line))
                                .foregroundStyle(model.indicators.isEmpty ? Theme.text : Color.black)
                        }
                        .padding(.trailing, 4)
                        Menu {
                            ForEach(ChartStyle.allCases) { st in
                                Button {
                                    model.chartStyle = st
                                    Feedback.play(.select)
                                } label: {
                                    if st == model.chartStyle {
                                        Label(st.title, systemImage: "checkmark")
                                    } else {
                                        Label(st.title, systemImage: st.symbol)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: model.chartStyle.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 30, height: 28)
                                .background(Theme.panel2.opacity(0.9), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line))
                                .foregroundStyle(Theme.text)
                        }
                        .padding(.trailing, 68)
                    }
                    Spacer()
                }.padding(.top, 6)
                if model.showIndicatorMenu {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { model.showIndicatorMenu = false }
                    VStack {
                        HStack {
                            Spacer()
                            IndicatorMenuCard(model: model).padding(.trailing, 8)
                        }
                        Spacer()
                    }
                    .padding(.top, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                // Pills that bring the chart back: to the present, and to automatic scaling
                if !model.viewport.isLive || !model.viewport.isDefaultZoom {
                    VStack(alignment: .leading, spacing: 6) {
                        if let d = model.viewedDate {
                            Button { model.chartGoLive() } label: {
                                Label("\(Fmt.date(d)) · Latest", systemImage: "forward.end.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.orange, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                        }
                        if !model.viewport.isDefaultZoom {
                            Button { model.resetPriceScale() } label: {
                                Label("Auto scale", systemImage: "arrow.up.and.down")
                                    .font(.system(size: 11, weight: .heavy))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.panel2.opacity(0.95), in: Capsule())
                                    .overlay(Capsule().stroke(Theme.orange))
                                    .foregroundStyle(Theme.orange)
                            }
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6).padding(.top, s.isRandomStart ? 8 : 34)
                }
                if model.showChartHint {
                    VStack {
                        Spacer()
                        Text("Drag to scroll back · drag the price scale to stretch · press and hold to measure")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.black.opacity(0.85), in: Capsule())
                            .foregroundStyle(Theme.text)
                            .padding(.bottom, 10)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
                if !s.isRandomStart {
                    VStack {
                        HStack {
                            Text("PRACTICE")
                                .font(.system(size: 9, weight: .heavy)).tracking(1)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Theme.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.black)
                            Spacer()
                        }
                        Spacer()
                    }.padding(6)
                }
                if let b = model.banner {
                    VStack {
                        NewsBannerView(item: b) { model.openNews() }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 6)
                        Spacer()
                    }
                    .zIndex(2)
                }
                if s.isPaused {
                    Color.black.opacity(0.55)
                    VStack(spacing: 8) {
                        Image(systemName: "pause.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.orange)
                        Text("PAUSED").font(.system(size: 14, weight: .heavy)).tracking(2).foregroundStyle(Theme.text)
                        Text("Tap to resume").font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.togglePause() }
                } else if s.isSleeping {
                    Color.black.opacity(0.65)
                    VStack(spacing: 6) {
                        Text("💤").font(.system(size: 44))
                        Text("SLEEPING — 8 HOURS PASSING…")
                            .font(.system(size: 12, weight: .heavy)).tracking(1)
                            .foregroundStyle(Theme.orange)
                    }
                }
            }
            .frame(minHeight: 150)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))

            portfolio(s)
            goalBar(s)
            actionBar(s)
            }
            if model.showOrderForm {
                OrderFormView(model: model)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
            }
            .clipped()
        }
        .background(Theme.bg)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: model.showOrderForm)
        .animation(.easeOut(duration: 0.2), value: model.indicators)
        .animation(.easeOut(duration: 0.18), value: model.showIndicatorMenu)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.banner?.id)
        .overlay(alignment: .top) {
            if let f = model.flash {
                Text(f).font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.orange, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 52)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.flash)
    }

    // MARK: Chart gestures

    @ViewBuilder
    private var chartGestures: some View {
        GeometryReader { g in
            let axis: CGFloat = 62
            HStack(spacing: 0) {
                // Drag the chart itself to move through time.
                Color.clear.contentShape(Rectangle())
                    // Press and hold, then drag: crosshair with price, date and time.
                    .highPriorityGesture(
                        LongPressGesture(minimumDuration: 0.22, maximumDistance: 12)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                guard case .second(true, let drag?) = value else { return }
                                if crosshair == nil { Feedback.play(.tap) }
                                crosshair = drag.location
                                let w = max((g.size.width - axis) / 48, 1)
                                let i = Int(drag.location.x / w)
                                if i != crosshairIndex { crosshairIndex = i; Feedback.play(.select) }
                            }
                            .onEnded { _ in crosshair = nil; crosshairIndex = -1 }
                    )
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { v in
                                let dx = v.translation.width - panLast
                                panLast = v.translation.width
                                let perCandle = max((g.size.width - axis) / 48, 1)
                                model.panChart(candlesBack: Double(dx / perCandle))
                            }
                            .onEnded { _ in panLast = 0 }
                    )
                // Drag the price scale up/down to stretch it, like an exchange chart.
                Color.clear.frame(width: axis).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                let dy = v.translation.height - zoomLast
                                zoomLast = v.translation.height
                                model.zoomPrice(by: exp(-Double(dy) / 140))
                            }
                            .onEnded { _ in zoomLast = 0 }
                    )
                    .onTapGesture(count: 2) { model.resetPriceScale() }
            }
        }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image("RobotEmojiOrange").resizable().scaledToFit().frame(width: 20, height: 20)
                    .frame(width: 26, height: 26)
                    .background(LinearGradient(colors: [Theme.orange, Theme.orangeDim],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 7))
                (Text("ORANGE").foregroundColor(Theme.text) + Text("ROBOT").foregroundColor(Theme.orange)
                 + Text(" TRADER").foregroundColor(Theme.text))
                    .font(.system(size: 13, weight: .black))
                Text("SIMULATOR")
                    .font(.system(size: 8, weight: .heavy)).tracking(1)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.dim, lineWidth: 1))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button { model.togglePause() } label: {
                Image(systemName: model.session.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Theme.orange, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(model.session.isPaused ? "Resume" : "Pause")
            Button { model.showInfo = true } label: {
                Text("ⓘ").font(.system(size: 13, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Theme.panel2, in: Circle())
                    .overlay(Circle().stroke(Theme.line))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func priceRow(_ s: GameSession) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("₿ BTC / USD").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim)
                Text(Fmt.usd(s.lastPrice))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                let chg = s.changeToday
                Text(String(format: "%@%.2f%% today", chg >= 0 ? "+" : "", chg))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(chg >= 0 ? Theme.green : Theme.red)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.date(s.currentDate)).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
                Text(Fmt.clock(minuteOfDay: s.minuteOfDay))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
    }

    private var controls: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach([(3, "3m"), (15, "15m"), (60, "1H"), (240, "4H"), (1440, "1D"), (10080, "1W")], id: \.0) { tf, label in
                    chip(label, active: model.timeframe == tf) {
                        if model.timeframe != tf { Feedback.play(.select) }
                        model.timeframe = tf
                    }
                }
            }
            Spacer()
            speedMenu
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var speedMenu: some View {
        let current = model.session.speed
        return Menu {
            ForEach(PlaybackSpeed.allCases, id: \.self) { sp in
                Button {
                    model.setSpeed(sp)
                } label: {
                    if sp == current {
                        Label(Self.speedTitle(sp), systemImage: "checkmark")
                    } else {
                        Text(Self.speedTitle(sp))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(Self.speedName(current)).font(.system(size: 11, weight: .bold))
                Text(Self.multiplierText(current)).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .opacity(0.75)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Theme.orange, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.black)
        }
    }

    static func speedName(_ s: PlaybackSpeed) -> String {
        switch s { case .actual: return "Actual"; case .normal: return "Normal"; case .fast: return "Fast" }
    }

    static func multiplierText(_ s: PlaybackSpeed) -> String {
        let m = s.multiplier
        return m >= 1000 ? String(format: "%.1fk×", m / 1000).replacingOccurrences(of: ".0k", with: "k") : String(format: "%.0f×", m)
    }

    static func speedTitle(_ s: PlaybackSpeed) -> String {
        switch s {
        case .actual: return "Actual — real time (1×)"
        case .normal: return "Normal — game speed (240×)"
        case .fast: return "Fast — fast forward (3,600×)"
        }
    }

    private func chip(_ t: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(active ? Theme.orange : Theme.panel2, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(active ? Color.black : Theme.dim)
        }
    }

    private func portfolio(_ s: GameSession) -> some View {
        HStack {
            stat("Cash", Fmt.compact(s.cash), Theme.text)
            stat("BTC Position", String(format: "%.5f ₿", s.btc), Theme.text)
            stat("Equity", Fmt.compact(s.equity), Theme.text)
            stat("P/L", (s.profitLoss >= 0 ? "+" : "") + Fmt.compact(s.profitLoss),
                 s.profitLoss >= 0 ? Theme.green : Theme.red)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.panel)
    }

    private func stat(_ l: String, _ v: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(l.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.5).foregroundStyle(Theme.dim)
            Text(v).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(c)
                .minimumScaleFactor(0.7).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    private func goalBar(_ s: GameSession) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text("$0"); Spacer()
                Text(String(format: "%.1f%%", s.goalProgress * 100)).foregroundStyle(Theme.orange)
                Spacer(); Text("$1,000,000")
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Theme.dim)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panel2)
                    Capsule().fill(LinearGradient(colors: [Theme.orangeDim, Theme.orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, g.size.width * s.goalProgress))
                }
            }.frame(height: 6)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: Actions

    private func actionBar(_ s: GameSession) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { model.showPositions = true } label: {
                    HStack(spacing: 6) {
                        Text("📊 Position & orders")
                        if !s.pendingOrders.isEmpty {
                            Text("\(s.pendingOrders.count)")
                                .font(.system(size: 11, weight: .black))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.orange, in: Capsule()).foregroundStyle(.black)
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(s.pendingOrders.isEmpty ? Theme.dim : Theme.orange)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 8))
                }
                Button { model.openNews() } label: {
                    HStack(spacing: 6) {
                        Text("📰 News")
                        if model.unreadNews > 0 {
                            Text("\(min(model.unreadNews, 99))")
                                .font(.system(size: 11, weight: .black))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.red, in: Capsule()).foregroundStyle(.white)
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(model.unreadNews > 0 ? Theme.text : Theme.dim)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack(spacing: 10) {
                tradeButton("BUY", .buy, Theme.green, s)
                tradeButton("SELL", .sell, Theme.red, s)
            }
            HStack(spacing: 8) {
                action("😴 Sleep 8h") { model.sleep() }.disabled(s.isSleeping || s.isPaused || s.isLive)
                action("🌅 +24h") { model.skipDay() }.disabled(s.isSleeping || s.isPaused || s.isLive)
                action("💰 Cash Out") { model.cashOut() }.disabled(s.isSleeping)
                action("↻ New") { model.showStartPicker = true }
            }
        }
        .padding(12)
        .background(Theme.panel)
    }

    /// Shown over the chart once the game is in real time (past the end of the real data).
    private var realTimeBanner: some View {
        VStack {
            HStack(spacing: 6) {
                Circle().fill(model.liveFeedFailed ? Theme.orange : Theme.green).frame(width: 7, height: 7)
                Text("REAL TIME").font(.system(size: 10, weight: .heavy)).tracking(1.5)
                Text(model.liveFeedFailed ? "· feed offline, holding last price"
                                          : "· live price, updates every 15 s")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.panel.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke((model.liveFeedFailed ? Theme.orange : Theme.green).opacity(0.7)))
            Spacer()
        }
        .padding(.top, 6)
        .allowsHitTesting(false)
    }

    private func tradeButton(_ t: String, _ side: Side, _ c: Color, _ s: GameSession) -> some View {
        Button { model.openOrderForm(side) } label: {
            Text(t).font(.system(size: 16, weight: .black)).tracking(1)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(c, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .disabled(s.isSleeping)
        .opacity(s.isSleeping ? 0.4 : 1)
    }

    private func action(_ t: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t).font(.system(size: 12, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                .foregroundStyle(Theme.text)
        }
    }
}
