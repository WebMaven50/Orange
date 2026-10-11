import Foundation

/// One saved experiment in the Lab notebook: either a single test of a rule
/// set or a whole "find me rules" search.
public struct Report: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case test, search }

    /// A rule set the finder turned up, with how it did on time it hadn't seen.
    public struct Found: Codable, Equatable, Sendable, Identifiable {
        public var id: String { strategy.name + "|" + String(strategy.hashValue) }
        public let strategy: Strategy
        public let trainReturn: Double
        public let trainHoldReturn: Double
        public let nextReturn: Double?
        public let nextHoldReturn: Double?
        /// Share of other periods that ended in profit / beat holding.
        public let otherPositiveShare: Double?
        public let otherBeatsHoldShare: Double?
        public let trades: Int
        public let verdict: Verdict

        public init(_ c: Candidate) {
            strategy = c.strategy
            trainReturn = c.train.totalReturn
            trainHoldReturn = c.trainBuyAndHold.totalReturn
            nextReturn = c.validation?.totalReturn
            nextHoldReturn = c.validationBuyAndHold?.totalReturn
            otherPositiveShare = c.robustness?.positiveShare
            otherBeatsHoldShare = c.robustness?.beatsHoldShare
            trades = c.train.trades
            verdict = c.verdict
        }
    }

    public let id: UUID
    public let kind: Kind
    public let createdAt: Date
    public var title: String
    /// The period the test ran over, or the finder's practice period.
    public let start: Date
    public let end: Date

    // Single test
    public let strategy: Strategy?
    public let result: Metrics?
    public let hold: Metrics?

    // Finder search
    public let tries: Int?
    public let found: [Found]

    public var notes: String
    public var starred: Bool

    public static func test(strategy: Strategy, start: Date, end: Date, result: Metrics, hold: Metrics,
                            now: Date = Date()) -> Report {
        Report(id: UUID(), kind: .test, createdAt: now, title: strategy.name, start: start, end: end,
               strategy: strategy, result: result, hold: hold, tries: nil, found: [], notes: "", starred: false)
    }

    public static func search(start: Date, end: Date, tries: Int, candidates: [Candidate],
                              now: Date = Date()) -> Report {
        Report(id: UUID(), kind: .search, createdAt: now, title: "Rule search", start: start, end: end,
               strategy: nil, result: nil, hold: nil, tries: tries,
               found: candidates.map(Found.init), notes: "", starred: false)
    }

    /// Score against just holding (0 = same, +100 = twice the money, −50 = half), for tests.
    public var scoreVsHold: Double? {
        guard kind == .test, let r = result, let h = hold else { return nil }
        return Score.vsHold(robotReturn: r.totalReturn, holdReturn: h.totalReturn)
    }

    /// One line for list rows.
    public var headline: String {
        switch kind {
        case .test:
            guard let r = result, let h = hold else { return "" }
            return "Robot \(Report.pct(r.totalReturn)) · holding \(Report.pct(h.totalReturn))"
        case .search:
            let good = found.filter { $0.verdict == .holdsUp }.count
            return "\(found.count) rule sets kept · \(good) beat holding on unseen time"
        }
    }

    /// Plain-text version for sharing or exporting.
    public var textSummary: String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .none
        f.timeZone = TimeZone(identifier: "UTC")
        var lines: [String] = []
        lines.append("ORANGE ROBOT LAB — \(kind == .test ? "Test" : "Rule search")")
        lines.append("\(title)")
        lines.append("Period: \(f.string(from: start)) – \(f.string(from: end))")
        switch kind {
        case .test:
            if let s = strategy {
                lines.append("")
                lines.append("RULES")
                if let d = s.dca {
                    lines.append("DCA: buys \(d.shortAmountText) \(d.label)")
                } else {
                    lines.append("Buy when " + s.entry.map(\.summary).joined(separator: " and "))
                }
                if !s.exit.isEmpty { lines.append("Sell when " + s.exit.map(\.summary).joined(separator: " or ")) }
                if let v = s.stopLossPercent { lines.append("Stop loss \(Report.g(v))%") }
                if let v = s.takeProfitPercent { lines.append("Take profit \(Report.g(v))%") }
                if let v = s.trailingStopPercent { lines.append("Trailing stop \(Report.g(v))%") }
                if let v = s.limitEntryDiscountPercent { lines.append("Limit buy \(Report.g(v))% below the signal") }
                if let v = s.maxHoldDays { lines.append("Sell after \(v) days") }
                lines.append("Uses \(Int(s.positionPercent))% of cash per buy")
            }
            if let r = result, let h = hold {
                lines.append("")
                lines.append("RESULT")
                lines.append("Robot: \(Report.pct(r.totalReturn)) · biggest fall \(Int(r.maxDrawdown * 100))% · \(r.trades) trades · \(Int(r.winRate * 100))% won")
                lines.append("Just holding: \(Report.pct(h.totalReturn)) · biggest fall \(Int(h.maxDrawdown * 100))%")
                if let sc = scoreVsHold { lines.append("Score vs holding: \(Score.label(sc))") }
            }
        case .search:
            lines.append("Ideas tried: \(tries ?? 0)")
            for (i, c) in found.enumerated() {
                lines.append("")
                lines.append("\(i + 1). \(c.strategy.name) — \(c.verdict.title)")
                lines.append("   Buy when " + c.strategy.entry.map(\.summary).joined(separator: " and "))
                lines.append("   Practice: \(Report.pct(c.trainReturn)) (holding \(Report.pct(c.trainHoldReturn)))")
                if let n = c.nextReturn, let nh = c.nextHoldReturn {
                    lines.append("   Next stretch, unseen: \(Report.pct(n)) (holding \(Report.pct(nh)))")
                }
            }
        }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("NOTES")
            lines.append(notes)
        }
        lines.append("")
        lines.append("Simulation on past data. Not financial advice.")
        lines.append("Made with Orange Robot Lab · theorangerobot.com")
        return lines.joined(separator: "\n")
    }

    static func pct(_ x: Double) -> String { String(format: "%@%.0f%%", x >= 0 ? "+" : "−", abs(x) * 100) }
    static func g(_ d: Double) -> String { String(format: "%g", d) }
}

