import SwiftUI
import OrangeRobotKit

struct NotebookView: View {
    @Environment(LabModel.self) private var lab
    @State private var filter: ReportBook.Filter = .all
    @State private var query = ""
    @State private var comparing = false
    @State private var picked: [UUID] = []
    @State private var showCompare = false

    var body: some View {
        let rows = lab.book.filtered(filter, query: query)
        ScrollView {
            VStack(spacing: 12) {
                Picker("", selection: $filter) {
                    Text("All").tag(ReportBook.Filter.all)
                    Text("Tests").tag(ReportBook.Filter.tests)
                    Text("Searches").tag(ReportBook.Filter.searches)
                    Text("★").tag(ReportBook.Filter.starred)
                }
                .pickerStyle(.segmented)

                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Text("📓").font(.system(size: 40))
                        Text(lab.book.reports.isEmpty ? "Nothing here yet" : "No matches")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                        Text("Run a test or a rule search and it will be saved here automatically.")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    }.padding(.top, 40)
                }

                ForEach(rows) { r in
                    if comparing {
                        Button { toggle(r) } label: { row(r, selected: picked.contains(r.id)) }
                            .disabled(r.kind != .test)
                            .opacity(r.kind == .test ? 1 : 0.4)
                    } else {
                        NavigationLink { ReportDetailView(id: r.id) } label: { row(r, selected: false) }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Notebook")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search notes, names, rules")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(comparing ? "Cancel" : "Compare") {
                    comparing.toggle(); picked = []
                }
                .disabled(lab.book.reports.filter { $0.kind == .test }.count < 2)
            }
            if comparing && picked.count == 2 {
                ToolbarItem(placement: .bottomBar) {
                    Button("Compare these two") { showCompare = true }.font(.system(size: 15, weight: .bold))
                }
            }
        }
        .navigationDestination(isPresented: $showCompare) {
            if picked.count == 2, let a = lab.book.report(picked[0]), let b = lab.book.report(picked[1]) {
                CompareView(a: a, b: b)
            }
        }
    }

    private func toggle(_ r: Report) {
        if let i = picked.firstIndex(of: r.id) { picked.remove(at: i) }
        else if picked.count < 2 { picked.append(r.id) }
    }

    private func row(_ r: Report, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(r.kind == .test ? "🧪" : "🔎").font(.system(size: 24))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(r.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    if r.starred { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Theme.gold) }
                }
                Text(r.headline).font(.system(size: 12)).foregroundStyle(Theme.dim).multilineTextAlignment(.leading)
                Text("\(Fmt.date(r.start)) – \(Fmt.date(r.end)) · saved \(r.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(Theme.dim)
                if !r.notes.isEmpty {
                    Text("“\(r.notes)”").font(.system(size: 11)).foregroundStyle(Theme.orange).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            if comparing {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.orange : Theme.dim)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.orange : Color.clear, lineWidth: 1.5))
    }
}

// MARK: - One report

