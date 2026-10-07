import CoreGraphics
import Foundation

/// Geometria del documento in coordinate "tela" (non zoomate).
struct PageLayout: Sendable, Equatable {
    static let pageSize = CGSize(width: 800, height: 1131) // proporzioni A4
    static let pageGap: CGFloat = 36
    static let margin: CGFloat = 56
    static let defaultInfiniteSize = CGSize(width: 2400, height: 3200)

    let style: PaperStyle
    let pageRects: [CGRect]
    let docSize: CGSize
    /// Per ogni pagina: indice della pagina PDF di sfondo, oppure -1 per una pagina con il motivo della carta.
    let pageSources: [Int]

    var isInfinite: Bool { style.isInfinite }
    var pageCount: Int { pageRects.count }

    /// Ordine naturale delle pagine: prima le pagine del PDF, poi eventuali pagine vuote.
    static func defaultSources(pageCount: Int, pdfPageCount: Int) -> [Int] {
        (0..<max(1, pageCount)).map { $0 < pdfPageCount ? $0 : -1 }
    }

    static func make(style: PaperStyle, pageCount: Int, pdfPageSizes: [CGSize]? = nil, infiniteSize: CGSize) -> PageLayout {
        make(style: style, pageSources: defaultSources(pageCount: pageCount, pdfPageCount: pdfPageSizes?.count ?? 0),
             pdfPageSizes: pdfPageSizes, infiniteSize: infiniteSize)
    }

    static func make(style: PaperStyle, pageSources: [Int], pdfPageSizes: [CGSize]? = nil, infiniteSize: CGSize) -> PageLayout {
        if style.isInfinite {
            let size = CGSize(
                width: max(infiniteSize.width, defaultInfiniteSize.width),
                height: max(infiniteSize.height, defaultInfiniteSize.height)
            )
            return PageLayout(style: style, pageRects: [], docSize: size, pageSources: [])
        }

        let sources = pageSources.isEmpty ? [-1] : pageSources
        var rects: [CGRect] = []
        var y = margin
        for source in sources {
            var size = pageSize
            if let sizes = pdfPageSizes, source >= 0, source < sizes.count, sizes[source].width > 0 {
                let s = sizes[source]
                size = CGSize(width: pageSize.width, height: (pageSize.width * s.height / s.width).rounded())
            }
            rects.append(CGRect(x: margin, y: y, width: size.width, height: size.height))
            y += size.height + pageGap
        }
        let height = y - pageGap + margin
        return PageLayout(style: style, pageRects: rects, docSize: CGSize(width: pageSize.width + margin * 2, height: height), pageSources: sources)
    }

    func withStyle(_ newStyle: PaperStyle, pdfPageSizes: [CGSize]?) -> PageLayout {
        PageLayout.make(style: newStyle, pageSources: pageSources, pdfPageSizes: pdfPageSizes, infiniteSize: docSize)
    }

    /// Indice (0-based) della pagina più vicina a una coordinata verticale.
    func pageIndex(nearY y: CGFloat) -> Int {
        guard !pageRects.isEmpty else { return 0 }
        for (index, rect) in pageRects.enumerated() where y < rect.maxY + PageLayout.pageGap / 2 {
            return index
        }
        return pageRects.count - 1
    }

    func withGrownInfiniteSize(_ size: CGSize) -> PageLayout {
        PageLayout(style: style, pageRects: [], docSize: size, pageSources: [])
    }
}
