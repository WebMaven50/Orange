import SwiftUI

/// A metal plate with rivets. Polished orange when on; dull, scratched and rusty when off.
struct RivetPlate: View {
    let title: String
    let isOn: Bool
    let action: () -> Void


    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? onGradient : offGradient)
                if !isOn { Scratches() }
                rivets
                Text(title)
                    .font(.system(size: 14, weight: .black)).tracking(1.4)
                    .foregroundStyle(isOn ? Color.black.opacity(0.85) : Color(red: 0.66, green: 0.58, blue: 0.50))
            }
            .frame(maxWidth: .infinity).frame(height: 60)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isOn ? Color(red: 1, green: 0.85, blue: 0.6).opacity(0.8) : Color.black.opacity(0.7), lineWidth: 1.5))
            .shadow(color: isOn ? Theme.orange.opacity(0.6) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var onGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0.38), Theme.orange, Color(red: 0.74, green: 0.36, blue: 0.08)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var offGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.42, green: 0.38, blue: 0.34), Color(red: 0.26, green: 0.22, blue: 0.19), Color(red: 0.34, green: 0.25, blue: 0.17)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Four rivets, one in each corner.
    private var rivets: some View {
        GeometryReader { g in
            let spots = [CGPoint(x: 11, y: 11), CGPoint(x: g.size.width - 11, y: 11),
                         CGPoint(x: 11, y: g.size.height - 11), CGPoint(x: g.size.width - 11, y: g.size.height - 11)]
            ForEach(spots.indices, id: \.self) { i in
                Circle()
                    .fill(RadialGradient(
                        colors: isOn
                            ? [.white, Color(red: 0.96, green: 0.62, blue: 0.22), Color(red: 0.48, green: 0.24, blue: 0.05)]
                            : [Color(red: 0.36, green: 0.33, blue: 0.31), Color(red: 0.18, green: 0.16, blue: 0.14)],
                        center: .topLeading, startRadius: 0, endRadius: 7))
                    .frame(width: 8, height: 8)
                    .position(spots[i])
            }
        }
    }
}

/// Worn scratches across a switched-off plate.
private struct Scratches: View {
    var body: some View {
        Canvas { ctx, size in
            let marks: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.08, 0.22, 0.42, 0.36), (0.30, 0.80, 0.72, 0.62), (0.55, 0.12, 0.92, 0.50),
                (0.12, 0.62, 0.28, 0.94), (0.62, 0.86, 0.96, 0.70), (0.40, 0.30, 0.50, 0.72),
            ]
            for m in marks {
                var p = Path()
                p.move(to: CGPoint(x: m.0 * size.width, y: m.1 * size.height))
                p.addLine(to: CGPoint(x: m.2 * size.width, y: m.3 * size.height))
                ctx.stroke(p, with: .color(.white.opacity(0.24)), lineWidth: 1)
            }
            let dents: [(CGFloat, CGFloat)] = [(0.25, 0.45), (0.70, 0.30), (0.82, 0.78)]
            for d in dents {
                ctx.fill(Path(ellipseIn: CGRect(x: d.0 * size.width, y: d.1 * size.height, width: 5, height: 3)),
                         with: .color(.black.opacity(0.35)))
            }
        }
    }
}

/// The one-time question, shown after the first finished game. Replaces the old alert.
struct NotifyPromptView: View {
    let answer: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 18) {
                Image("RobotEmojiOrange").resizable().scaledToFit().frame(width: 46, height: 46)
                Text("Keep in touch with the robot?")
                    .font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text("The robot wants to keep you updated on new releases, game news, and interesting articles and interviews. You can change it anytime in Info.")
                    .font(.system(size: 14)).foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    RivetPlate(title: "ROBOT ALERTS ON", isOn: true) { answer(true) }
                    RivetPlate(title: "ROBOT ALERTS OFF", isOn: false) { answer(false) }
                }
                .padding(.top, 6)
            }
            .padding(24)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
            .padding(.horizontal, 28)
        }
    }
}
