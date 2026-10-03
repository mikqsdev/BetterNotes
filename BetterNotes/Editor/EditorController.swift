import Observation
import PencilKit
import SwiftData
import SwiftUI
import UIKit

struct EditorToast: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let systemImage: String
}

/// Stato e logica dell'editor di una nota. Fa da ponte tra SwiftUI e la tela UIKit.
@MainActor
@Observable
final class EditorController: Identifiable {
    let note: Note
    nonisolated let id: UUID

    @ObservationIgnored let canvasView: NoteCanvasView
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored private var toastWorkItem: DispatchWorkItem?
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var thumbnailIsStale = false
    @ObservationIgnored private var settings = EditorSettings()
    @ObservationIgnored private var toolBeforeDoubleTap: ToolKind?

    var tool: ToolState {
        didSet {
            guard tool != oldValue else { return }
            tool.persist()
            canvasView.apply(tool: tool)
        }
    }

    var isPaletteExpanded = false
    var canUndo = false
    var canRedo = false
    var isEditingImages = false
    var hasSelectedImage = false
    var currentPage = 1
    var pageCount: Int
    var zoomPercent = 100
    var toast: EditorToast?

    var style: PaperStyle { note.paperStyle }
    var isPaged: Bool { !note.paperStyle.isInfinite }

