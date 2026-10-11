import SwiftUI
import OrangeRobotKit

/// The calm first screen. Everything else lives one tap away.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("RobotHead")
                .resizable().scaledToFit()
                .frame(width: 170, height: 170)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("ORANGE ROBOT LAB")
                    .font(.system(size: 30, weight: .black)).tracking(1.5)
                    .foregroundStyle(Theme.orange)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text("Robotic Trading Simulator Game")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text("Robot trading agents")
                    .font(.system(size: 14, weight: .bold)).tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.dim)
            }
            .padding(.top, 22)
            .padding(.horizontal, 24)

            Spacer()

            NavigationLink {
                HomeView()
            } label: {
                Text("START")
                    .font(.system(size: 18, weight: .black)).tracking(2)
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(Theme.orange, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
            }
            .simultaneousGesture(TapGesture().onEnded { Feedback.play(.tap) })
            .padding(.horizontal, 36)

            Text("A simulation using past prices. Not financial advice.")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)
                .padding(.top, 14).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .navigationBarHidden(true)
    }
}
