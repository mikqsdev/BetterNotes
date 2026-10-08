import PencilKit
import UIKit

/// Rendering offscreen di una nota: miniature ed esportazione.
@MainActor
enum NoteRenderer {
    struct Snapshot {
        let layout: PageLayout
        let pdf: PDFSource?
        let drawing: PKDrawing
        let images: [CanvasImage]
    }

    /// Disegna una regione del documento (carta + immagini + inchiostro) nel contesto corrente.
    private static func draw(_ snapshot: Snapshot, region: CGRect, in ctx: CGContext, inkScale: CGFloat, shadows: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: -region.minX, y: -region.minY)
        PaperRenderer(layout: snapshot.layout, pdf: snapshot.pdf).draw(in: ctx, rect: region, drawShadows: shadows)
        for image in snapshot.images where image.boundingBox.insetBy(dx: -30, dy: -30).intersects(region) {
            drawImage(image, in: ctx)
        }
        drawInk(snapshot.drawing, region: region, scale: inkScale)
        ctx.restoreGState()
    }

    /// Lato massimo (in pixel) di un singolo tassello d'inchiostro.
    private static let inkTilePixels: CGFloat = 3072

    /// Disegna l'inchiostro a tasselli, saltando quelli vuoti: un foglio infinito con contenuti sparsi
    /// non genera mai un'unica immagine gigantesca (lenta da creare e pesantissima nel PDF).
    private static func drawInk(_ drawing: PKDrawing, region: CGRect, scale: CGFloat) {
        let strokeBounds = drawing.strokes.map(\.renderBounds).filter { $0.intersects(region) }
        guard !strokeBounds.isEmpty else { return }
        let tile = max(256, (inkTilePixels / scale).rounded(.down))
        var y = region.minY
        while y < region.maxY {
            var x = region.minX
            while x < region.maxX {
                let rect = CGRect(x: x, y: y, width: min(tile, region.maxX - x), height: min(tile, region.maxY - y))
                if strokeBounds.contains(where: { $0.intersects(rect) }) {
                    autoreleasepool {
                        var ink: UIImage?
                        // PKDrawing.image rispetta la modalità scura: forziamo la resa chiara (carta bianca).
                        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                            ink = drawing.image(from: rect, scale: scale)
                        }
                        ink?.draw(in: rect)
                    }
                }
                x += tile
            }
            y += tile
        }
    }

    /// Scala che mantiene un'esportazione entro `maxPixels` pixel complessivi.
    private static func cappedScale(_ preferred: CGFloat, for size: CGSize, maxPixels: CGFloat) -> CGFloat {
        let area = max(1, size.width * size.height)
        return max(0.5, min(preferred, (maxPixels / area).squareRoot()))
    }

    /// Disegna un'immagine con rotazione, angoli arrotondati e ombra.
    private static func drawImage(_ image: CanvasImage, in ctx: CGContext) {
        guard let ui = UIImage(data: image.data) else { return }
        let size = image.frame.size
        let local = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let path = UIBezierPath(roundedRect: local, cornerRadius: image.cornerRadius)
        ctx.saveGState()
        ctx.translateBy(x: image.center.x, y: image.center.y)
        ctx.rotate(by: image.rotation)
        if image.shadow {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: UIColor(white: 0, alpha: 0.32).cgColor)
            ctx.addPath(path.cgPath)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.addPath(path.cgPath)
        ctx.clip()
        ui.draw(in: local)
        ctx.restoreGState()
    }

    static func images(from data: Data?) -> [CanvasImage] {
        let stored = data.flatMap { try? PropertyListDecoder().decode([StoredImage].self, from: $0) } ?? []
        return stored.map {
            var image = CanvasImage(id: $0.id, frame: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height), data: $0.data)
            image.rotation = CGFloat($0.rotation ?? 0)
            image.rounded = $0.rounded ?? false
            image.shadow = $0.shadow ?? false
            return image
        }
    }

    static func encode(_ images: [CanvasImage]) -> Data? {
        guard !images.isEmpty else { return nil }
        let stored = images.map {
            StoredImage(id: $0.id, x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height,
                        data: $0.data, rotation: Double($0.rotation), rounded: $0.rounded, shadow: $0.shadow)
        }
        return try? PropertyListEncoder().encode(stored)
    }

    /// Carica il contenuto di una nota senza aprire l'editor (per miniature ed esportazioni dalla Libreria).
    static func snapshot(for note: Note) -> Snapshot {
        let style = note.paperStyle
        let pdf = note.pdfData.flatMap(PDFSource.init(data:))
        let drawing = note.drawingData.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        let pageCount = style == .pdf ? max(note.pageCount, pdf?.pageCount ?? 1) : max(1, note.pageCount)
        var sources = note.pageSourcesData.flatMap { try? JSONDecoder().decode([Int].self, from: $0) } ?? []
        if sources.isEmpty {
            sources = PageLayout.defaultSources(pageCount: pageCount, pdfPageCount: pdf?.pageCount ?? 0)
        }
        let layout = PageLayout.make(
            style: style,
            pageSources: sources,
            pdfPageSizes: pdf?.pageSizes,
            infiniteSize: CGSize(width: note.canvasWidth, height: note.canvasHeight)
        )
        return Snapshot(layout: layout, pdf: pdf, drawing: drawing, images: images(from: note.attachmentsData))
    }

    private static func contentBounds(of snapshot: Snapshot) -> CGRect {
        NoteCanvasView.contentBounds(drawing: snapshot.drawing, images: snapshot.images)
    }

    /// Anteprima di una singola pagina (gestione pagine).
    static func pageThumbnail(for snapshot: Snapshot, page index: Int, width: CGFloat) -> UIImage? {
        guard snapshot.layout.pageRects.indices.contains(index) else { return nil }
        let region = snapshot.layout.pageRects[index]
        let scale = width / region.width
        let size = CGSize(width: width, height: (region.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.scaleBy(x: scale, y: scale)
            draw(snapshot, region: region, in: context.cgContext, inkScale: scale * 2, shadows: false)
        }
    }

    /// Area da mostrare in copertina: prima pagina, oppure l'inizio del contenuto del foglio infinito.
    static func coverRegion(for snapshot: Snapshot) -> CGRect {
        if let first = snapshot.layout.pageRects.first { return first }
        let content = contentBounds(of: snapshot)
        let aspect = PageLayout.pageSize.height / PageLayout.pageSize.width
        guard !content.isNull else { return CGRect(x: 0, y: 0, width: 900, height: 900 * aspect) }
        let width = min(max(900, content.width + 120), 2200)
        return CGRect(x: content.minX - 60, y: content.minY - 60, width: width, height: width * aspect)
    }

    /// Area esportata di un foglio infinito: solo il contenuto (più un piccolo margine), mai tutto il foglio caricato.
    private static func infiniteExportRegion(for snapshot: Snapshot) -> CGRect {
        let content = contentBounds(of: snapshot)
        guard !content.isNull else {
            return CGRect(origin: CGPoint(x: NoteCanvasView.infiniteChunk, y: NoteCanvasView.infiniteChunk), size: PageLayout.pageSize)
        }
        return content.insetBy(dx: -48, dy: -48).integral
    }

    /// Pagine da esportare: quelle del documento, oppure un'unica pagina attorno al contenuto del foglio infinito.
    private static func exportPages(for snapshot: Snapshot) -> [CGRect] {
        if !snapshot.layout.pageRects.isEmpty { return snapshot.layout.pageRects }
        return [infiniteExportRegion(for: snapshot)]
    }

    private static func drawPages(of snapshot: Snapshot, in context: UIGraphicsPDFRendererContext) {
        for page in exportPages(for: snapshot) {
            context.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
            // Le pagine A4 restano a 3×; un foglio infinito molto esteso scende di risoluzione (fino a ~60 Mpx).
            let scale = snapshot.layout.isInfinite ? cappedScale(3, for: page.size, maxPixels: 60_000_000) : 3
            autoreleasepool {
                draw(snapshot, region: page, in: context.cgContext, inkScale: scale, shadows: false)
            }
        }
    }

    /// Esporta più note: un PDF per nota, oppure tutte in un unico PDF.
    static func exportPDFs(_ notes: [Note], combinedTitle: String?) throws -> [URL] {
        if let combinedTitle {
            let url = exportURL(title: combinedTitle, ext: "pdf")
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: PageLayout.pageSize))
            try renderer.writePDF(to: url) { context in
                for note in notes { drawPages(of: snapshot(for: note), in: context) }
            }
            return [url]
        }
        var used: [String: Int] = [:]
        return try notes.map { note in
            var title = note.displayTitle
            if let count = used[title] { title += " (\(count + 1))" }
            used[note.displayTitle, default: 0] += 1
            return try exportPDF(snapshot(for: note), title: title)
        }
    }

    static func thumbnail(for snapshot: Snapshot, width: CGFloat = 360) -> Data? {
        let region = coverRegion(for: snapshot)
        guard region.width > 0 else { return nil }
        let scale = width / region.width
        let size = CGSize(width: width, height: (region.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.scaleBy(x: scale, y: scale)
            draw(snapshot, region: region, in: context.cgContext, inkScale: scale * 2, shadows: false)
        }
        return image.jpegData(compressionQuality: 0.82)
    }

    static func exportPDF(_ snapshot: Snapshot, title: String) throws -> URL {
        let url = exportURL(title: title, ext: "pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: PageLayout.pageSize))
        try renderer.writePDF(to: url) { context in
            drawPages(of: snapshot, in: context)
        }
        return url
    }

    static func exportImage(_ snapshot: Snapshot, pageIndex: Int, title: String) throws -> URL {
        let region: CGRect
        if snapshot.layout.pageRects.indices.contains(pageIndex) {
            region = snapshot.layout.pageRects[pageIndex]
        } else {
            region = infiniteExportRegion(for: snapshot)
        }
        // Al massimo ~36 Mpx: anche un foglio infinito molto esteso si esporta in pochi istanti.
        let scale = cappedScale(2, for: region.size, maxPixels: 36_000_000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: region.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: region.size))
            draw(snapshot, region: region, in: context.cgContext, inkScale: scale, shadows: false)
        }
        let url = exportURL(title: title, ext: "png")
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func exportURL(title: String, ext: String) -> URL {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "-")
        let name = (safe.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Nota") : safe)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name).appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: url)
        return url
    }
}
