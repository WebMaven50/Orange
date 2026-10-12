import SwiftUI
import OrangeRobotKit

/// Change the price (or trail %) and size of a resting order.
struct EditOrderView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: GameModel
    let orderID: Int

    @State private var levelText = ""
    @State private var fraction = 0.5
    @State private var loaded = false
    @State private var error: String?
    @FocusState private var levelFocused: Bool

    private var order: PendingOrder? { model.session.pendingOrders.first { $0.id == orderID } }

    var body: some View {
        NavigationStack {
            Group {
                if let o = order {
                    form(o)
                } else {
                    Text("This order is no longer open.").foregroundStyle(Theme.dim)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Edit order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded, let o = order else { return }
            levelText = o.type == .trailing ? String(format: "%g", o.level) : String(format: "%.2f", o.level)
            fraction = o.amountFraction
            loaded = true
        }
    }

    private func form(_ o: PendingOrder) -> some View {
        let s = model.session
        let trailing = o.type == .trailing
        let max = s.maxAmount(for: o.side)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Text(o.side.rawValue.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(o.side == .buy ? Theme.green : Theme.red, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.white)
                    Text(o.type.rawValue.uppercased())
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("Now " + Fmt.usd(s.lastPrice, decimals: 0))
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.dim)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(trailing ? "TRAIL DISTANCE (%)" : (o.type == .limit ? "LIMIT PRICE (USD)" : "STOP PRICE (USD)"))
                        .font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.dim)
                    TextField("", text: $levelText)
                        .keyboardType(.decimalPad)
                        .focused($levelFocused)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .padding(12)
                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 6) {
                        if trailing {
                            ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { p in
                                chip("\(Int(p))%") { levelText = String(format: "%g", p) }
                            }
                        } else {
                            ForEach([-5.0, -1.0, 1.0, 5.0], id: \.self) { p in
                                chip(String(format: "%+.0f%%", p)) {
                                    levelText = String(format: "%.2f", s.lastPrice * (1 + p / 100))
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("SIZE").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.dim)
                        Spacer()
                        Text("\(Int((fraction * 100).rounded()))% ≈ \(Fmt.usd(max * fraction, decimals: 0))")
                            .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
                    }
                    HStack(spacing: 6) {
                        ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { p in
                            Button { fraction = p } label: {
                                Text("\(Int(p * 100))%").font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .background(abs(fraction - p) < 0.001 ? Theme.orange : Theme.panel2,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(abs(fraction - p) < 0.001 ? Color.black : Theme.text)
                            }
                        }
                    }
                    Slider(value: $fraction, in: 0.01...1).tint(Theme.orange)
                    Text("Size is a share of what's available when the order fills, so it stays correct as your balance changes.")
                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                }

                if let error {
                    Text(error).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.red)
                }

                Button { save(o) } label: {
                    Text("SAVE CHANGES").font(.system(size: 15, weight: .black)).tracking(0.5)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                Button(role: .destructive) {
                    model.cancel(o.id)
                    dismiss()
                } label: {
                    Text("Cancel this order").font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(Theme.red)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func chip(_ t: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t).font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                .foregroundStyle(Theme.text)
        }
    }

    private func save(_ o: PendingOrder) {
        levelFocused = false
        let level = Double(levelText.replacingOccurrences(of: ",", with: ""))
        guard let level, level > 0 else {
            error = o.type == .trailing ? "Enter a trail percentage above 0." : "Enter a price above 0."
            return
        }
        do {
            try model.updateOrder(id: o.id, level: level, fraction: fraction)
            dismiss()
        } catch OrderError.stopOnWrongSide(let side) {
            self.error = side == .sell
                ? "A sell stop must sit below the current price. To sell higher, use a limit order."
                : "A buy stop must sit above the current price. To buy lower, use a limit order."
        } catch {
            self.error = "Couldn't change the order right now."
        }
    }
}
