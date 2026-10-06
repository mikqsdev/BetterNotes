import PencilKit
import UIKit

/// Contenuto di una pagina in coordinate relative alla pagina stessa.
struct PageContent {
    var source: Int
    var strokes: [PKStroke]
    var images: [CanvasImage]
}

extension NoteCanvasView {
    /// Divide tratti e immagini per pagina (in base al centro di ciascun elemento).
    func extractPages() -> [PageContent] {
        var pages = layout.pageSources.map { PageContent(source: $0, strokes: [], images: []) }
        guard !pages.isEmpty else { return [] }
        for stroke in canvas.drawing.strokes {
            let index = layout.pageIndex(nearY: stroke.renderBounds.midY)
            let origin = layout.pageRects[index].origin
            var moved = stroke
            moved.transform = stroke.transform.concatenating(CGAffineTransform(translationX: -origin.x, y: -origin.y))
            pages[index].strokes.append(moved)
        }
        for image in images {
            let index = layout.pageIndex(nearY: image.center.y)
            let origin = layout.pageRects[index].origin
            var moved = image
            moved.frame = image.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            pages[index].images.append(moved)
        }
        return pages
    }

    /// Ricompone il documento da un nuovo elenco di pagine e salva una voce di cronologia.
    func applyPages(_ pages: [PageContent], scrollTo pageIndex: Int?) {
        guard !layout.isInfinite, !pages.isEmpty else { return }
        let newLayout = PageLayout.make(style: layout.style, pageSources: pages.map(\.source), pdfPageSizes: pdf?.pageSizes, infiniteSize: .zero)
        var strokes: [PKStroke] = []
        var newImages: [CanvasImage] = []
        for (index, page) in pages.enumerated() {
            let origin = newLayout.pageRects[index].origin
            let shift = CGAffineTransform(translationX: origin.x, y: origin.y)
            strokes += page.strokes.map { stroke in
                var moved = stroke
                moved.transform = stroke.transform.concatenating(shift)
                return moved
            }
            newImages += page.images.map { image in
                var moved = image
                moved.frame = image.frame.offsetBy(dx: origin.x, dy: origin.y)
                return moved
            }
        }
        inkEngine.cancel()
        isApplyingState = true
        canvas.drawing = PKDrawing(strokes: strokes)
        isApplyingState = false
        images = newImages
        syncImageViews()
        if let selected = selectedImageID, !images.contains(where: { $0.id == selected }) { selectImage(nil) }
        setLayout(newLayout, redrawPaper: true)
        commit()
        if let pageIndex {
            DispatchQueue.main.async { [weak self] in self?.scrollToPage(pageIndex, animated: true) }
        }
    }

    private func copied(_ page: PageContent) -> PageContent {
        var copy = page
        copy.images = page.images.map { image in
            var duplicate = CanvasImage(id: UUID(), frame: image.frame, data: image.data)
            duplicate.rotation = image.rotation
            duplicate.rounded = image.rounded
            duplicate.shadow = image.shadow
            return duplicate
        }
        return copy
    }

    func insertBlankPage(at index: Int) {
        var pages = extractPages()
        let target = min(max(0, index), pages.count)
        pages.insert(PageContent(source: -1, strokes: [], images: []), at: target)
        applyPages(pages, scrollTo: target)
    }

    func duplicatePage(_ index: Int) {
        var pages = extractPages()
        guard pages.indices.contains(index) else { return }
        pages.insert(copied(pages[index]), at: index + 1)
        applyPages(pages, scrollTo: index + 1)
    }

    func deletePage(_ index: Int) {
        var pages = extractPages()
        guard pages.count > 1, pages.indices.contains(index) else { return }
        pages.remove(at: index)
        applyPages(pages, scrollTo: min(index, pages.count - 1))
    }

    func movePage(from source: Int, to destination: Int) {
        var pages = extractPages()
        guard pages.indices.contains(source), source != destination else { return }
        let page = pages.remove(at: source)
        pages.insert(page, at: min(max(0, destination), pages.count))
        applyPages(pages, scrollTo: nil)
    }

    func clearPage(_ index: Int) {
        var pages = extractPages()
        guard pages.indices.contains(index) else { return }
        pages[index].strokes = []
        pages[index].images = []
        applyPages(pages, scrollTo: nil)
    }

    func pageHasContent(_ index: Int) -> Bool {
        guard layout.pageRects.indices.contains(index) else { return false }
        let rect = layout.pageRects[index]
        return canvas.drawing.strokes.contains { layout.pageIndex(nearY: $0.renderBounds.midY) == index && $0.renderBounds.intersects(rect.insetBy(dx: -40, dy: -40)) }
            || images.contains { layout.pageIndex(nearY: $0.center.y) == index }
    }
}
