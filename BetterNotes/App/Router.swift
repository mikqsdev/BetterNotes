import SwiftUI
import Observation

enum SidebarItem: Hashable {
    case library, recents, favorites, trash, settings
    case folder(UUID)
}

@MainActor
@Observable
final class AppRouter {
    var selection: SidebarItem? = .library
    /// Editor attualmente aperto (presentato a schermo intero con transizione zoom).
    var editor: EditorController?

    func open(_ note: Note) {
        guard editor == nil else { return }
        note.lastOpenedAt = Date()
        editor = EditorController(note: note)
    }
}

extension EnvironmentValues {
    @Entry var noteTransitionNamespace: Namespace.ID? = nil
}