    init(note: Note) {
        self.note = note
        self.id = note.id
        let style = note.paperStyle
        let pdf = note.pdfData.flatMap(PDFSource.init(data:))
        let drawing = note.drawingData.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        let stored = note.attachmentsData.flatMap { try? PropertyListDecoder().decode([StoredImage].self, from: $0) } ?? []
        let images = stored.map {
            CanvasImage(id: $0.id, frame: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height), data: $0.data)
        }
        let pageCount = style == .pdf ? max(note.pageCount, pdf?.pageCount ?? 1) : max(1, note.pageCount)
        let layout = PageLayout.make(
            style: style,
            pageCount: pageCount,
            pdfPageSizes: pdf?.pageSizes,
            infiniteSize: CGSize(width: note.canvasWidth, height: note.canvasHeight)
        )
        self.pageCount = layout.pageCount
        self.tool = ToolState.load()
        self.canvasView = NoteCanvasView(drawing: drawing, images: images, layout: layout, pdf: pdf)
        canvasView.controller = self
        canvasView.apply(tool: tool)
    }

    // MARK: - Strumenti

    func select(_ kind: ToolKind) {
        if isEditingImages { finishImageEditing() }
        if kind.isInk { tool.lastInkKind = kind }
        tool.kind = kind
    }

    /// Tocco sull'icona della matita: seleziona l'inchiostro e apre il sottomenu.
    func tapPencil() {
        if !tool.kind.isInk {
            select(tool.lastInkKind)
        }
        if isEditingImages { finishImageEditing() }
        isPaletteExpanded.toggle()
    }

    func tapEraser() {
        if tool.kind == .eraser {
            isPaletteExpanded.toggle()
        } else {
            select(.eraser)
        }
    }

    func returnToInk() {
        select(tool.lastInkKind)
    }

    func togglePalette() {
        isPaletteExpanded.toggle()
    }

    func setColor(_ hex: String) {
        if !tool.kind.isInk { select(tool.lastInkKind) }
        tool.activeColorHex = hex
        tool.rememberColor(hex)
    }

    func handlePencilDoubleTap() {
        var action = settings.doubleTap
        if action == .system {
            switch UIPencilInteraction.preferredTapAction {
            case .switchEraser: action = .eraser
            case .switchPrevious: action = .previous
            case .showColorPalette, .showInkAttributes, .showContextualPalette: action = .palette
            case .ignore: action = .none
            default: action = .eraser
            }
        }
        switch action {
        case .eraser:
            if tool.kind == .eraser { returnToInk() } else { select(.eraser) }
        case .previous:
            let current = tool.kind
            select(toolBeforeDoubleTap ?? (current == .eraser ? tool.lastInkKind : .eraser))
            toolBeforeDoubleTap = current
        case .palette:
            togglePalette()
        case .none, .system:
            break
        }
    }

    func userDidBeginDrawing() {
        if isPaletteExpanded { isPaletteExpanded = false }
    }

    // MARK: - Impostazioni

    func apply(settings newSettings: EditorSettings) {
        settings = newSettings
        canvasView.apply(settings: newSettings)
    }

    func zoomToFit() {
        canvasView.zoomToFit(animated: true)
    }

    // MARK: - Cronologia

    func undo() { canvasView.undo() }
    func redo() { canvasView.redo() }

    func historyDidChange() {
        if canUndo != canvasView.canUndo { canUndo = canvasView.canUndo }
        if canRedo != canvasView.canRedo { canRedo = canvasView.canRedo }
    }

    func showToast(_ text: String, systemImage: String) {
        toastWorkItem?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toast = EditorToast(text: text, systemImage: systemImage)
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    // MARK: - Viewport e pagine

    func viewportDidChange(page: Int, zoomPercent percent: Int) {
        if currentPage != page { currentPage = page }
        if zoomPercent != percent { zoomPercent = percent }
    }

    func addPage() {
        canvasView.addPage()
        pageCount = canvasView.layout.pageCount
        showToast("Pagina \(pageCount) aggiunta", systemImage: "doc.badge.plus")
    }

    func goToPage(_ page: Int) {
        canvasView.scrollToPage(page - 1, animated: true)
    }

    // MARK: - Immagini

    func insertImage(data: Data) {
        guard let image = UIImage(data: data) else { return }
        let prepared = Self.prepareImage(image)
        canvasView.insertImage(data: prepared.data, pixelSize: prepared.size)
        isPaletteExpanded = false
    }

    /// Ridimensiona le foto molto grandi e le comprime, per mantenere leggere le note.
    private static func prepareImage(_ image: UIImage) -> (data: Data, size: CGSize) {
        let maxSide: CGFloat = 2200
        let size = image.size
        let factor = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        let hasAlpha: Bool = {
            guard let alpha = image.cgImage?.alphaInfo else { return false }
            return [.first, .last, .premultipliedFirst, .premultipliedLast].contains(alpha)
        }()
        let data = (hasAlpha ? rendered.pngData() : rendered.jpegData(compressionQuality: 0.86)) ?? Data()
        return (data, target)
    }

    func startImageEditing() {
        isPaletteExpanded = false
        canvasView.setEditingImages(true)
    }

    func finishImageEditing() {
        canvasView.setEditingImages(false)
    }

    func deleteSelectedImage() { canvasView.deleteSelectedImage() }
    func bringSelectedImageToFront() { canvasView.bringSelectedImageToFront() }

    func imageEditingDidChange(_ editing: Bool) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isEditingImages = editing }
    }

    func imageSelectionDidChange(_ selected: Bool) {
        if hasSelectedImage != selected { hasSelectedImage = selected }
    }

    // MARK: - Salvataggio

    func contentDidChange() {
        isDirty = true
        thumbnailIsStale = true
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save(includeThumbnail: false) }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    var snapshot: NoteRenderer.Snapshot {
        NoteRenderer.Snapshot(layout: canvasView.layout, pdf: canvasView.pdf, drawing: canvasView.drawing, images: canvasView.images)
    }

    func save(includeThumbnail: Bool) {
        saveWorkItem?.cancel()
        let needsThumbnail = includeThumbnail && (thumbnailIsStale || note.thumbnailData == nil)
        guard isDirty || needsThumbnail else { return }
        let layout = canvasView.layout
        if isDirty {
            note.drawingData = canvasView.drawing.dataRepresentation()
            let stored = canvasView.images.map {
                StoredImage(id: $0.id, x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height, data: $0.data)
            }
            note.attachmentsData = stored.isEmpty ? nil : try? PropertyListEncoder().encode(stored)
            note.pageCount = max(1, layout.pageCount)
            if layout.isInfinite {
                note.canvasWidth = layout.docSize.width
                note.canvasHeight = layout.docSize.height
            }
            note.updatedAt = Date()
            note.folder?.updatedAt = Date()
        }
        if needsThumbnail {
            note.thumbnailData = NoteRenderer.thumbnail(for: snapshot)
            thumbnailIsStale = false
        }
        isDirty = false
        try? note.modelContext?.save()
    }

    func close() {
        if isEditingImages { finishImageEditing() }
        save(includeThumbnail: true)
    }

    // MARK: - Esportazione

    func exportPDF() -> URL? {
        try? NoteRenderer.exportPDF(snapshot, title: note.displayTitle)
    }

    func exportCurrentPageImage() -> URL? {
        let suffix = isPaged ? " - pagina \(currentPage)" : ""
        return try? NoteRenderer.exportImage(snapshot, pageIndex: currentPage - 1, title: note.displayTitle + suffix)
    }
}
