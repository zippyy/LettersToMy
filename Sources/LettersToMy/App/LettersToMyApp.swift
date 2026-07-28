import SwiftUI

@main
struct LettersToMyApp: App {
    @StateObject private var persistence = PersistenceController.shared

    #if os(iOS)
    @UIApplicationDelegateAdaptor(LettersToMyApplicationDelegate.self)
    private var applicationDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(LettersToMyApplicationDelegate.self)
    private var applicationDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                if persistence.isLoaded {
                    RootView()
                        .environment(\.managedObjectContext, persistence.container.viewContext)
                } else {
                    SplashView()
                }
            }
            .task {
                await persistence.loadStores()
            }
        }


        #if os(macOS)
        Settings {
            SettingsView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
        #endif
    }
}
