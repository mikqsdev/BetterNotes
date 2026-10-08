import PencilKit
import SwiftUI
import UIKit

enum ToolKind: String, Codable, CaseIterable, Identifiable {
    case pen, pencil, marker, fountain, monoline, eraser, lasso

    var id: String { rawValue }

    var isInk: Bool { self != .eraser && self != .lasso }

    static let inkKinds: [ToolKind] = [.pen, .pencil, .fountain, .monoline, .marker]

    var title: String {
        switch self {
        case .pen: String(localized: "Penna")
        case .pencil: String(localized: "Matita")
        case .marker: String(localized: "Evidenziatore")
        case .fountain: String(localized: "Stilografica")
        case .monoline: String(localized: "Fineliner")
        case .eraser: String(localized: "Gomma")
        case .lasso: String(localized: "Lazo")
        }
    }

    var systemImage: String {
        switch self {
        case .pen: "pencil"
        case .pencil: "pencil.and.scribble"
        case .marker: "highlighter"
        case .fountain: "paintbrush.pointed.fill"
        case .monoline: "pencil.line"
        case .eraser: "eraser.fill"
        case .lasso: "lasso"
        }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .pencil: .pencil
        case .marker: .marker
        case .fountain: .fountainPen
        case .monoline: .monoline
        default: .pen
        }
    }

    /// Intervallo di spessore usato dallo slider (in punti).
    var widthRange: ClosedRange<CGFloat> {
        switch self {
        case .pencil: 1.5...22
        case .marker: 8...44
        case .fountain: 1...18
        case .monoline: 0.8...14
        default: 0.8...18
        }
    }
}

enum EraserMode: String, Codable, CaseIterable, Identifiable {
    case pixel, stroke
    var id: String { rawValue }
    var title: String { self == .pixel ? String(localized: "Pixel") : String(localized: "Tratto") }
    var detail: String {
        self == .pixel
            ? String(localized: "Cancella solo i punti che tocchi, come una gomma vera.")
            : String(localized: "Cancella l'intero tratto al primo tocco.")
    }
}

/// Stato persistente degli strumenti di scrittura.
struct ToolState: Codable, Equatable {
    var kind: ToolKind = .pen
    var lastInkKind: ToolKind = .pen
    var colorHex: String = "#1C1C1E"
    var markerColorHex: String = "#F4C430"
    var width: Double = 0.25
    var opacity: Double = 1
    var stabilization: Double = 0.35
    var eraserMode: EraserMode = .pixel
    var eraserWidth: Double = 0.35
    var returnToPen: Bool = false
    var recentColors: [String] = []

    static let palette: [String] = [
        "#1C1C1E", "#5E5E63", "#1F4FD1", "#2A9DD8", "#D7263D", "#E8743B",
        "#2E8B57", "#7FB800", "#7B3FE4", "#D9468F", "#8A5D3B", "#F4C430",
    ]

    var activeColorHex: String {
        get { kind == .marker ? markerColorHex : colorHex }
        set { if kind == .marker { markerColorHex = newValue } else { colorHex = newValue } }
    }

    var uiColor: UIColor { UIColor(hexString: activeColorHex) ?? .black }

    var inkWidth: CGFloat {
        let range = kind.isInk ? kind.widthRange : ToolKind.pen.widthRange
        // Curva quadratica: più precisione sui tratti sottili.
        return range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(width * width)
    }

    var eraserPointWidth: CGFloat { 6 + 74 * CGFloat(eraserWidth * eraserWidth) }

    var pkTool: PKTool {
        switch kind {
        case .eraser:
            return PKEraserTool(eraserMode == .pixel ? .bitmap : .vector, width: eraserPointWidth)
        case .lasso:
            return PKLassoTool()
        default:
            let color = uiColor.withAlphaComponent(CGFloat(max(0.05, min(1, opacity))))
            return PKInkingTool(kind.inkType, color: color, width: inkWidth)
        }
    }

    mutating func rememberColor(_ hex: String) {
        guard !ToolState.palette.contains(hex) else { return }
        recentColors.removeAll { $0 == hex }
        recentColors.insert(hex, at: 0)
        if recentColors.count > 5 { recentColors.removeLast(recentColors.count - 5) }
    }

    static func load() -> ToolState {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.toolState),
              let state = try? JSONDecoder().decode(ToolState.self, from: data) else { return ToolState() }
        return state
    }

    func persist() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: SettingsKey.toolState)
        }
    }
}
