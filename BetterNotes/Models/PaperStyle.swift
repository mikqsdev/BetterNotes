import Foundation
import CoreGraphics

enum PaperPattern: Equatable, Sendable {
    case none
    case grid(CGFloat)
    case lines(CGFloat)
    case dots(CGFloat)
}

enum PaperStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case infiniteBlank, infiniteGrid, infiniteLined, infiniteDotted
    case pageBlank, pageLined, pageGridSmall, pageGridMedium, pageGridLarge, pageDotted
    case pdf

    var id: String { rawValue }

    var isInfinite: Bool {
        switch self {
        case .infiniteBlank, .infiniteGrid, .infiniteLined, .infiniteDotted: true
        default: false
        }
    }

    var pattern: PaperPattern {
        switch self {
        case .infiniteBlank, .pageBlank, .pdf: .none
        case .infiniteGrid: .grid(32)
        case .infiniteLined: .lines(36)
        case .infiniteDotted: .dots(30)
        case .pageLined: .lines(32)
        case .pageGridSmall: .grid(17)
        case .pageGridMedium: .grid(24)
        case .pageGridLarge: .grid(34)
        case .pageDotted: .dots(24)
        }
    }

    var title: String {
        switch self {
        case .infiniteBlank: "Bianco"
        case .infiniteGrid: "Quadretti"
        case .infiniteLined: "Righe"
        case .infiniteDotted: "Puntini"
        case .pageBlank: "Bianco"
        case .pageLined: "Righe"
        case .pageGridSmall: "Quadretti piccoli"
        case .pageGridMedium: "Quadretti medi"
        case .pageGridLarge: "Quadretti grandi"
        case .pageDotted: "Puntini"
        case .pdf: "Documento"
        }
    }

    var subtitle: String {
        switch self {
        case .infiniteBlank: "Foglio enorme, libero"
        case .infiniteGrid: "Foglio enorme a quadretti"
        case .infiniteLined: "Foglio enorme a righe"
        case .infiniteDotted: "Foglio enorme a puntini"
        case .pageBlank: "Pagine A4 bianche"
        case .pageLined: "Pagine A4 a righe"
        case .pageGridSmall: "Quadretti da 4 mm"
        case .pageGridMedium: "Quadretti da 5 mm"
        case .pageGridLarge: "Quadretti da 1 cm"
        case .pageDotted: "Pagine A4 a puntini"
        case .pdf: "PDF o Word importato"
        }
    }

    static let infiniteStyles: [PaperStyle] = [.infiniteBlank, .infiniteGrid, .infiniteLined, .infiniteDotted]
    static let pageStyles: [PaperStyle] = [.pageLined, .pageGridSmall, .pageGridMedium, .pageGridLarge, .pageBlank, .pageDotted]
}