/// The notebook: pure bookkeeping for a list of reports (persistence is the app's job).
public struct ReportBook: Codable, Equatable, Sendable {
    public private(set) var reports: [Report] = []
    public static let capacity = 500

    public init(reports: [Report] = []) { self.reports = reports }

    public enum Filter: String, CaseIterable, Sendable { case all, tests, searches, starred }

    /// Adds a report, newest first. A test of the same rules over the same period
    /// saved within a minute of the last one is treated as the same experiment.
    @discardableResult
    public mutating func add(_ r: Report) -> Bool {
        if r.kind == .test, let dup = reports.first(where: {
            $0.kind == .test && $0.strategy == r.strategy && $0.start == r.start && $0.end == r.end
                && abs($0.createdAt.timeIntervalSince(r.createdAt)) < 60
        }) { _ = dup; return false }
        reports.insert(r, at: 0)
        // Over capacity: drop the oldest that aren't starred.
        while reports.count > Self.capacity, let i = reports.lastIndex(where: { !$0.starred }) {
            reports.remove(at: i)
        }
        return true
    }

    public mutating func delete(_ id: UUID) { reports.removeAll { $0.id == id } }

    public mutating func setNotes(_ id: UUID, _ text: String) {
        if let i = reports.firstIndex(where: { $0.id == id }) { reports[i].notes = text }
    }

    public mutating func setTitle(_ id: UUID, _ text: String) {
        if let i = reports.firstIndex(where: { $0.id == id }) { reports[i].title = text }
    }

    public mutating func toggleStar(_ id: UUID) {
        if let i = reports.firstIndex(where: { $0.id == id }) { reports[i].starred.toggle() }
    }

    public func report(_ id: UUID) -> Report? { reports.first { $0.id == id } }

    public func filtered(_ f: Filter, query: String = "") -> [Report] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return reports.filter { r in
            switch f {
            case .all: break
            case .tests: if r.kind != .test { return false }
            case .searches: if r.kind != .search { return false }
            case .starred: if !r.starred { return false }
            }
            if q.isEmpty { return true }
            let hay = (r.title + " " + r.notes + " " + r.headline + " "
                       + (r.strategy?.entry.map(\.summary).joined(separator: " ") ?? "")).lowercased()
            return hay.contains(q)
        }
    }
}
