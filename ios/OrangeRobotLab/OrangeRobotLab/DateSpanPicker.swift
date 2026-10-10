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
                DatePicker("", selection: $span.start, in: lab.dataStart...span.end, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                Text("To").foregroundStyle(Theme.dim)
                DatePicker("", selection: $span.end, in: span.start...lab.dataEnd, displayedComponents: .date)
                    .labelsHidden()
            }
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .font(.system(size: 13))
        }
    }
}
