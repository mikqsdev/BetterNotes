import SwiftUI

enum SettingsKey {
    static let appearance = "appearance"
    static let lockZoom = "lockZoom"
    static let twoFingerUndo = "twoFingerUndo"
    static let threeFingerRedo = "threeFingerRedo"
    static let pencilOnly = "pencilOnly"
    static let ruler = "rulerActive"
    static let iCloudSync = "iCloudSync"
    static let sortOrder = "librarySort"
    static let showRecents = "showRecents"
    static let pencilDoubleTap = "pencilDoubleTap"
    static let paletteX = "paletteX"
    static let paletteY = "paletteY"
    static let paletteDock = "paletteDock"
    static let paletteSnapToEdges = "paletteSnapToEdges"
    static let defaultPaper = "defaultPaper"
    static let toolState = "toolState"
    static let showPageNumbers = "showPageNumbers"
}

enum AppSettings {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.appearance: AppearanceMode.system.rawValue,
            SettingsKey.lockZoom: false,
            SettingsKey.twoFingerUndo: true,
            SettingsKey.threeFingerRedo: true,
            SettingsKey.pencilOnly: true,
            SettingsKey.ruler: false,
            SettingsKey.iCloudSync: false,
            SettingsKey.sortOrder: LibrarySort.modified.rawValue,
            SettingsKey.showRecents: true,
            SettingsKey.pencilDoubleTap: PencilDoubleTapAction.system.rawValue,
            SettingsKey.paletteX: -1.0,
            SettingsKey.paletteY: -1.0,
            SettingsKey.paletteDock: "bottom",
            SettingsKey.paletteSnapToEdges: true,
            SettingsKey.defaultPaper: PaperStyle.pageLined.rawValue,
            SettingsKey.showPageNumbers: true,
        ])
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Automatico"
        case .light: "Chiaro"
        case .dark: "Scuro"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case modified, created, name, manual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .modified: "Ultima modifica"
        case .created: "Data di creazione"
        case .name: "Nome"
        case .manual: "Ordine personalizzato"
        }
    }
    var systemImage: String {
        switch self {
        case .modified: "clock.arrow.circlepath"
        case .created: "calendar"
        case .name: "textformat"
        case .manual: "line.3.horizontal"
        }
    }
}

enum PencilDoubleTapAction: String, CaseIterable, Identifiable {
    case system, eraser, previous, palette, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Come da Impostazioni di sistema"
        case .eraser: "Passa alla gomma"
        case .previous: "Strumento precedente"
        case .palette: "Mostra strumenti"
        case .none: "Nessuna azione"
        }
    }
}

/// Impostazioni che influenzano il comportamento della tela.
struct EditorSettings: Equatable {
    var lockZoom = false
    var twoFingerUndo = true
    var threeFingerRedo = true
    var pencilOnly = true
    var ruler = false
    var doubleTap: PencilDoubleTapAction = .system
}
