import SwiftUI
import OrangeRobotKit

enum StartChoice {
    case random
    case moment(Date)
}

/// "When do you want to trade?" — random (ranked) or a chosen date and time (practice).
struct StartPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (StartChoice) -> Void

    private let range = GameSession.startDateRange()
    @State private var moment: Date = StartPickerView.initialMoment()

    private static let lastKey = "tor_last_start_moment"

    private static func initialMoment() -> Date {
        let saved = UserDefaults.standard.double(forKey: lastKey)
        let r = GameSession.startDateRange()
        if saved > 0 { return min(max(Date(timeIntervalSince1970: saved), r.lowerBound), r.upperBound) }
        return Self.utc(2017, 12, 17, 9, 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Random
                    Button { start(.random) } label: {
                        VStack(spacing: 4) {
                            Text("🎲  RANDOM DATE").font(.system(size: 17, weight: .black)).tracking(1)
                            Text("A surprise window of real history.\nCounts for the leaderboard and virtual sats.")
                                .font(.system(size: 12)).multilineTextAlignment(.center).opacity(0.8)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                    }

                    HStack {
                        Rectangle().fill(Theme.line).frame(height: 1)
                        Text("OR PICK YOUR MOMENT").font(.system(size: 10, weight: .heavy)).tracking(1)
                            .foregroundStyle(Theme.dim).fixedSize()
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }

                    // Famous moments
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FAMOUS MOMENTS").font(.system(size: 10, weight: .heavy)).tracking(1)
                            .foregroundStyle(Theme.dim)
                        FlowChips(items: Self.presets) { p in
                            moment = p.date
                        }
                    }

                    // Date + time
                    VStack(spacing: 12) {
                        HStack {
                            Text("Date").foregroundStyle(Theme.text)
                            Spacer()
                            DatePicker("", selection: $moment, in: range, displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.compact)
                        }
                        HStack {
                            Text("Time").foregroundStyle(Theme.text)
                            Spacer()
                            DatePicker("", selection: $moment, in: range, displayedComponents: .hourAndMinute)
                                .labelsHidden().datePickerStyle(.compact)
                        }
                        Text("Game time is UTC. Data covers Jul 2010 – \(Self.lastPlayable(range)).")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                    .padding(14)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .environment(\.timeZone, TimeZone(identifier: "UTC")!)

                    Button { start(.moment(moment)) } label: {
                        VStack(spacing: 3) {
                            Text("START FROM THIS MOMENT").font(.system(size: 15, weight: .black)).tracking(0.5)
                            Text("Practice run — doesn't count for the leaderboard or virtual sats.")
                                .font(.system(size: 11)).opacity(0.7).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.orange, lineWidth: 1.5))
                        .foregroundStyle(Theme.orange)
                    }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Choose your start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func start(_ choice: StartChoice) {
        if case .moment(let d) = choice {
            UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Self.lastKey)
        }
        dismiss()
        onStart(choice)
    }

    // MARK: Presets

    struct Preset: Identifiable {
        let id = UUID()
        let title: String
        let date: Date
    }

    static let presets: [Preset] = [
        Preset(title: "Mt. Gox era · Apr 2013", date: utc(2013, 4, 10, 6, 0)),
        Preset(title: "2017 peak · Dec 2017", date: utc(2017, 12, 17, 9, 0)),
        Preset(title: "COVID crash · Mar 2020", date: utc(2020, 3, 12, 8, 0)),
        Preset(title: "2021 top · Nov 2021", date: utc(2021, 11, 10, 9, 0)),
        Preset(title: "FTX collapse · Nov 2022", date: utc(2022, 11, 8, 9, 0)),
    ]

    private static func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private static func lastPlayable(_ r: ClosedRange<Date>) -> String { Fmt.date(r.upperBound) }
}

/// Wrapping row of tappable chips.
private struct FlowChips: View {
    let items: [StartPickerView.Preset]
    let tap: (StartPickerView.Preset) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { p in
                Button { tap(p) } label: {
                    Text(p.title).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.panel2, in: Capsule())
                        .overlay(Capsule().stroke(Theme.line))
                        .foregroundStyle(Theme.text)
                }
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
