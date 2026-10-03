import SwiftUI
import SwiftData

@main
struct BetterNotesApp: App {
    @State private var persistence: Persistence

    init() {
        AppSettings.registerDefaults()
        AppearanceConfigurator.configure()
        _persistence = State(initialValue: Persistence())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(persistence)
        }
        .modelContainer(persistence.container)
    }
}
