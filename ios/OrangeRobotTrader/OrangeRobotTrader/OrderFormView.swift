import SwiftUI
import OrangeRobotKit

/// Full order form that slides up over the chart. The market keeps running
/// behind it (price stays live in the header), so there is room for a proper
/// amount field, price nudges and a cost summary.
struct OrderFormView: View {
    @Bindable var model: GameModel

    private enum Field { case amount, level }
    @FocusState private var focus: Field?
    @State private var amountDraft = ""

    var body: some View {
        let s = model.session
        VStack(spacing: 0) {
            header(s)
            ScrollView {
                VStack(spacing: 16) {
                    sideTabs
                    typeSection
                    if model.needsLevel { levelSection(s) }
                    amountSection(s)
                    summary(s)
                    if !s.pendingOrders.isEmpty { openOrders(s) }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            confirmBar(s)
        }
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.orange).frame(height: 2) }
        .onChange(of: focus) { _, f in
            if f == .amount { amountDraft = String(format: "%.2f", model.amountUSD) }
        }
    }

    // MARK: Header

    private func header(_ s: GameSession) -> some View {
        VStack(spacing: 10) {
            Capsule().fill(Theme.line).frame(width: 40, height: 4).padding(.top, 8)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLACE ORDER").font(.system(size: 11, weight: .heavy)).tracking(1.5)
                        .foregroundStyle(Theme.dim)
                    Text(Fmt.usd(s.lastPrice))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                }
                Spacer()
                HStack(spacing: 14) {
                    miniStat("CASH", Fmt.compact(s.cash))
                    miniStat("BTC", String(format: "%.4f", s.btc))
                    miniStat("EQUITY", Fmt.compact(s.equity))
                }
                Button { close() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.dim)
                }.padding(.leading, 6)
            }
            .padding(.horizontal, 16)
            if s.isPaused {
                Text("⏸ Market is paused — orders fill at the frozen price")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.orange)
            }
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func miniStat(_ l: String, _ v: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(l).font(.system(size: 8, weight: .bold)).tracking(0.5).foregroundStyle(Theme.dim)
            Text(v).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
    }

    // MARK: Side + type

    private var sideTabs: some View {
        HStack(spacing: 0) {
            sideTab("BUY", .buy, Theme.green)
            sideTab("SELL", .sell, Theme.red)
        }
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sideTab(_ t: String, _ side: Side, _ c: Color) -> some View {
        Button { model.setSide(side) } label: {
            Text(t).font(.system(size: 15, weight: .heavy))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(model.side == side ? c : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(model.side == side ? Color.white : Theme.dim)
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach([(OrderType.market, "Market"), (.limit, "Limit"), (.stop, "Stop"), (.trailing, "Trailing")], id: \.0) { t, l in
                    Button { model.setOrderType(t) } label: {
                        Text(l).font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(model.orderType == t ? Theme.orange : Theme.panel2,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(model.orderType == t ? Color.black : Theme.dim)
                    }
                }
            }
            Text(description).font(.system(size: 12)).foregroundStyle(Theme.dim)
        }
    }

    private var description: String {
        switch (model.orderType, model.side) {
        case (.market, _): return "Fills instantly at the current price."
        case (.limit, .buy): return "Buys when the price falls to your limit or lower."
        case (.limit, .sell): return "Sells when the price rises to your limit or higher."
        case (.stop, .buy): return "Buys when the price rises to your stop — to chase a breakout."
        case (.stop, .sell): return "Sells when the price falls to your stop — a stop-loss."
        case (.trailing, .sell): return "Sells when the price drops this far from its best price since you placed it."
        case (.trailing, .buy): return "Buys when the price rises this far from its lowest price since you placed it."
        }
    }

    // MARK: Price level

    private func levelSection(_ s: GameSession) -> some View {
        let trailing = model.orderType == .trailing
        return VStack(alignment: .leading, spacing: 8) {
            Text(trailing ? "TRAIL DISTANCE (%)" : (model.orderType == .limit ? "LIMIT PRICE (USD)" : "STOP PRICE (USD)"))
                .font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.dim)
            TextField("", text: $model.levelText)
                .keyboardType(.decimalPad)
                .focused($focus, equals: .level)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .padding(12)
                .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.text)
            HStack(spacing: 6) {
                if trailing {
                    ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { p in
                        nudge("\(Int(p))%") { model.levelText = String(format: "%g", p) }
                    }
                } else {
                    ForEach([-5.0, -1.0, 1.0, 5.0], id: \.self) { p in
                        nudge(String(format: "%+.0f%%", p)) {
                            model.levelText = String(format: "%.2f", s.lastPrice * (1 + p / 100))
                        }
                    }
                    nudge("Market") { model.levelText = String(format: "%.2f", s.lastPrice) }
                }
            }
        }
    }

    private func nudge(_ t: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t).font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                .foregroundStyle(Theme.text)
        }
    }

    // MARK: Amount

    private func amountSection(_ s: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AMOUNT (USD)").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.dim)
                Spacer()
                Text("Max \(Fmt.usd(model.maxAmount, decimals: 0))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 6) {
                Text("$").font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(Theme.dim)
                TextField("0", text: Binding(
                    get: { focus == .amount ? amountDraft : String(format: "%.2f", model.amountUSD) },
                    set: { new in
                        amountDraft = new
                        let v = Double(new.replacingOccurrences(of: ",", with: ""))
                        if let v, model.maxAmount > 0 { model.fraction = min(max(v / model.maxAmount, 0), 1) }
                    }))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }
            .padding(12)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 6) {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { p in
                    Button { focus = nil; model.fraction = p } label: {
                        Text("\(Int(p * 100))%").font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(abs(model.fraction - p) < 0.001 ? Theme.orange : Theme.panel2,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(abs(model.fraction - p) < 0.001 ? Color.black : Theme.text)
                    }
                }
            }
            Slider(value: $model.fraction, in: 0...1).tint(Theme.orange)
        }
    }

    // MARK: Summary

    private func summary(_ s: GameSession) -> some View {
        let amt = model.amountUSD
        let qty = s.lastPrice > 0 ? amt / s.lastPrice : 0
        let fee = amt * GameSession.fee
        let isShort = model.side == .sell && s.btc <= 0
        return VStack(spacing: 6) {
            row("Quantity", String(format: "≈ %.5f ₿", qty))
            row("Fee (0.26%)", Fmt.usd(fee))
            row(model.side == .buy ? "You pay" : "You receive",
                Fmt.usd(model.side == .buy ? amt : amt - fee), bold: true)
            if isShort {
                Text("You hold no BTC, so this opens a **short**: you borrow BTC and profit if the price falls. Losses can wipe you out.")
                    .font(.system(size: 11)).foregroundStyle(Theme.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            }
        }
        .padding(12)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ l: String, _ v: String, bold: Bool = false) -> some View {
        HStack {
            Text(l).foregroundStyle(Theme.dim)
            Spacer()
            Text(v).font(.system(size: 13, weight: bold ? .bold : .regular, design: .monospaced))
                .foregroundStyle(Theme.text)
        }.font(.system(size: 13))
    }

    // MARK: Open orders

    private func openOrders(_ s: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPEN ORDERS").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.dim)
            ForEach(s.pendingOrders) { o in
                HStack {
                    Text(o.side.rawValue.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(o.side == .buy ? Theme.green : Theme.red, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                    let detail = o.type == .trailing ? "trail \(String(format: "%g", o.level))%"
                                                     : "@ " + Fmt.usd(o.level, decimals: 0)
                    Text("\(o.type.rawValue.uppercased()) \(detail) · \(Int(o.amountFraction * 100))% (~\(Fmt.compact(s.liveAmount(for: o))))")
                        .font(.system(size: 12)).foregroundStyle(Theme.text)
                    Spacer()
                    Button { model.cancel(o.id) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Confirm

    private func confirmBar(_ s: GameSession) -> some View {
        let verb = model.side == .buy ? "BUY" : (s.btc > 0 ? "SELL" : "SHORT")
        let kind = model.orderType == .market ? "" : " (\(model.orderType.rawValue.uppercased()))"
        return Button {
            focus = nil
            model.submit()
        } label: {
            Text("\(verb) \(Fmt.compact(model.amountUSD)) OF BTC\(kind)")
                .font(.system(size: 16, weight: .black)).tracking(0.5)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(model.side == .buy ? Theme.green : Theme.red, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .disabled(s.isSleeping || model.amountUSD < 1)
        .opacity(s.isSleeping || model.amountUSD < 1 ? 0.45 : 1)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func close() {
        focus = nil
        model.showOrderForm = false
    }
}
