import CoreGraphics
import Foundation
import UIKit

/// Documento PDF thread-safe (le tile vengono disegnate su thread in background).
final class PDFSource: @unchecked Sendable {
    private let document: CGPDFDocument
    private let lock = NSLock()
    let pageSizes: [CGSize]

    init?(data: Data) {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              document.numberOfPages > 0 else { return nil }
        self.document = document
        var sizes: [CGSize] = []
        for index in 1...document.numberOfPages {
            guard let page = document.page(at: index) else { sizes.append(PageLayout.pageSize); continue }
            let box = page.getBoxRect(.cropBox)
            let rotation = ((page.rotationAngle % 360) + 360) % 360
            sizes.append(rotation == 90 || rotation == 270 ? CGSize(width: box.height, height: box.width) : box.size)
        }
        pageSizes = sizes
    }

    var pageCount: Int { pageSizes.count }

    /// Disegna la pagina `index` (0-based) riempiendo `rect` in un contesto con origine in alto a sinistra.
    func draw(page index: Int, in rect: CGRect, context ctx: CGContext) {
        lock.lock()
        defer { lock.unlock() }
        guard let page = document.page(at: index + 1) else { return }
        let box = page.getBoxRect(.cropBox)
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        let rotated = (rotation == 90 || rotation == 270) ? CGSize(width: box.height, height: box.width) : box.size
        guard rotated.width > 0, rotated.height > 0 else { return }
        let scale = rect.width / rotated.width

        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: scale, y: scale)
        // Passa allo spazio PDF (origine in basso a sinistra).
        ctx.translateBy(x: 0, y: rotated.height)
        ctx.scaleBy(x: 1, y: -1)
        switch rotation {
        case 90:
            ctx.translateBy(x: 0, y: rotated.height)
            ctx.rotate(by: -.pi / 2)
        case 180:
            ctx.translateBy(x: rotated.width, y: rotated.height)
            ctx.rotate(by: .pi)
        case 270:
            ctx.translateBy(x: rotated.width, y: 0)
            ctx.rotate(by: .pi / 2)
        default:
            break
        }
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.interpolationQuality = .high
        ctx.setRenderingIntent(.defaultIntent)
        ctx.drawPDFPage(page)
        ctx.restoreGState()
    }
}

/// Disegna la carta (sfondo, righe, quadretti, puntini, pagine PDF). Puro Core Graphics, thread-safe.
struct PaperRenderer: Sendable {
    let layout: PageLayout
    let pdf: PDFSource?

