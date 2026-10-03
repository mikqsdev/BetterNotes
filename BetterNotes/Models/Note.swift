import Foundation
import SwiftData
import CoreGraphics

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var iconName: String?
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastOpenedAt: Date?
    var deletedAt: Date?

    var paperStyleRaw: String = PaperStyle.pageLined.rawValue
    var pageCount: Int = 1
    var canvasWidth: Double = 0
    var canvasHeight: Double = 0
    var sourceFileName: String?

    @Attribute(.externalStorage) var drawingData: Data?
    @Attribute(.externalStorage) var attachmentsData: Data?
    @Attribute(.externalStorage) var pdfData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?

    var folder: Folder?

    init(title: String, style: PaperStyle) {
        self.id = UUID()
        self.title = title
        self.paperStyleRaw = style.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        if style.isInfinite {
            canvasWidth = PageLayout.defaultInfiniteSize.width
            canvasHeight = PageLayout.defaultInfiniteSize.height
        }
    }

    var paperStyle: PaperStyle { PaperStyle(rawValue: paperStyleRaw) ?? .pageLined }

    var isEffectivelyTrashed: Bool {
        deletedAt != nil || (folder?.isEffectivelyTrashed ?? false)
    }

    var displayTitle: String { title.isEmpty ? "Senza titolo" : title }
}

/// Immagine incollata nella nota (serializzata in `Note.attachmentsData`).
struct StoredImage: Codable {
    var id: UUID
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var data: Data
}
