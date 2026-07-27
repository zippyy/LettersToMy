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
        TabView {
            LibraryView()
                .tabItem { Label("Letters", systemImage: "envelope.fill") }

            TimelineView()
                .tabItem { Label("Timeline", systemImage: "calendar") }

            FamilyView()
                .tabItem { Label("Family", systemImage: "person.2.fill") }

            CollaboratorsView()
                .tabItem { Label("People", systemImage: "person.3.fill") }

            #if os(iOS)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            #endif
        }
    }
}

private struct WelcomeView: View {
    let continueAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.open.heart.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("Letters to My")
                    .font(.largeTitle.bold())
                Text("A private place for the words, memories, photos, and moments you want your child to receive someday.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("Write now and unlock on a future birthday", systemImage: "birthday.cake")
                Label("Invite spouses and family into carefully scoped spaces", systemImage: "person.3.fill")
                Label("Use the same archive on iPhone, iPad, Mac, and later the web", systemImage: "rectangle.3.group")
            }
            .font(.headline)

            Spacer()

            Button("Create Our Family Archive", action: continueAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}
