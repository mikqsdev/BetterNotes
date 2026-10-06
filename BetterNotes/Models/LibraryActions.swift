import Foundation
import SwiftData

/// Operazioni sulla libreria (creazione, cestino, spostamenti).
@MainActor
enum LibraryActions {
    static let trashRetentionDays = 30

    @discardableResult
    static func createFolder(named name: String, in parent: Folder?, context: ModelContext) -> Folder {
        let siblings = parent?.activeSubfolders.count ?? 0
        let palette = FolderColor.allCases
        let folder = Folder(name: name, colorName: palette[siblings % palette.count].rawValue)
        context.insert(folder)
        folder.parent = parent
        folder.sortIndex = nextSortIndex(in: parent, context: context, excluding: folder)
        parent?.updatedAt = Date()
        try? context.save()
        return folder
    }

    @discardableResult
    static func createNote(title: String, style: PaperStyle, in folder: Folder?, context: ModelContext) -> Note {
        let note = Note(title: title, style: style)
        context.insert(note)
        note.folder = folder
        folder?.updatedAt = Date()
        try? context.save()
        return note
    }

    static func trash(_ folder: Folder) {
        folder.deletedAt = Date()
        folder.isFavorite = false
        try? folder.modelContext?.save()
    }

    static func trash(_ note: Note) {
        note.deletedAt = Date()
        try? note.modelContext?.save()
    }

    static func restore(_ folder: Folder) {
        folder.deletedAt = nil
        if folder.parent?.isEffectivelyTrashed == true { folder.parent = nil }
        try? folder.modelContext?.save()
    }

    static func restore(_ note: Note) {
        note.deletedAt = nil
        if note.folder?.isEffectivelyTrashed == true { note.folder = nil }
        try? note.modelContext?.save()
    }

    static func deletePermanently(_ folder: Folder) {
        let context = folder.modelContext
        context?.delete(folder)
        try? context?.save()
    }

    static func deletePermanently(_ note: Note) {
        let context = note.modelContext
        context?.delete(note)
        try? context?.save()
    }

    static func move(_ note: Note, to folder: Folder?) {
        note.folder = folder
        note.updatedAt = Date()
        try? note.modelContext?.save()
    }

    /// Sposta una cartella evitando cicli (una cartella non può finire dentro sé stessa).
    @discardableResult
    static func move(_ folder: Folder, to target: Folder?) -> Bool {
        if let target, target.id == folder.id || target.isDescendant(of: folder) { return false }
        folder.parent = target
        folder.sortIndex = nextSortIndex(in: target, context: folder.modelContext, excluding: folder)
        folder.updatedAt = Date()
        try? folder.modelContext?.save()
        return true
    }

    @discardableResult
    static func duplicate(_ note: Note) -> Note? {
        guard let context = note.modelContext else { return nil }
        let copy = Note(title: note.title + " (copia)", style: note.paperStyle)
        context.insert(copy)
        copy.folder = note.folder
        copy.iconName = note.iconName
        copy.pageCount = note.pageCount
        copy.canvasWidth = note.canvasWidth
        copy.canvasHeight = note.canvasHeight
        copy.drawingData = note.drawingData
        copy.attachmentsData = note.attachmentsData
        copy.pdfData = note.pdfData
        copy.thumbnailData = note.thumbnailData
        copy.sourceFileName = note.sourceFileName
        try? context.save()
        return copy
    }

    // MARK: - Ordine personalizzato

    /// Cartelle sorelle attive, nell'ordine personalizzato.
    static func siblings(in parent: Folder?, context: ModelContext?) -> [Folder] {
        let list: [Folder]
        if let parent {
            list = parent.activeSubfolders
        } else {
            let all = (try? context?.fetch(FetchDescriptor<Folder>())) ?? []
            list = all.filter { $0.parent == nil && $0.deletedAt == nil }
        }
        return Folder.manualOrder(list)
    }

    private static func nextSortIndex(in parent: Folder?, context: ModelContext?, excluding folder: Folder) -> Int {
        (siblings(in: parent, context: context).filter { $0.id != folder.id }.map(\.sortIndex).max() ?? -1) + 1
    }

