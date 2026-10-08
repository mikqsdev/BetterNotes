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
        case .infiniteBlank: String(localized: "Bianco")
        case .infiniteGrid: String(localized: "Quadretti")
        case .infiniteLined: String(localized: "Righe")
        case .infiniteDotted: String(localized: "Puntini")
        case .pageBlank: String(localized: "Bianco")
        case .pageLined: String(localized: "Righe")
        case .pageGridSmall: String(localized: "Quadretti piccoli")
        case .pageGridMedium: String(localized: "Quadretti medi")
        case .pageGridLarge: String(localized: "Quadretti grandi")
        case .pageDotted: String(localized: "Puntini")
        case .pdf: String(localized: "Documento")
        }
    }

    var subtitle: String {
        switch self {
        case .infiniteBlank: String(localized: "Foglio enorme, libero")
        case .infiniteGrid: String(localized: "Foglio enorme a quadretti")
        case .infiniteLined: String(localized: "Foglio enorme a righe")
        case .infiniteDotted: String(localized: "Foglio enorme a puntini")
        case .pageBlank: String(localized: "Pagine A4 bianche")
        case .pageLined: String(localized: "Pagine A4 a righe")
        case .pageGridSmall: String(localized: "Quadretti da 4 mm")
        case .pageGridMedium: String(localized: "Quadretti da 5 mm")
        case .pageGridLarge: String(localized: "Quadretti da 1 cm")
        case .pageDotted: String(localized: "Pagine A4 a puntini")
        case .pdf: String(localized: "PDF o Word importato")
        }
    }

    static let infiniteStyles: [PaperStyle] = [.infiniteBlank, .infiniteGrid, .infiniteLined, .infiniteDotted]
    static let pageStyles: [PaperStyle] = [.pageLined, .pageGridSmall, .pageGridMedium, .pageGridLarge, .pageBlank, .pageDotted]
}
