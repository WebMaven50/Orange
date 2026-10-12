import SwiftUI
import OrangeRobotKit

/// One line, shown before each run. Tap anywhere to begin.
struct QuoteCardView: View {
    let quote: Quote
    let dismiss: () -> Void
    @State private var shown = false

    private var caption: String {
        switch quote.kind {
        case .book: return "FROM THE BOOK"
        case .site: return "FROM THE ORANGE ROBOT"
        case .scripture: return "SCRIPTURE"
        case .original: return "FROM THE WORLD OF THE ORANGE ROBOT"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 22) {
                Image("RobotEmojiOrange").resizable().scaledToFit().frame(width: 54, height: 54)
                    .opacity(0.95)
                Text(caption)
                    .font(.system(size: 10, weight: .heavy)).tracking(2.4)
                    .foregroundStyle(Theme.orange)
                Text("“\(quote.text)”")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 30)
                    .fixedSize(horizontal: false, vertical: true)
                Text("— " + quote.source)
                    .font(.system(size: 13, weight: .regular, design: .serif)).italic()
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Text("tap to begin")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(Theme.dim.opacity(0.8))
                    .padding(.top, 14)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { shown = true } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
