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
                // La nota si chiude solo con il tasto indietro: niente pizzico o swipe per uscire.
                .interactiveDismissDisabled()
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
    @State private var expandedFolders: Set<UUID> = []
    @State private var dragModel = SidebarDragModel()

    private var rootFolders: [Folder] {
        Folder.manualOrder(folders.filter { $0.parent == nil && $0.deletedAt == nil })
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

            Section {
                if rootFolders.isEmpty {
                    Text("Nessuna cartella")
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
                SidebarFolderTree(folders: rootFolders, expanded: $expandedFolders)
            } header: {
                Text("Cartelle")
            } footer: {
                if rootFolders.count > 1 {
                    Text("Tieni premuta una cartella e trascinala sopra o sotto un'altra per riordinarla, oppure al centro di una cartella per spostarla dentro.")
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { dragModel.containerFrame = $0 }
        .overlay { SidebarDragGhost(folders: folders) }
        .scrollDisabled(dragModel.draggingID != nil)
        .environment(dragModel)
        .sensoryFeedback(.selection, trigger: dragModel.target?.id)
        .sensoryFeedback(.impact(weight: .medium), trigger: dragModel.draggingID) { _, new in new != nil }
        .navigationTitle("BetterNotes")
    }
}
