import SwiftUI
import Observation
import OrangeRobotKit

/// A chosen stretch of history, in calendar dates (UTC).
struct DateSpan: Hashable {
    var start: Date
    var end: Date

    static func utc(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d))!
    }

    static let presets: [(String, DateSpan)] = [
        ("2013 boom & bust", DateSpan(start: utc(2013, 1, 1), end: utc(2013, 12, 31))),
        ("2015 bear", DateSpan(start: utc(2015, 1, 1), end: utc(2015, 12, 31))),
        ("2017 mania", DateSpan(start: utc(2017, 1, 1), end: utc(2017, 12, 31))),
        ("2018 bear", DateSpan(start: utc(2018, 1, 1), end: utc(2018, 12, 31))),
        ("2020–21 bull", DateSpan(start: utc(2020, 6, 1), end: utc(2021, 5, 31))),
        ("2022 crash", DateSpan(start: utc(2022, 1, 1), end: utc(2022, 12, 31))),
        ("2023–24", DateSpan(start: utc(2023, 1, 1), end: utc(2024, 8, 31))),
    ]
}

@MainActor @Observable
final class LabModel {
    let backtester = Backtester()
    var saved: [Strategy] = []

    private let key = "lab_saved_strategies"

    /// The notebook: every test and search is recorded here automatically.
    var book = ReportBook()
    private let bookURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("lab_reports.json")
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Strategy].self, from: data) {
            saved = list
        }
        if let data = try? Data(contentsOf: bookURL),
           let b = try? JSONDecoder().decode(ReportBook.self, from: data) {
            book = b
        }
    }

    // MARK: Notebook

    func recordTest(strategy: Strategy, span: DateSpan, result: Metrics, hold: Metrics) {
        let r = Report.test(strategy: strategy, start: span.start, end: span.end, result: result, hold: hold)
        if book.add(r) { persistBook() }
    }

    func recordSearch(span: DateSpan, tries: Int, candidates: [Candidate]) {
        guard !candidates.isEmpty else { return }
        book.add(Report.search(start: span.start, end: span.end, tries: tries, candidates: candidates))
        persistBook()
    }

    func setNotes(_ id: UUID, _ text: String) { book.setNotes(id, text); persistBook() }
    func setTitle(_ id: UUID, _ text: String) { book.setTitle(id, text); persistBook() }
    func toggleStar(_ id: UUID) { book.toggleStar(id); persistBook() }
    func deleteReport(_ id: UUID) { book.delete(id); persistBook() }

    private func persistBook() {
        if let data = try? JSONEncoder().encode(book) { try? data.write(to: bookURL, options: .atomic) }
    }

    var dataStart: Date { backtester.date(forDay: 0) }
    var dataEnd: Date { backtester.date(forDay: backtester.dayCount - 1) }

    func range(for span: DateSpan) -> Range<Int> {
        let a = backtester.dayIndex(for: span.start)
        let b = backtester.dayIndex(for: span.end)
        return a..<(max(a, b) + 1)
    }

    func save(_ s: Strategy) {
        if let i = saved.firstIndex(where: { $0.name == s.name }) { saved[i] = s } else { saved.insert(s, at: 0) }
        persist()
    }

    func delete(at offsets: IndexSet) {
        saved.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Small shared UI helpers

enum Money {
    static func pct(_ x: Double, digits: Int = 0) -> String {
        String(format: "%@%.\(digits)f%%", x >= 0 ? "+" : "−", abs(x) * 100)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.dim)
    }
}
