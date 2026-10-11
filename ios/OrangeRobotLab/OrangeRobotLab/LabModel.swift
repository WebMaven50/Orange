import SwiftUI
import UserNotifications
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
        ("2023–24", DateSpan(start: utc(2023, 1, 1), end: utc(2024, 12, 31))),
        ("2025", DateSpan(start: utc(2025, 1, 1), end: utc(2025, 12, 31))),
        ("2026 so far", DateSpan(start: utc(2026, 1, 1), end: utc(2026, 12, 31))),
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
        loadLive()
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

    // MARK: Live (forward) tests

    var liveTests: [LiveTest] = []
    var candles: [DailyCandle] = []
    var candleSource: String?
    var candlesUpdated: Date?
    var refreshing = false
    var refreshError: String?

    private let liveURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("lab_live.json")
    }()

    private struct LiveFile: Codable {
        var tests: [LiveTest]; var candles: [DailyCandle]; var source: String?; var updated: Date?
    }

    private func loadLive() {
        guard let data = try? Data(contentsOf: liveURL),
              let f = try? JSONDecoder().decode(LiveFile.self, from: data) else { return }
        liveTests = f.tests; candles = f.candles; candleSource = f.source; candlesUpdated = f.updated
    }

    private func persistLive() {
        let f = LiveFile(tests: liveTests, candles: candles, source: candleSource, updated: candlesUpdated)
        if let data = try? JSONEncoder().encode(f) { try? data.write(to: liveURL, options: .atomic) }
    }

    func startLiveTest(_ strategy: Strategy, horizon: Int) {
        liveTests.insert(LiveTest(strategy: strategy, horizonDays: horizon), at: 0)
        Feedback.play(.tap)
        persistLive()
        Task { await refreshLive() }
    }

    func deleteLiveTest(_ id: UUID) {
        liveTests.removeAll { $0.id == id }
        persistLive()
    }

    func liveStatus(_ t: LiveTest) -> LiveStatus { LiveEvaluator.evaluate(t, candles: candles) }

    /// Pull the latest daily candles and refresh every running test.
    func refreshLive() async {
        guard !refreshing else { return }
        refreshing = true; refreshError = nil
        defer { refreshing = false }
        do {
            let fetched = try await LiveClient().fetch()
            candles = fetched.candles
            candleSource = fetched.source
            candlesUpdated = Date()
        } catch {
            refreshError = candles.isEmpty
                ? "Couldn't reach the price feed. Check your connection and try again."
                : "Couldn't refresh just now, so this is the last data we have."
        }
        recordFinishedTests()
        announceNewTrades()
        updateReminders()
        persistLive()
    }

    // MARK: Notifications

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "lab_notify") }
        set { UserDefaults.standard.set(newValue, forKey: "lab_notify"); updateReminders() }
    }

    /// Tell the player about robot trades they haven't heard about yet.
    private func announceNewTrades() {
        for i in liveTests.indices {
            let t = liveTests[i]
            let events = LiveEvaluator.newEvents(liveStatus(t), after: t.lastNotifiedDay)
            guard let newest = events.map(\.day).max() else { continue }
            if notificationsEnabled {
                for e in events.suffix(3) {
                    LabNotifications.post(title: "Orange Robot Lab", body: e.message(robot: t.name))
                }
            }
            // Always tell the player in-app, quietly.
            if let last = events.last { Feedback.play(last.kind == .bought ? .buy : .sell) }
            liveTests[i].lastNotifiedDay = newest
        }
    }

    private func updateReminders() {
        let active = liveTests.contains { liveStatus($0).phase != .finished }
        LabNotifications.setDailyReminder(notificationsEnabled && active)
        if active { LabNotifications.scheduleBackgroundRefresh() }
    }

    /// Called from the system's background refresh. Best effort: iOS may never run it.
    func backgroundRefresh() async {
        await refreshLive()
    }

    /// Finished tests go into the notebook on their own.
    private func recordFinishedTests() {
        for i in liveTests.indices where !liveTests[i].recordedInNotebook {
            let t = liveTests[i]
            let s = liveStatus(t)
            guard s.phase == .finished, let r = s.robotMetrics, let h = s.holdMetrics else { continue }
            let start = Date(timeIntervalSince1970: Double(t.startDay) * 86_400)
            let end = Date(timeIntervalSince1970: Double(t.startDay + t.horizonDays - 1) * 86_400)
            let report = Report.test(strategy: t.strategy, start: start, end: end, result: r, hold: h)
            if book.add(report) {
                book.setTitle(report.id, "Live test · \(t.name)")
                book.setNotes(report.id, "Forward test on days that had not happened when the rules were locked. Fingerprint \(t.fingerprint.prefix(12)).")
                persistBook()
            }
            liveTests[i].recordedInNotebook = true
        }
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

    /// "Dip buyer" -> "Dip buyer 2" if that name is already one of your robots.
    func uniqueName(_ base: String) -> String {
        let taken = Set(saved.map(\.name))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
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
