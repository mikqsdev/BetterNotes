import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var colorName: String = FolderColor.terracotta.rawValue
    var iconName: String?
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    /// Ordine personalizzato tra cartelle sorelle (riordinabile dalla barra laterale).
    var sortIndex: Int = 0

    var parent: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var subfolders: [Folder]? = []
    @Relationship(deleteRule: .cascade, inverse: \Note.folder)
    var notes: [Note]? = []

    init(name: String, colorName: String = FolderColor.terracotta.rawValue) {
        self.id = UUID()
        self.name = name
        self.colorName = colorName
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var color: FolderColor { FolderColor(rawValue: colorName) ?? .terracotta }

    /// Vero se la cartella o un suo antenato si trova nel cestino.
    var isEffectivelyTrashed: Bool {
        deletedAt != nil || (parent?.isEffectivelyTrashed ?? false)
    }

    var activeSubfolders: [Folder] { (subfolders ?? []).filter { $0.deletedAt == nil } }
    var activeNotes: [Note] { (notes ?? []).filter { $0.deletedAt == nil } }

    /// Figli per OutlineGroup (nil = foglia, niente freccia).
    var outlineChildren: [Folder]? {
        let children = Folder.manualOrder(activeSubfolders)
        return children.isEmpty ? nil : children
    }

    /// Numero di elementi contenuti (note e sottocartelle), usato dall'icona della cartella.
    var contentCount: Int { activeNotes.count + activeSubfolders.count }

    /// Ordine personalizzato: indice manuale, poi nome.
    static func manualOrder(_ folders: [Folder]) -> [Folder] {
        folders.sorted {
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func isDescendant(of other: Folder) -> Bool {
        var current = parent
        while let c = current {
            if c.id == other.id { return true }
            current = c.parent
        }
        return false
    }

    var itemSummary: String {
        let f = activeSubfolders.count
        let n = activeNotes.count
        var parts: [String] = []
        if f > 0 { parts.append(f == 1 ? "1 cartella" : "\(f) cartelle") }
        if n > 0 || f == 0 { parts.append(n == 1 ? "1 nota" : "\(n) note") }
        return parts.joined(separator: " · ")
    }
}
