import SwiftUI
import UIKit

enum FolderColor: String, CaseIterable, Identifiable {
    case terracotta, corallo, rosa, senape, salvia, menta, oceano, indaco, lavanda, prugna, cioccolato, ardesia

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .terracotta: 0xC8553D
        case .corallo: 0xEE7B5E
        case .rosa: 0xD9668F
        case .senape: 0xDDA436
        case .salvia: 0x7FA17A
        case .menta: 0x3FA996
        case .oceano: 0x3B7DBF
        case .indaco: 0x4F5BB8
        case .lavanda: 0x9580D0
        case .prugna: 0x8C4A78
        case .cioccolato: 0x8A5D3B
        case .ardesia: 0x5E6873
        }
    }

    var uiColor: UIColor { UIColor(hex: hex) }
    var color: Color { Color(uiColor: uiColor) }

    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Pallino colorato per i menu contestuali (i menu ignorano il tint, serve un'immagine "original").
    var menuSwatch: UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let image = UIImage(systemName: "circle.fill", withConfiguration: config) ?? UIImage()
        return image.withTintColor(uiColor, renderingMode: .alwaysOriginal)
    }
}
