import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
    @State private var router = AppRouter()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Namespace private var noteNamespace

    private var colorScheme: ColorScheme? { (AppearanceMode(rawValue: appearanceRaw) ?? .system).colorScheme }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $router.selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            DetailRoot(selection: router.selection ?? .library)
                .id(router.selection ?? .library)
        }
        .fullScreenCover(item: $router.editor) { editor in
            NoteEditorView(controller: editor)
                .navigationTransition(.zoom(sourceID: editor.note.id, in: noteNamespace))
                .preferredColorScheme(colorScheme)
                .fontDesign(.serif)
                .tint(Theme.accent)
        }
        .environment(router)
        .environment(\.noteTransitionNamespace, noteNamespace)
        .fontDesign(.serif)
        .tint(Theme.accent)
        .preferredColorScheme(colorScheme)
        .onAppear { LibraryActions.purgeExpiredTrash(context: context) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { LibraryActions.purgeExpiredTrash(context: context) }
        }
    }
}

private struct DetailRoot: View {
    let selection: SidebarItem
    @Query private var folders: [Folder]

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: Folder.self) { folder in
                    LibraryView(folder: folder)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .library:
            LibraryView(folder: nil)
        case .recents:
            RecentsView()
        case .favorites:
            FavoritesView()
        case .trash:
            TrashView()
        case .settings:
            SettingsView()
        case .folder(let id):
            if let folder = folders.first(where: { $0.id == id }), !folder.isEffectivelyTrashed {
                LibraryView(folder: folder)
            } else {
                ContentUnavailableView("Cartella non trovata", systemImage: "folder.badge.questionmark")
                    .background(Theme.background.ignoresSafeArea())
            }
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query private var notes: [Note]

    private var rootFolders: [Folder] {
        folders.filter { $0.parent == nil && $0.deletedAt == nil }
    }
    private var trashCount: Int {
        folders.filter { $0.deletedAt != nil }.count + notes.filter { $0.deletedAt != nil }.count
    }
    private var favoritesCount: Int {
        folders.filter { $0.isFavorite && !$0.isEffectivelyTrashed }.count + notes.filter { $0.isFavorite && !$0.isEffectivelyTrashed }.count
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Libreria", systemImage: "books.vertical")
                    .tag(SidebarItem.library)
                    .dropDestination(for: String.self) { items, _ in
                        _ = LibraryActions.handleDrop(items, into: nil, context: context)
                    }
                Label("Recenti", systemImage: "clock")
                    .tag(SidebarItem.recents)
                Label("Preferiti", systemImage: "star")
                    .badge(favoritesCount)
                    .tag(SidebarItem.favorites)
            }

            Section("Cartelle") {
                if rootFolders.isEmpty {
                    Text("Nessuna cartella")
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
                OutlineGroup(rootFolders, children: \.outlineChildren) { folder in
                    Label {
                        Text(folder.name).lineLimit(1)
                    } icon: {
                        Image(systemName: folder.iconName ?? "folder.fill")
                            .foregroundStyle(folder.color.color)
                    }
                    .tag(SidebarItem.folder(folder.id))
                    .dropDestination(for: String.self) { items, _ in
                        _ = LibraryActions.handleDrop(items.filter { !$0.hasSuffix(folder.id.uuidString) }, into: folder, context: context)
                    }
                }
            }

            Section {
                Label("Cestino", systemImage: "trash")
                    .badge(trashCount)
                    .tag(SidebarItem.trash)
                Label("Impostazioni", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
        }
        .navigationTitle("BetterNotes")
    }
}
