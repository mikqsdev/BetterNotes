import SwiftUI
import UIKit

/// Palette e tipografia di BetterNotes.
/// Chiaro: bianco crema caldo. Scuro: grigio antracite (mai nero puro).
enum Theme {
    static let backgroundUI = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x1F1F22) : UIColor(hex: 0xF8F4EA)
    }
    static let elevatedUI = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x2B2B2F) : UIColor(hex: 0xFFFCF6)
    }
    static let canvasSurroundUI = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x29292C) : UIColor(hex: 0xECE6D8)
    }
    static let inkUI = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0xF2EEE6) : UIColor(hex: 0x2A2723)
    }

    static var background: Color { Color(uiColor: backgroundUI) }
    static var elevated: Color { Color(uiColor: elevatedUI) }
    static var canvasSurround: Color { Color(uiColor: canvasSurroundUI) }
    static var ink: Color { Color(uiColor: inkUI) }
    static var accent: Color { Color("AccentColor") }
    static var hairline: Color { Color.primary.opacity(0.08) }

    /// Colore carta (sempre bianco, come un vero foglio).
    static let paperUI = UIColor(hex: 0xFFFFFF)
}

extension Font {
    /// New York, il serif di sistema di Apple.
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}

extension UIFont {
    static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = (base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    convenience init?(hexString: String) {
        var string = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6 || string.count == 8, let value = UInt64(string, radix: 16) else { return nil }
        if string.count == 8 {
            self.init(
                red: CGFloat((value >> 24) & 0xFF) / 255,
                green: CGFloat((value >> 16) & 0xFF) / 255,
                blue: CGFloat((value >> 8) & 0xFF) / 255,
                alpha: CGFloat(value & 0xFF) / 255
            )
        } else {
            self.init(hex: UInt32(value))
        }
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let resolved = resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

/// Font della barra di navigazione (resta la barra Liquid Glass nativa, cambia solo il carattere).
enum AppearanceConfigurator {
    static func configure() {
        let navBar = UINavigationBar.appearance()
        navBar.largeTitleTextAttributes = [.font: UIFont.serif(.largeTitle, weight: .bold)]
        navBar.titleTextAttributes = [.font: UIFont.serif(.headline, weight: .semibold)]
    }
}
