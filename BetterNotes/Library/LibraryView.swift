import PencilKit
import SwiftData
import SwiftUI

/// Contenuto di una cartella (o della Libreria principale se `folder` è nil).
struct LibraryView: View {
    let folder: Folder?

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var allFolders: [Folder]
    @Query private var allNotes: [Note]
    @AppStorage(SettingsKey.sortOrder) private var sortRaw = LibrarySort.modified.rawValue
    @AppStorage(SettingsKey.showRecents) private var showRecents = true

    @State private var searchText = ""
    @State private var showNewNote = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showRename = false
    @State private var showCustomize = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 28, alignment: .top)]

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .modified }

    private var subfolders: [Folder] {
        let list = folder?.activeSubfolders ?? allFolders.filter { $0.parent == nil && $0.deletedAt == nil }
        return sorted(list, name: \.name, created: \.createdAt, modified: \.updatedAt)
    }

    private var notes: [Note] {
        let list = folder?.activeNotes ?? allNotes.filter { $0.folder == nil && $0.deletedAt == nil }
        return sorted(list, name: \.title, created: \.createdAt, modified: \.updatedAt)
    }

    private var recents: [Note] {
        allNotes
            .filter { !$0.isEffectivelyTrashed }
            .sorted { ($0.lastOpenedAt ?? $0.updatedAt) > ($1.lastOpenedAt ?? $1.updatedAt) }
            .prefix(10)
            .map { $0 }
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var searchFolders: [Folder] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return allFolders.filter { !$0.isEffectivelyTrashed && $0.name.localizedStandardContains(q) }
    }

    private var searchNotes: [Note] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return allNotes.filter {
            !$0.isEffectivelyTrashed && ($0.title.localizedStandardContains(q) || ($0.folder?.name.localizedStandardContains(q) ?? false))
        }
    }

    private func sorted<T>(_ items: [T], name: KeyPath<T, String>, created: KeyPath<T, Date>, modified: KeyPath<T, Date>) -> [T] {
        switch sort {
        case .name: items.sorted { $0[keyPath: name].localizedStandardCompare($1[keyPath: name]) == .orderedAscending }
        case .created: items.sorted { $0[keyPath: created] > $1[keyPath: created] }
        case .modified: items.sorted { $0[keyPath: modified] > $1[keyPath: modified] }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if isSearching {
                    searchResults
                } else {
                    if folder == nil, showRecents, recents.count >= 4 {
                        recentsSection
                    }
                    if !subfolders.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionHeader(title: "Cartelle", count: subfolders.count)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                                ForEach(subfolders) { FolderTile(folder: $0) }
                            }
                        }
                    }
                    if !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionHeader(title: "Note", count: notes.count)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                                ForEach(notes) { NoteTile(note: $0) }
                            }
                        }
                    }
                    if subfolders.isEmpty && notes.isEmpty {
                        emptyState
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 60)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: subfolders.map(\.id))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: notes.map(\.id))
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(folder?.name ?? "Libreria")
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Cerca note e cartelle")
        .toolbar { toolbarContent }
        .dropDestination(for: String.self) { items, _ in
            _ = LibraryActions.handleDrop(items, into: folder, context: context)
        }
        .sheet(isPresented: $showNewNote) {
            NewNoteSheet { title, style in
                let note = LibraryActions.createNote(title: title, style: style, in: folder, context: context)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.open(note) }
            }
            .presentationSizing(.page)
        }
        .alert("Nuova cartella", isPresented: $showNewFolder) {
            TextField("Nome della cartella", text: $newFolderName)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
            Button("Annulla", role: .cancel) {}
            Button("Crea") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                withAnimation {
                    _ = LibraryActions.createFolder(named: name.isEmpty ? "Nuova cartella" : name, in: folder, context: context)
                }
            }
        } message: {
            Text(folder == nil ? "Crea una cartella nella Libreria." : "Crea una sottocartella in “\(folder?.name ?? "")”.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: DocumentImporter.supportedTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await importFiles(urls) }
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .alert("Importazione non riuscita", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .overlay {
            if isImporting {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Importazione in corso…").font(.serif(.headline, weight: .semibold))
                }
                .padding(32)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring, value: isImporting)
        .modifier(FolderHeaderActions(folder: folder, showRename: $showRename, showCustomize: $showCustomize))
    }

    private var subtitle: String {
        if isSearching { return "" }
        let f = subfolders.count, n = notes.count
        let folders = f == 1 ? "1 cartella" : "\(f) cartelle"
        let noteText = n == 1 ? "1 nota" : "\(n) note"
        return "\(folders) · \(noteText)"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Ordina per", selection: $sortRaw) {
                    ForEach(LibrarySort.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option.rawValue)
                    }
                }
                if let folder {
                    Divider()
                    Button { showCustomize = true } label: { Label("Colore e icona", systemImage: "paintpalette") }
                    Button { showRename = true } label: { Label("Rinomina cartella", systemImage: "pencil") }
                    Button {
                        folder.isFavorite.toggle()
                        try? context.save()
                    } label: {
                        Label(folder.isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti", systemImage: folder.isFavorite ? "star.slash" : "star")
                    }
                }
            } label: {
                Label("Opzioni", systemImage: "ellipsis")
            }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showImporter = true } label: {
                Label("Importa", systemImage: "square.and.arrow.down")
            }
            .help("Importa PDF o Word")
            Button {
                newFolderName = ""
                showNewFolder = true
            } label: {
                Label("Nuova cartella", systemImage: "folder.badge.plus")
            }
            .help("Nuova cartella")
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button { showNewNote = true } label: {
                Label("Nuova nota", systemImage: "square.and.pencil")
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut("n", modifiers: .command)
            .help("Nuova nota")
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Recenti")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(recents) { note in
                        NoteTile(note: note)
                            .frame(width: 150)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 32)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -32)
            .padding(.vertical, -14)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if searchFolders.isEmpty && searchNotes.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .padding(.top, 80)
        } else {
            if !searchFolders.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(title: "Cartelle", count: searchFolders.count)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                        ForEach(searchFolders) { FolderTile(folder: $0) }
                    }
                }
            }
            if !searchNotes.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(title: "Note", count: searchNotes.count)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                        ForEach(searchNotes) { NoteTile(note: $0) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            ZStack {
                FolderArtwork(color: folder?.color ?? .terracotta, iconName: folder?.iconName ?? "pencil.and.scribble")
                    .frame(width: 170)
                    .opacity(0.9)
            }
            VStack(spacing: 8) {
                Text(folder == nil ? "Benvenuto in BetterNotes" : "Questa cartella è vuota")
                    .font(.serif(.title, weight: .bold))
                Text("Crea una nota da scrivere con Apple Pencil, organizza tutto in cartelle oppure importa un PDF o un documento Word da annotare.")
                    .font(.serif(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    Button { showNewNote = true } label: {
                        Label("Nuova nota", systemImage: "square.and.pencil").padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        newFolderName = ""
                        showNewFolder = true
                    } label: {
                        Label("Nuova cartella", systemImage: "folder.badge.plus").padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    Button { showImporter = true } label: {
                        Label("Importa", systemImage: "square.and.arrow.down").padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        var lastNote: Note?
        var errors: [String] = []
        for url in urls {
            do {
                let imported = try await DocumentImporter.importFile(at: url)
                let note = LibraryActions.createNote(title: imported.title, style: .pdf, in: folder, context: context)
                note.pdfData = imported.pdfData
                note.pageCount = imported.pageCount
                note.sourceFileName = imported.fileName
                let pdf = PDFSource(data: imported.pdfData)
                let layout = PageLayout.make(style: .pdf, pageCount: imported.pageCount, pdfPageSizes: pdf?.pageSizes, infiniteSize: .zero)
                note.thumbnailData = NoteRenderer.thumbnail(for: .init(layout: layout, pdf: pdf, drawing: PKDrawing(), images: []))
                try? context.save()
                lastNote = note
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if !errors.isEmpty { importError = errors.joined(separator: "\n") }
        if urls.count == 1, let lastNote {
            try? await Task.sleep(for: .milliseconds(300))
            router.open(lastNote)
        }
    }
}

/// Rinomina e personalizzazione della cartella corrente dal menu della barra.
private struct FolderHeaderActions: ViewModifier {
    let folder: Folder?
    @Binding var showRename: Bool
    @Binding var showCustomize: Bool
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        if let folder {
            content
                .modifier(RenameAlert(isPresented: $showRename, title: "Rinomina cartella", current: folder.name) { name in
                    folder.name = name
                    try? context.save()
                })
                .sheet(isPresented: $showCustomize, onDismiss: { try? context.save() }) {
                    CustomizeSheet(
                        title: "Personalizza cartella",
                        iconName: Binding(get: { folder.iconName }, set: { folder.iconName = $0 }),
                        colorName: Binding(get: { folder.colorName }, set: { folder.colorName = $0 }),
                        previewName: folder.name
                    )
                }
        } else {
            content
        }
    }
}
