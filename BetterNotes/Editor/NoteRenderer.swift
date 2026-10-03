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
        for image in snapshot.images where image.frame.intersects(region) {
            UIImage(data: image.data)?.draw(in: image.frame)
        }
        var ink: UIImage?
        // PKDrawing.image rispetta la modalità scura: forziamo la resa chiara (carta bianca).
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = snapshot.drawing.image(from: region, scale: inkScale)
        }
        ink?.draw(in: region)
        ctx.restoreGState()
    }

    /// Area da mostrare in copertina: prima pagina, oppure la zona in alto a sinistra del foglio infinito.
    static func coverRegion(for snapshot: Snapshot) -> CGRect {
        if let first = snapshot.layout.pageRects.first { return first }
        var content = snapshot.drawing.bounds
        for image in snapshot.images { content = content.isNull ? image.frame : content.union(image.frame) }
        let aspect = PageLayout.pageSize.height / PageLayout.pageSize.width
        let width: CGFloat = content.isNull ? 900 : min(max(900, content.maxX + 60), 2200)
        return CGRect(x: 0, y: 0, width: width, height: width * aspect)
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
        var pages = snapshot.layout.pageRects
        if pages.isEmpty {
            var content = snapshot.drawing.bounds
            for image in snapshot.images { content = content.isNull ? image.frame : content.union(image.frame) }
            pages = [content.isNull ? CGRect(origin: .zero, size: PageLayout.pageSize) : content.insetBy(dx: -48, dy: -48).intersection(CGRect(origin: .zero, size: snapshot.layout.docSize))]
        }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pages[0].size))
        try renderer.writePDF(to: url) { context in
            for page in pages {
                context.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                draw(snapshot, region: page, in: context.cgContext, inkScale: 3, shadows: false)
            }
        }
        return url
    }

    static func exportImage(_ snapshot: Snapshot, pageIndex: Int, title: String) throws -> URL {
        let region: CGRect
        if snapshot.layout.pageRects.indices.contains(pageIndex) {
            region = snapshot.layout.pageRects[pageIndex]
        } else {
            var content = snapshot.drawing.bounds
            for image in snapshot.images { content = content.isNull ? image.frame : content.union(image.frame) }
            region = content.isNull ? CGRect(origin: .zero, size: PageLayout.pageSize) : content.insetBy(dx: -40, dy: -40)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: region.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: region.size))
            draw(snapshot, region: region, in: context.cgContext, inkScale: 2, shadows: false)
        }
        let url = exportURL(title: title, ext: "png")
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func exportURL(title: String, ext: String) -> URL {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "-")
        let name = (safe.trimmingCharacters(in: .whitespaces).isEmpty ? "Nota" : safe)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name).appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: url)
        return url
    }
}
