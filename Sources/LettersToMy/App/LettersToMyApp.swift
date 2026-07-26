import SwiftData
import SwiftUI

@main
struct LettersToMyApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            ChildProfile.self,
            Letter.self,
            LetterAttachment.self
        ])
        let configuration = ModelConfiguration(
            "LettersToMy",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create LettersToMy model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
        #endif
    }
}
