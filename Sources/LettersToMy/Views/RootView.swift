import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                WelcomeView {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}

private struct MainTabView: View {
    var body: some View {
        Text("HELLO WORLD")
            .font(.largeTitle)
            .foregroundStyle(.red)
            .padding()
            .background(Color.yellow)
    }
}

private struct WelcomeView: View {
    let continueAction: () -> Void

    var body: some View {
        Button("Continue", action: continueAction)
            .buttonStyle(.borderedProminent)
    }
}