    static let lineColor = UIColor(red: 0.56, green: 0.69, blue: 0.84, alpha: 0.75).cgColor
    static let gridColor = UIColor(red: 0.62, green: 0.73, blue: 0.86, alpha: 0.62).cgColor
    static let marginColor = UIColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 0.65).cgColor
    static let dotColor = UIColor(red: 0.55, green: 0.58, blue: 0.64, alpha: 0.75).cgColor
    static let shadowColor = UIColor(white: 0, alpha: 0.13).cgColor

    /// - Parameter fillPaper: disegna anche il bianco della carta. Sulla tela è falso: il bianco e le ombre
    ///   sono un layer separato (sempre visibile), così le tile non lasciano mai "buchi" scuri mentre si ridisegnano.
    func draw(in ctx: CGContext, rect: CGRect, drawShadows: Bool = true, fillPaper: Bool = true) {
        if layout.isInfinite {
            if fillPaper {
                ctx.setFillColor(Theme.paperUI.cgColor)
                ctx.fill(rect)
            }
            let area = CGRect(origin: .zero, size: layout.docSize)
            Self.drawPattern(layout.style.pattern, in: area, clip: rect, isPage: false, ctx: ctx)
            return
        }

        for (index, page) in layout.pageRects.enumerated() {
            let shadowReach: CGFloat = drawShadows && fillPaper ? 30 : 0
            guard page.insetBy(dx: -shadowReach, dy: -shadowReach).intersects(rect) else { continue }
            if fillPaper { Self.drawPage(page, ctx: ctx, shadow: drawShadows) }
            ctx.saveGState()
            ctx.clip(to: page)
            let source = index < layout.pageSources.count ? layout.pageSources[index] : -1
            if layout.style == .pdf {
                if let pdf, source >= 0, source < pdf.pageCount {
                    pdf.draw(page: source, in: page, context: ctx)
                }
            } else {
                Self.drawPattern(layout.style.pattern, in: page, clip: rect.intersection(page), isPage: true, ctx: ctx)
            }
            ctx.restoreGState()
        }
    }

    static func drawPage(_ page: CGRect, ctx: CGContext, shadow: Bool) {
        ctx.saveGState()
        if shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 22, color: shadowColor)
        }
        ctx.setFillColor(Theme.paperUI.cgColor)
        ctx.fill(page)
        ctx.restoreGState()
    }

    /// Disegna il motivo della carta dentro `area`, limitandosi a `clip`.
    static func drawPattern(_ pattern: PaperPattern, in area: CGRect, clip: CGRect, isPage: Bool, ctx: CGContext, lineScale: CGFloat = 1) {
        let visible = clip.intersection(area)
        guard !visible.isNull, !visible.isEmpty else { return }

        switch pattern {
        case .none:
            return

        case .grid(let spacing):
            let path = CGMutablePath()
            let firstCol = max(1, Int(floor((visible.minX - area.minX) / spacing)))
            let lastCol = Int(ceil((visible.maxX - area.minX) / spacing))
            if firstCol <= lastCol {
                for col in firstCol...lastCol {
                    let x = area.minX + CGFloat(col) * spacing
                    guard x < area.maxX else { break }
                    path.move(to: CGPoint(x: x, y: visible.minY))
                    path.addLine(to: CGPoint(x: x, y: visible.maxY))
                }
            }
            let firstRow = max(1, Int(floor((visible.minY - area.minY) / spacing)))
            let lastRow = Int(ceil((visible.maxY - area.minY) / spacing))
            if firstRow <= lastRow {
                for row in firstRow...lastRow {
                    let y = area.minY + CGFloat(row) * spacing
                    guard y < area.maxY else { break }
                    path.move(to: CGPoint(x: visible.minX, y: y))
                    path.addLine(to: CGPoint(x: visible.maxX, y: y))
                }
            }
            ctx.saveGState()
            ctx.setStrokeColor(gridColor)
            ctx.setLineWidth((spacing < 20 ? 0.55 : 0.7) * lineScale)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()

        case .lines(let spacing):
            let top = isPage ? area.minY + 3 * spacing : area.minY + spacing
            let bottom = isPage ? area.maxY - spacing : area.maxY
            let path = CGMutablePath()
            let first = max(0, Int(floor((visible.minY - top) / spacing)))
            let last = Int(ceil((visible.maxY - top) / spacing))
            if first <= last {
                for index in first...last {
                    let y = top + CGFloat(index) * spacing
                    guard y <= bottom else { break }
                    guard y >= visible.minY - 1 else { continue }
                    path.move(to: CGPoint(x: visible.minX, y: y))
                    path.addLine(to: CGPoint(x: visible.maxX, y: y))
                }
            }
            ctx.saveGState()
            ctx.setStrokeColor(lineColor)
            ctx.setLineWidth(0.8 * lineScale)
            ctx.addPath(path)
            ctx.strokePath()
            if isPage {
                let marginX = area.minX + 84
                if marginX >= visible.minX - 1 && marginX <= visible.maxX + 1 {
                    ctx.setStrokeColor(marginColor)
                    ctx.setLineWidth(1 * lineScale)
                    ctx.move(to: CGPoint(x: marginX, y: visible.minY))
                    ctx.addLine(to: CGPoint(x: marginX, y: visible.maxY))
                    ctx.strokePath()
                }
            }
            ctx.restoreGState()

        case .dots(let spacing):
            let radius: CGFloat = 1.25 * lineScale
            let firstCol = max(1, Int(floor((visible.minX - area.minX) / spacing)))
            let lastCol = Int(ceil((visible.maxX - area.minX) / spacing))
            let firstRow = max(1, Int(floor((visible.minY - area.minY) / spacing)))
            let lastRow = Int(ceil((visible.maxY - area.minY) / spacing))
            guard firstCol <= lastCol, firstRow <= lastRow else { return }
            ctx.saveGState()
            ctx.setFillColor(dotColor)
            for row in firstRow...lastRow {
                let y = area.minY + CGFloat(row) * spacing
                guard y < area.maxY else { break }
                for col in firstCol...lastCol {
                    let x = area.minX + CGFloat(col) * spacing
                    guard x < area.maxX else { break }
                    ctx.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
            }
            ctx.fillPath()
            ctx.restoreGState()
        }
    }
}

/// Layer a tile: disegno vettoriale nitido a qualsiasi livello di zoom.
final class PaperTiledLayer: CATiledLayer {
    private let lock = NSLock()
    private var _renderer: PaperRenderer?

    var renderer: PaperRenderer? {
        get { lock.lock(); defer { lock.unlock() }; return _renderer }
        set { lock.lock(); _renderer = newValue; lock.unlock() }
    }

    override class func fadeDuration() -> CFTimeInterval { 0.05 }

    override func draw(in ctx: CGContext) {
        guard let renderer else { return }
        renderer.draw(in: ctx, rect: ctx.boundingBoxOfClipPath, drawShadows: false, fillPaper: false)
    }
}

final class PaperView: UIView {
    override class var layerClass: AnyClass { PaperTiledLayer.self }
    var tiledLayer: PaperTiledLayer { layer as! PaperTiledLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        tiledLayer.tileSize = CGSize(width: 1024, height: 1024)
        tiledLayer.levelsOfDetail = 5
        tiledLayer.levelsOfDetailBias = 3
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
