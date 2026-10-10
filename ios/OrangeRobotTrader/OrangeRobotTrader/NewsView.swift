import SwiftUI
import OrangeRobotKit

extension NewsTag {
    var label: String {
        switch self {
        case .bitcoin: return "BITCOIN"
        case .markets: return "MARKETS"
        case .regulation: return "REGULATION"
        case .security: return "SECURITY"
        case .tech: return "TECH"
        case .adoption: return "ADOPTION"
        }
    }
    var symbol: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .markets: return "chart.line.uptrend.xyaxis"
        case .regulation: return "building.columns.fill"
        case .security: return "exclamationmark.shield.fill"
        case .tech: return "cpu.fill"
        case .adoption: return "cart.fill"
        }
    }
    var color: Color {
        switch self {
        case .security: return Theme.red
        case .markets: return Theme.gold
        case .regulation: return Color(hex: 0x6AA9FF)
        case .tech: return Color(hex: 0xB28CFF)
        case .adoption: return Theme.green
        case .bitcoin: return Theme.orange
        }
    }
}

/// Flashes across the top of the chart when the game clock reaches a big event.
struct NewsBannerView: View {
    let item: NewsItem
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.tag.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(item.tag.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("BREAKING")
                            .font(.system(size: 9, weight: .black)).tracking(1.2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Theme.red, in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.white)
                        Text(item.tag.label)
                            .font(.system(size: 9, weight: .heavy)).tracking(1)
                            .foregroundStyle(item.tag.color)
                        Spacer()
                        Text(Fmt.date(Self.date(item)))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.dim)
                    }
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.red).frame(width: 3).padding(.vertical, 6)
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    static func date(_ item: NewsItem) -> Date {
        Date(timeIntervalSince1970: Double(item.dayNumber) * 86_400)
    }
}

/// Headlines up to the game's current date. Nothing later is ever shown.
struct NewsView: View {
    @Environment(\.dismiss) private var dismiss
    let model: GameModel

    var body: some View {
        let today = model.session.currentDayNumber
        let items = model.visibleNews(limit: 80)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups(items, today: today), id: \.0) { title, rows in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(title).font(.system(size: 10, weight: .heavy)).tracking(1.5)
                                .foregroundStyle(Theme.dim)
                            ForEach(rows) { row($0) }
                        }
                    }
                    if items.isEmpty {
                        Text("No headlines yet — it's early in Bitcoin's story.")
                            .font(.system(size: 13)).foregroundStyle(Theme.dim)
                    }
                    Text("Real events, shown only up to the game's current date — nothing from the future. Price levels in headlines follow this game's daily data, which can differ slightly from other sources.")
                        .font(.system(size: 11)).foregroundStyle(Theme.dim).padding(.top, 6)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("📰 News")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.markNewsSeen() }
    }

    private func groups(_ items: [NewsItem], today: Int) -> [(String, [NewsItem])] {
        var buckets: [(String, [NewsItem])] = [("TODAY", []), ("THIS WEEK", []), ("THIS MONTH", []), ("EARLIER", [])]
        for i in items {
            let age = today - i.dayNumber
            let k = age == 0 ? 0 : age <= 7 ? 1 : age <= 31 ? 2 : 3
            buckets[k].1.append(i)
        }
        return buckets.filter { !$0.1.isEmpty }
    }

    private func row(_ i: NewsItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: i.tag.symbol).foregroundStyle(i.tag.color).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(Fmt.date(NewsBannerView.date(i)))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.dim)
                    Text(i.tag.label).font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(i.tag.color)
                }
                Text(i.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let d = i.detail {
                    Text(d).font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}