struct ReportDetailView: View {
    @Environment(LabModel.self) private var lab
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let r = lab.book.report(id) { content(r) }
            else { Text("This report was deleted.").foregroundStyle(Theme.dim) }
        }
        .background(Theme.bg)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let r = lab.book.report(id) {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { lab.toggleStar(r.id) } label: {
                        Image(systemName: r.starred ? "star.fill" : "star").foregroundStyle(Theme.gold)
                    }
                    ShareLink(item: r.textSummary)
                    Button { confirmDelete = true } label: { Image(systemName: "trash") }
                }
            }
        }
        .confirmationDialog("Delete this report?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { lab.deleteReport(id); dismiss() }
            Button("Keep it", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func content(_ r: Report) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Title", text: Binding(get: { r.title }, set: { lab.setTitle(r.id, $0) }))
                            .font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.text)
                        Text("\(Fmt.date(r.start)) – \(Fmt.date(r.end))")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.dim)
                        Text("Saved \(r.createdAt.formatted(date: .long, time: .shortened))")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                }

                if r.kind == .test { testBody(r) } else { searchBody(r) }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("My notes")
                        TextEditor(text: Binding(get: { r.notes }, set: { lab.setNotes(r.id, $0) }))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                            .padding(8)
                            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Theme.text)
                        Text("Write your thesis, what you'd change, or what to try next.")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                }
            }
            .padding(16)
        }
    }

    private func testBody(_ r: Report) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let res = r.result, let hold = r.hold {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                SectionLabel("Robot")
                                Text(Money.pct(res.totalReturn))
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundStyle(res.totalReturn >= 0 ? Theme.green : Theme.red)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                SectionLabel("Just holding")
                                Text(Money.pct(hold.totalReturn))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(Theme.dim)
                            }
                        }
                        Text("Biggest fall \(Int(res.maxDrawdown * 100))% (holding \(Int(hold.maxDrawdown * 100))%) · \(res.trades) trades · \(Int(res.winRate * 100))% won · invested \(Int(res.exposure * 100))% of the time")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                }
            }
            if let s = r.strategy {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Rules")
                        ForEach(s.entry, id: \.self) { Text("BUY when " + $0.summary).font(.system(size: 13)).foregroundStyle(Theme.green) }
                        ForEach(s.exit, id: \.self) { Text("SELL when " + $0.summary).font(.system(size: 13)).foregroundStyle(Theme.red) }
                        if let v = s.stopLossPercent { Text("Stop loss \(String(format: "%g", v))%").font(.system(size: 13)).foregroundStyle(Theme.text) }
                        if let v = s.takeProfitPercent { Text("Take profit \(String(format: "%g", v))%").font(.system(size: 13)).foregroundStyle(Theme.text) }
                        if let v = s.trailingStopPercent { Text("Trailing stop \(String(format: "%g", v))%").font(.system(size: 13)).foregroundStyle(Theme.text) }
                        if let v = s.limitEntryDiscountPercent { Text("Limit buy \(String(format: "%g", v))% below").font(.system(size: 13)).foregroundStyle(Theme.text) }
                        Text("Uses \(Int(s.positionPercent))% of cash").font(.system(size: 13)).foregroundStyle(Theme.dim)
                    }
                }
                let span = DateSpan(start: r.start, end: r.end)
                NavigationLink { ReplayView(strategy: s, span: span) } label: {
                    Label("Watch the replay", systemImage: "play.circle.fill").font(.system(size: 15, weight: .black))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
                }
                NavigationLink { BuilderView(strategy: s) } label: {
                    Text("Open these rules in the builder").font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                        .foregroundStyle(Theme.text)
                }
            }
        }
    }

    private func searchBody(_ r: Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tried \((r.tries ?? 0).formatted()) rule sets, kept \(r.found.count).")
                .font(.system(size: 13)).foregroundStyle(Theme.dim)
            ForEach(r.found) { f in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(f.strategy.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(f.verdict.title.uppercased()).font(.system(size: 9, weight: .black)).tracking(0.6)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(Theme.orange.opacity(0.18), in: Capsule()).foregroundStyle(Theme.orange)
                        }
                        Text("Buy when " + f.strategy.entry.map(\.summary).joined(separator: " and "))
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                        Text("Practice \(Money.pct(f.trainReturn)) (holding \(Money.pct(f.trainHoldReturn)))"
                             + (f.nextReturn.map { " · Next \(Money.pct($0))" } ?? ""))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                        NavigationLink { BuilderView(strategy: f.strategy) } label: {
                            Text("Open in builder").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Compare

struct CompareView: View {
    let a: Report
    let b: Report

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    header(a, Theme.orange)
                    header(b, Color(hex: 0x6AA9FF))
                }
                if let ra = a.result, let rb = b.result, let ha = a.hold, let hb = b.hold {
                    table([
                        ("Return", Money.pct(ra.totalReturn), Money.pct(rb.totalReturn), ra.totalReturn >= rb.totalReturn),
                        ("Holding did", Money.pct(ha.totalReturn), Money.pct(hb.totalReturn), nil),
                        ("Beat holding by", Money.pct(ra.totalReturn - ha.totalReturn), Money.pct(rb.totalReturn - hb.totalReturn),
                         (ra.totalReturn - ha.totalReturn) >= (rb.totalReturn - hb.totalReturn)),
                        ("Biggest fall", "\(Int(ra.maxDrawdown * 100))%", "\(Int(rb.maxDrawdown * 100))%", ra.maxDrawdown <= rb.maxDrawdown),
                        ("Trades", "\(ra.trades)", "\(rb.trades)", nil),
                        ("Winning trades", "\(Int(ra.winRate * 100))%", "\(Int(rb.winRate * 100))%", ra.winRate >= rb.winRate),
                        ("Time invested", "\(Int(ra.exposure * 100))%", "\(Int(rb.exposure * 100))%", nil),
                        ("Steadiness", String(format: "%.2f", ra.sharpe), String(format: "%.2f", rb.sharpe), ra.sharpe >= rb.sharpe),
                    ])
                }
                if a.start != b.start || a.end != b.end {
                    Text("⚠️ These were tested over different periods, so the numbers aren't directly comparable.")
                        .font(.system(size: 12)).foregroundStyle(Theme.orange)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ r: Report, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(r.title).font(.system(size: 15, weight: .heavy)).foregroundStyle(c)
            Text("\(Fmt.date(r.start)) –\n\(Fmt.date(r.end))").font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func table(_ rows: [(String, String, String, Bool?)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.1).frame(maxWidth: .infinity)
                        .foregroundStyle(row.3 == true ? Theme.green : Theme.text)
                    Text(row.0).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim)
                        .frame(width: 100)
                    Text(row.2).frame(maxWidth: .infinity)
                        .foregroundStyle(row.3 == false ? Theme.green : Theme.text)
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .padding(.vertical, 11)
                Divider().overlay(Theme.line)
            }
        }
        .padding(.horizontal, 10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}
