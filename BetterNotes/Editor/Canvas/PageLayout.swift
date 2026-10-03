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

    var isInfinite: Bool { style.isInfinite }
    var pageCount: Int { pageRects.count }

    static func make(style: PaperStyle, pageCount: Int, pdfPageSizes: [CGSize]? = nil, infiniteSize: CGSize) -> PageLayout {
        if style.isInfinite {
            let size = CGSize(
                width: max(infiniteSize.width, defaultInfiniteSize.width),
                height: max(infiniteSize.height, defaultInfiniteSize.height)
            )
            return PageLayout(style: style, pageRects: [], docSize: size)
        }

        var rects: [CGRect] = []
        var y = margin
        let count = max(1, pageCount)
        for index in 0..<count {
            var size = pageSize
            if let sizes = pdfPageSizes, index < sizes.count, sizes[index].width > 0 {
                let s = sizes[index]
                size = CGSize(width: pageSize.width, height: (pageSize.width * s.height / s.width).rounded())
            }
            rects.append(CGRect(x: margin, y: y, width: size.width, height: size.height))
            y += size.height + pageGap
        }
        let height = y - pageGap + margin
        return PageLayout(style: style, pageRects: rects, docSize: CGSize(width: pageSize.width + margin * 2, height: height))
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
        PageLayout(style: style, pageRects: [], docSize: size)
    }
}