    /// Posiziona `folder` subito prima o dopo `target` (anche spostandolo in un'altra cartella).
    @discardableResult
    static func place(_ folder: Folder, nextTo target: Folder, after: Bool) -> Bool {
        guard folder.id != target.id, !target.isDescendant(of: folder) else { return false }
        let context = folder.modelContext
        let newParent = target.parent
        if folder.parent?.id != newParent?.id {
            folder.parent = newParent
            folder.updatedAt = Date()
        }
        var ordered = siblings(in: newParent, context: context).filter { $0.id != folder.id }
        let targetIndex = ordered.firstIndex { $0.id == target.id } ?? ordered.count
        ordered.insert(folder, at: min(ordered.count, targetIndex + (after ? 1 : 0)))
        for (index, item) in ordered.enumerated() where item.sortIndex != index {
            item.sortIndex = index
        }
        try? context?.save()
        return true
    }

    /// Inserisce una cartella trascinata nella posizione `index` tra le sorelle di `parent`
    /// (anche spostandola da un'altra cartella). Una nota trascinata tra le cartelle finisce in `parent`.
    static func insertDropped(_ payload: String, at index: Int, in parent: Folder?, context: ModelContext) {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return }
        if parts[0] == "note", let note = note(withID: id, context: context) {
            move(note, to: parent)
            return
        }
        guard parts[0] == "folder", let folder = folder(withID: id, context: context) else { return }
        if let parent, parent.id == folder.id || parent.isDescendant(of: folder) { return }
        let current = siblings(in: parent, context: context)
        var target = index
        if folder.parent?.id == parent?.id, let oldIndex = current.firstIndex(where: { $0.id == folder.id }), oldIndex < index {
            target -= 1
        }
        if folder.parent?.id != parent?.id {
            folder.parent = parent
            folder.updatedAt = Date()
        }
        var ordered = current.filter { $0.id != folder.id }
        ordered.insert(folder, at: min(max(0, target), ordered.count))
        for (position, item) in ordered.enumerated() where item.sortIndex != position {
            item.sortIndex = position
        }
        try? context.save()
    }

    static func daysRemaining(deletedAt: Date?) -> Int {
        guard let deletedAt else { return trashRetentionDays }
        let expiry = Calendar.current.date(byAdding: .day, value: trashRetentionDays, to: deletedAt) ?? deletedAt
        return max(0, Int((expiry.timeIntervalSinceNow / 86_400).rounded(.up)))
    }

    /// Elimina definitivamente ciò che è nel cestino da più di 30 giorni.
    static func purgeExpiredTrash(context: ModelContext) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -trashRetentionDays, to: Date()) else { return }
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        var changed = false
        for folder in folders {
            if let d = folder.deletedAt, d < cutoff {
                context.delete(folder)
                changed = true
            }
        }
        for note in notes {
            if let d = note.deletedAt, d < cutoff, note.modelContext != nil, !note.isDeleted {
                context.delete(note)
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    static func emptyTrash(context: ModelContext) {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        for folder in folders where folder.deletedAt != nil { context.delete(folder) }
        for note in notes where note.deletedAt != nil && !note.isDeleted { context.delete(note) }
        try? context.save()
    }

    static func note(withID id: UUID, context: ModelContext) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func folder(withID id: UUID, context: ModelContext) -> Folder? {
        var descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Gestisce il drop di una nota o cartella (trascinamento) su una cartella.
    static func handleDrop(_ payloads: [String], into target: Folder?, context: ModelContext) -> Bool {
        var moved = false
        for payload in payloads {
            let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { continue }
            if parts[0] == "note", let note = note(withID: id, context: context) {
                if note.folder?.id != target?.id { move(note, to: target); moved = true }
            } else if parts[0] == "folder", let folder = folder(withID: id, context: context) {
                if folder.parent?.id != target?.id, move(folder, to: target) { moved = true }
            }
        }
        return moved
    }
}
