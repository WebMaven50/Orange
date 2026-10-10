import SwiftUI
import OrangeRobotKit

/// Everything you currently hold or have pending: your position, open orders
/// (with a cancel button for each) and recent fills.
struct PositionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: GameModel
    @State private var confirmClose = false
    @State private var editing: Int?

    var body: some View {
        let s = model.session
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Orders first when there are any: that's what you open this page to manage.
                    if !s.pendingOrders.isEmpty { ordersSection(s) }
                    positionCard(s)
                    if s.pendingOrders.isEmpty { ordersSection(s) }
                    fillsSection(s)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Positions & Orders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: Binding(get: { editing.map { EditTarget(id: $0) } },
                                 set: { editing = $0?.id })) { t in
                EditOrderView(model: model, orderID: t.id)
                    .presentationDetents([.large])
            }
            .confirmationDialog("Close your whole position at the market price?",
                                isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Close position", role: .destructive) {
                    model.closePosition()
                }
                Button("Keep it", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Position

    private func positionCard(_ s: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("POSITION").font(.system(size: 10, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                Spacer()
                if s.hasPosition {
                    Text(s.btc > 0 ? "LONG" : "SHORT")
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(s.btc > 0 ? Theme.green : Theme.red, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.white)
                }
            }
            if s.hasPosition {
                Text(String(format: "%.5f ₿", abs(s.btc)))
                    .font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
                Text("≈ " + Fmt.usd(abs(s.btc) * s.lastPrice, decimals: 0))
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.dim)
                Divider().overlay(Theme.line)
                stat("Average entry", Fmt.usd(s.averageEntry ?? 0))
                stat("Current price", Fmt.usd(s.lastPrice))
                stat("Unrealized P/L", signed(s.unrealizedPL) + String(format: "  (%+.2f%%)", s.unrealizedPercent),
                     color: s.unrealizedPL >= 0 ? Theme.green : Theme.red)
                Button { confirmClose = true } label: {
                    Text("CLOSE POSITION").font(.system(size: 14, weight: .black)).tracking(0.5)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.orange, lineWidth: 1.5))
                        .foregroundStyle(Theme.orange)
                }
                .disabled(s.isSleeping)
            } else {
                Text("No open position").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                Text("You're fully in cash. Buy or sell from the main screen to open one.")
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            Divider().overlay(Theme.line)
            stat("Cash", Fmt.usd(s.cash, decimals: 0))
            stat("Equity", Fmt.usd(s.equity, decimals: 0))
            stat("Realized P/L", signed(s.realizedPL), color: s.realizedPL >= 0 ? Theme.green : Theme.red)
            stat("Fees paid", Fmt.usd(s.feesPaid))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ l: String, _ v: String, color: Color = Theme.text) -> some View {
        HStack {
            Text(l).font(.system(size: 13)).foregroundStyle(Theme.dim)
            Spacer()
            Text(v).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(color)
        }
    }

    private func signed(_ n: Double) -> String { (n >= 0 ? "+" : "−") + Fmt.usd(abs(n)) }

    // MARK: Open orders

    private func ordersSection(_ s: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("OPEN ORDERS (\(s.pendingOrders.count))")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
                Spacer()
                if s.pendingOrders.count > 1 {
                    Button("Cancel all") { model.cancelAll() }
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.red)
                }
            }
            if s.pendingOrders.isEmpty {
                Text("No resting orders. Limit, stop and trailing orders you place will show here.")
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
            } else {
                ForEach(s.pendingOrders) { o in orderRow(o, s) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func orderRow(_ o: PendingOrder, _ s: GameSession) -> some View {
        let trigger = s.triggerPrice(for: o)
        let away = s.lastPrice > 0 ? (trigger - s.lastPrice) / s.lastPrice * 100 : 0
        let kind = o.type == .limit ? "LIMIT" : o.type == .stop ? "STOP" : "TRAILING \(String(format: "%g", o.level))%"
        return HStack(alignment: .top, spacing: 10) {
            Text(o.side.rawValue.uppercased())
                .font(.system(size: 10, weight: .black))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(o.side == .buy ? Theme.green : Theme.red, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(kind) @ \(Fmt.usd(trigger, decimals: 0))")
                    .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
                Text("≈ \(Fmt.compact(s.liveAmount(for: o))) · \(Int(o.amountFraction * 100))% of available")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                Text(String(format: "%.1f%% %@ the current price", abs(away), away >= 0 ? "above" : "below"))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Spacer()
            VStack(spacing: 6) {
                Button { editing = o.id } label: {
                    Text("Edit").font(.system(size: 12, weight: .bold))
                        .frame(width: 62).padding(.vertical, 6)
                        .background(Theme.orange, in: Capsule())
                        .foregroundStyle(.black)
                }
                Button { model.cancel(o.id) } label: {
                    Text("Cancel").font(.system(size: 12, weight: .bold))
                        .frame(width: 62).padding(.vertical, 6)
                        .background(Theme.panel, in: Capsule())
                        .overlay(Capsule().stroke(Theme.line))
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .padding(10)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Fills

    private func fillsSection(_ s: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT TRADES").font(.system(size: 10, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
            if s.fills.isEmpty {
                Text("No trades yet.").font(.system(size: 12)).foregroundStyle(Theme.dim)
            } else {
                ForEach(s.fills.prefix(20)) { f in
                    HStack(alignment: .firstTextBaseline) {
                        Text(f.side.rawValue.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(f.side == .buy ? Theme.green : Theme.red)
                            .frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.5f ₿ @ ", f.quantity) + Fmt.usd(f.price, decimals: 0))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.text)
                            Text(when(f, s) + (f.via == .market ? "" : " · \(f.via.rawValue)"))
                                .font(.system(size: 10)).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Text("fee " + Fmt.usd(f.fee))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.dim)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func when(_ f: Fill, _ s: GameSession) -> String {
        let day = Int(floor(f.absMinute / 1440))
        let m = Int(f.absMinute.truncatingRemainder(dividingBy: 1440))
        return Fmt.date(s.engine.date(forDayOffset: day)) + " " + Fmt.clock(minuteOfDay: max(0, m))
    }
}

private struct EditTarget: Identifiable { let id: Int }
