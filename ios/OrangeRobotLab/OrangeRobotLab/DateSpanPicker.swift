import SwiftUI

/// Start and end date pickers plus one-tap historical periods.
struct DateSpanPicker: View {
    @Environment(LabModel.self) private var lab
    @Binding var span: DateSpan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DateSpan.presets, id: \.0) { name, s in
                        Button { span = s } label: {
                            Text(name).font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(span == s ? Theme.orange : Theme.panel2, in: Capsule())
                                .foregroundStyle(span == s ? Color.black : Theme.text)
                        }
                    }
                }
            }
            HStack {
                Text("From").foregroundStyle(Theme.dim)
                // Any date in the data is allowed; if it lands after "To", "To" moves with it.
                DatePicker("", selection: Binding(
                    get: { span.start },
                    set: { new in
                        span.start = new
                        if span.end <= new {
                            span.end = min(lab.dataEnd, new.addingTimeInterval(365 * 86_400))
                            if span.end <= new { span.start = lab.dataEnd.addingTimeInterval(-86_400 * 90) }
                        }
                    }), in: lab.dataStart...lab.dataEnd, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                Text("To").foregroundStyle(Theme.dim)
                // Likewise, an earlier "To" pulls "From" back with it.
                DatePicker("", selection: Binding(
                    get: { span.end },
                    set: { new in
                        span.end = new
                        if span.start >= new {
                            span.start = max(lab.dataStart, new.addingTimeInterval(-365 * 86_400))
                        }
                    }), in: lab.dataStart...lab.dataEnd, displayedComponents: .date)
                    .labelsHidden()
            }
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .font(.system(size: 13))
        }
    }
}
