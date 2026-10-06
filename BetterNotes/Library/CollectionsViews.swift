import SwiftData
import SwiftUI

private let gridColumns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 28, alignment: .top)]

struct FavoritesView: View {
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    private var favoriteFolders: [Folder] { folders.filter { $0.isFavorite && !$0.isEffectivelyTrashed } }
    private var favoriteNotes: [Note] { notes.filter { $0.isFavorite && !$0.isEffectivelyTrashed } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if favoriteFolders.isEmpty && favoriteNotes.isEmpty {
                    ContentUnavailableView {
                        Label("Nessun preferito", systemImage: "star")
                    } description: {
                        Text("Tieni premuto su una nota o una cartella e scegli “Aggiungi ai preferiti” per trovarla qui.")
                    }
                    .padding(.top, 100)
                }
                if !favoriteFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeader(title: "Cartelle", count: favoriteFolders.count)
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 30) {
                            ForEach(favoriteFolders) { FolderTile(folder: $0) }
                        }
                    }
                }
                if !favoriteNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeader(title: "Note", count: favoriteNotes.count)
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 30) {
                            ForEach(favoriteNotes) { NoteTile(note: $0) }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .animation(.spring, value: favoriteNotes.map(\.id))
            .animation(.spring, value: favoriteFolders.map(\.id))
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Preferiti")
    }
}

struct RecentsView: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    private var groups: [(String, [Note])] {
        let calendar = Calendar.current
        let active = notes.filter { !$0.isEffectivelyTrashed }.prefix(80)
        var today: [Note] = [], week: [Note] = [], month: [Note] = [], older: [Note] = []
        for note in active {
            let date = note.updatedAt
            if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
                today.append(note)
            } else if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
                week.append(note)
            } else if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 31 {
                month.append(note)
            } else {
                older.append(note)
            }
        }
        return [("Oggi e ieri", today), ("Questa settimana", week), ("Questo mese", month), ("Meno recenti", older)]
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if groups.isEmpty {
                    ContentUnavailableView("Nessuna nota recente", systemImage: "clock", description: Text("Le note che modifichi compariranno qui."))
                        .padding(.top, 100)
                }
                ForEach(groups, id: \.0) { title, items in
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeader(title: title, count: items.count)
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 30) {
                            ForEach(items) { NoteTile(note: $0) }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Recenti")
    }
}

struct TrashView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var confirmEmpty = false
    @State private var pendingFolderDeletion: Folder?
    @State private var pendingNoteDeletion: Note?

    /// Solo gli elementi eliminati "in cima" (non quelli dentro una cartella già nel cestino).
    private var trashedFolders: [Folder] {
        folders.filter { $0.deletedAt != nil && !($0.parent?.isEffectivelyTrashed ?? false) }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }
    private var trashedNotes: [Note] {
        notes.filter { $0.deletedAt != nil && !($0.folder?.isEffectivelyTrashed ?? false) }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }
    private var isEmpty: Bool { trashedFolders.isEmpty && trashedNotes.isEmpty }

    var body: some View {
        List {
            if isEmpty {
                ContentUnavailableView {
                    Label("Il cestino è vuoto", systemImage: "trash")
                } description: {
                    Text("Le note e le cartelle eliminate restano qui per \(LibraryActions.trashRetentionDays) giorni prima di essere cancellate per sempre.")
                }
                .listRowBackground(Color.clear)
                .padding(.top, 80)
            } else {
                Section {
                    ForEach(trashedFolders) { folder in
                        TrashRow(
                            title: folder.name,
                            subtitle: folder.itemSummary,
                            deletedAt: folder.deletedAt
                        ) {
                            FolderArtwork(color: folder.color, iconName: folder.iconName, documentCount: folder.contentCount).frame(width: 56)
                        }
                        .swipeActions(edge: .leading) {
                            Button { withAnimation { LibraryActions.restore(folder) } } label: {
                                Label("Ripristina", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingFolderDeletion = folder } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button { withAnimation { LibraryActions.restore(folder) } } label: {
                                Label("Ripristina", systemImage: "arrow.uturn.backward")
                            }
                            Button(role: .destructive) { pendingFolderDeletion = folder } label: {
                                Label("Elimina definitivamente", systemImage: "trash")
                            }
                        }
                    }
                    ForEach(trashedNotes) { note in
                        TrashRow(
                            title: note.displayTitle,
                            subtitle: note.folder.map { "Da “\($0.name)”" } ?? "Dalla Libreria",
                            deletedAt: note.deletedAt
                        ) {
                            NoteThumbnail(note: note).frame(width: 44)
                        }
                        .swipeActions(edge: .leading) {
                            Button { withAnimation { LibraryActions.restore(note) } } label: {
                                Label("Ripristina", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingNoteDeletion = note } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button { withAnimation { LibraryActions.restore(note) } } label: {
                                Label("Ripristina", systemImage: "arrow.uturn.backward")
                            }
                            Button(role: .destructive) { pendingNoteDeletion = note } label: {
                                Label("Elimina definitivamente", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("Scorri verso destra per ripristinare, verso sinistra per eliminare definitivamente. Gli elementi vengono cancellati automaticamente dopo \(LibraryActions.trashRetentionDays) giorni.")
                }
                .listRowBackground(Theme.elevated)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Cestino")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmEmpty = true } label: {
                    Label("Svuota cestino", systemImage: "trash.slash")
                }
                .disabled(isEmpty)
            }
        }
        .confirmationDialog("Svuotare il cestino?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Svuota cestino", role: .destructive) {
                withAnimation { LibraryActions.emptyTrash(context: context) }
            }
        } message: {
            Text("Tutti gli elementi nel cestino verranno eliminati per sempre. L'operazione non può essere annullata.")
        }
        .alert("Eliminare definitivamente?", isPresented: Binding(
            get: { pendingFolderDeletion != nil || pendingNoteDeletion != nil },
            set: { if !$0 { pendingFolderDeletion = nil; pendingNoteDeletion = nil } }
        )) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) {
                withAnimation {
                    if let folder = pendingFolderDeletion { LibraryActions.deletePermanently(folder) }
                    if let note = pendingNoteDeletion { LibraryActions.deletePermanently(note) }
                }
            }
        } message: {
            Text("L'elemento verrà cancellato per sempre e non potrà essere recuperato.")
        }
    }
}

private struct TrashRow<Artwork: View>: View {
    let title: String
    let subtitle: String
    let deletedAt: Date?
    @ViewBuilder var artwork: Artwork

    var body: some View {
        let days = LibraryActions.daysRemaining(deletedAt: deletedAt)
        HStack(spacing: 16) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.serif(.headline, weight: .semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(days == 1 ? "1 giorno" : "\(days) giorni")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(days <= 3 ? Color.red : Color.secondary)
                Text("rimanenti").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}
