import SwiftUI

@main
struct LettersToMyApp: App {
    private let persistence = PersistenceController.shared

    #if os(iOS)
    @UIApplicationDelegateAdaptor(LettersToMyApplicationDelegate.self)
    private var applicationDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(LettersToMyApplicationDelegate.self)
    private var applicationDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
        #endif
    }
}
