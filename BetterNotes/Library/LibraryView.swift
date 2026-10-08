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
    @State private var busyMessage: String?
    @State private var importError: String?
    @State private var exportError: String?
    @State private var showRename = false
    @State private var showCustomize = false
    @State private var selection = LibrarySelection()
    @State private var shareFiles: ShareFiles?
    @State private var showMoveSelection = false
    @State private var confirmDeleteSelection = false
    @State private var confirmDeleteSelectionAgain = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 28, alignment: .top)]

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .modified }

    private var subfolders: [Folder] {
        let list = folder?.activeSubfolders ?? allFolders.filter { $0.parent == nil && $0.deletedAt == nil }
        if sort == .manual { return Folder.manualOrder(list) }
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

    /// Note visibili ora (risultati di ricerca o contenuto della cartella), usate da "Seleziona tutte".
    private var visibleNotes: [Note] { isSearching ? searchNotes : notes }

    private var selectedNotes: [Note] {
        visibleNotes.filter { selection.noteIDs.contains($0.id) }
            + allNotes.filter { selection.noteIDs.contains($0.id) && !visibleNotes.contains($0) && !$0.isEffectivelyTrashed }
    }

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
        case .modified, .manual: items.sorted { $0[keyPath: modified] > $1[keyPath: modified] }
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
            .padding(.bottom, selection.isActive ? 120 : 60)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: subfolders.map(\.id))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: notes.map(\.id))
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(folder?.name ?? String(localized: "Libreria"))
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
        .environment(\.librarySelection, selection)
        .overlay(alignment: .bottom) {
            if selection.isActive {
                selectionBar
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selection.isActive)
        .sheet(item: $shareFiles) { files in
            ShareSheet(items: files.urls)
        }
        .sheet(isPresented: $showMoveSelection) {
            MoveSheet(title: selection.noteIDs.count == 1 ? "Sposta nota" : "Sposta note", movingFolder: nil, currentParentID: folder?.id) { target in
                withAnimation {
                    for note in selectedNotes { LibraryActions.move(note, to: target) }
                    selection.end()
                }
            }
        }
        .confirmationDialog(deleteSelectionTitle, isPresented: $confirmDeleteSelection, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirmDeleteSelectionAgain = true }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Le note selezionate verranno spostate nel Cestino.")
        }
        .alert("Sei sicuro?", isPresented: $confirmDeleteSelectionAgain) {
            Button("Annulla", role: .cancel) {}
            Button("Sì, elimina", role: .destructive) {
                withAnimation {
                    for note in selectedNotes { LibraryActions.trash(note) }
                    selection.end()
                }
            }
        } message: {
            Text("Conferma ancora una volta. Potrai recuperarle dal Cestino entro \(LibraryActions.trashRetentionDays) giorni, poi verranno eliminate per sempre.")
        }
        .alert("Esportazione non riuscita", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
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
                    _ = LibraryActions.createFolder(named: name.isEmpty ? String(localized: "Nuova cartella") : name, in: folder, context: context)
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
            if let busyMessage {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(busyMessage).font(.serif(.headline, weight: .semibold))
                }
                .padding(32)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring, value: busyMessage)
        .modifier(FolderHeaderActions(folder: folder, showRename: $showRename, showCustomize: $showCustomize))
    }

    private var deleteSelectionTitle: String {
        let count = selection.noteIDs.count
        return count == 1 ? String(localized: "Eliminare 1 nota?") : String(localized: "Eliminare \(count) note?")
    }

    private var subtitle: String {
        if selection.isActive {
            let count = selection.noteIDs.count
            return count == 0 ? String(localized: "Seleziona le note") : (count == 1 ? String(localized: "1 nota selezionata") : String(localized: "\(count) note selezionate"))
        }
        if isSearching { return "" }
        let f = subfolders.count, n = notes.count
        return "\(Counts.folders(f)) · \(Counts.notes(n))"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selection.isActive {
            ToolbarItem(placement: .topBarTrailing) {
                let allSelected = !visibleNotes.isEmpty && visibleNotes.allSatisfy { selection.contains($0) }
                Button(allSelected ? "Deseleziona tutte" : "Seleziona tutte") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if allSelected {
                            selection.noteIDs.subtract(visibleNotes.map(\.id))
                        } else {
                            selection.noteIDs.formUnion(visibleNotes.map(\.id))
                        }
                    }
                }
                .disabled(visibleNotes.isEmpty)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fine") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection.end() }
                }
                .buttonStyle(.glassProminent)
            }
        } else {
            regularToolbar
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            InlineSearchField(text: $searchText, prompt: "Cerca note e cartelle", width: 240)
        }
    }

    @ToolbarContentBuilder
    private var regularToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection.begin() }
                } label: {
                    Label("Seleziona note", systemImage: "checkmark.circle")
                }
                .disabled(visibleNotes.isEmpty)
                Menu {
                    Button { export(visibleNotes, combined: false) } label: {
                        Label("Un PDF per ogni nota", systemImage: "doc.on.doc")
                    }
                    Button { export(visibleNotes, combined: true) } label: {
                        Label("Tutte in un unico PDF", systemImage: "doc.richtext")
                    }
                } label: {
                    Label(folder == nil ? "Esporta tutte le note" : "Esporta le note della cartella", systemImage: "square.and.arrow.up")
                }
                .disabled(visibleNotes.isEmpty)
                Divider()
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

    private var selectionBar: some View {
        let count = selection.noteIDs.count
        let notes = selectedNotes
        return GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Text(count == 0 ? "Nessuna nota selezionata" : (count == 1 ? "1 nota" : "\(count) note"))
                    .font(.serif(.headline, weight: .semibold))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .capsule)

                HStack(spacing: 4) {
                    Menu {
                        Button { export(notes, combined: false) } label: {
                            Label(count == 1 ? "Esporta PDF" : "Un PDF per ogni nota", systemImage: "doc.on.doc")
                        }
                        if count > 1 {
                            Button { export(notes, combined: true) } label: {
                                Label("Tutte in un unico PDF", systemImage: "doc.richtext")
                            }
                        }
                    } label: {
                        Label("Esporta", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                    }

                    Button { showMoveSelection = true } label: {
                        Label("Sposta", systemImage: "folder")
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                    }

                    Button {
                        let makeFavorite = !notes.allSatisfy(\.isFavorite)
                        withAnimation { for note in notes { note.isFavorite = makeFavorite } }
                        try? context.save()
                    } label: {
                        Label(notes.allSatisfy(\.isFavorite) && !notes.isEmpty ? "Rimuovi preferiti" : "Preferiti", systemImage: "star")
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                    }

                    Button(role: .destructive) { confirmDeleteSelection = true } label: {
                        Label("Elimina", systemImage: "trash")
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                    }
                    .tint(.red)
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6)
                .glassEffect(.regular, in: .capsule)
                .disabled(count == 0)
                .opacity(count == 0 ? 0.5 : 1)
            }
        }
    }

    /// Esporta le note in PDF (separati o in un unico file) e apre il foglio di condivisione.
    private func export(_ notes: [Note], combined: Bool) {
        guard !notes.isEmpty else { return }
        busyMessage = notes.count == 1 ? String(localized: "Esportazione in corso…") : String(localized: "Esportazione di \(notes.count) note…")
        Task { @MainActor in
            // Lascia apparire l'indicatore prima del rendering.
            try? await Task.sleep(for: .milliseconds(120))
            do {
                let title = combined ? "\(folder?.name ?? String(localized: "Libreria")) - \(Counts.notes(notes.count))" : nil
                let urls = try NoteRenderer.exportPDFs(notes, combinedTitle: title)
                busyMessage = nil
                shareFiles = ShareFiles(urls: urls)
            } catch {
                busyMessage = nil
                exportError = error.localizedDescription
            }
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
                FolderArtwork(color: folder?.color ?? .terracotta, iconName: folder?.iconName ?? "pencil.and.scribble", documentCount: folder == nil ? 2 : 0)
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
        busyMessage = String(localized: "Importazione in corso…")
        defer { busyMessage = nil }
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
                        previewName: folder.name,
                        previewDocumentCount: folder.contentCount
                    )
                }
        } else {
            content
        }
    }
}
