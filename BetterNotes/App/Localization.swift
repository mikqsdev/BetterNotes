import Foundation

/// Conteggi di note e cartelle, già tradotti (singolare e plurale).
enum Counts {
    static func notes(_ count: Int) -> String {
        count == 1 ? String(localized: "1 nota") : String(localized: "\(count) note")
    }

    static func folders(_ count: Int) -> String {
        count == 1 ? String(localized: "1 cartella") : String(localized: "\(count) cartelle")
    }
}
