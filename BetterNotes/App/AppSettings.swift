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
    static let infiniteRecenter = "infiniteRecenter"
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
            SettingsKey.infiniteRecenter: InfiniteRecenterMode.content.rawValue,
        ])
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "Automatico")
        case .light: String(localized: "Chiaro")
        case .dark: String(localized: "Scuro")
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
        case .modified: String(localized: "Ultima modifica")
        case .created: String(localized: "Data di creazione")
        case .name: String(localized: "Nome")
        case .manual: String(localized: "Ordine personalizzato")
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
        case .system: String(localized: "Come da Impostazioni di sistema")
        case .eraser: String(localized: "Passa alla gomma")
        case .previous: String(localized: "Strumento precedente")
        case .palette: String(localized: "Mostra strumenti")
        case .none: String(localized: "Nessuna azione")
        }
    }
}

/// Cosa fa il tasto "Inquadra" nei fogli infiniti.
enum InfiniteRecenterMode: String, CaseIterable, Identifiable {
    case content, defaultView
    var id: String { rawValue }
    var title: String {
        switch self {
        case .content: String(localized: "Centra sul contenuto")
        case .defaultView: String(localized: "Torna alla vista predefinita")
        }
    }
    var systemImage: String {
        switch self {
        case .content: "viewfinder"
        case .defaultView: "1.magnifyingglass"
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
