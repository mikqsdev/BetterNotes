import Observation
import SwiftUI

/// Stato della selezione multipla di note nella Libreria.
@MainActor
@Observable
final class LibrarySelection {
    var isActive = false
    var noteIDs: Set<UUID> = []

    func contains(_ note: Note) -> Bool { noteIDs.contains(note.id) }

    func toggle(_ note: Note) {
        if noteIDs.contains(note.id) { noteIDs.remove(note.id) } else { noteIDs.insert(note.id) }
    }

    func begin(selecting note: Note? = nil) {
        isActive = true
        noteIDs = note.map { [$0.id] } ?? []
    }

    func end() {
        isActive = false
        noteIDs = []
    }
}

extension EnvironmentValues {
    @Entry var librarySelection: LibrarySelection? = nil
}

/// File pronti da condividere (una o più esportazioni).
struct ShareFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Campo di ricerca personalizzato: a differenza di `.searchable`, non nasconde il titolo
/// della schermata quando è attivo.
struct InlineSearchField: View {
    @Binding var text: String
    var prompt: String
    var width: CGFloat? = 280
    /// Fuori dalla barra di navigazione il campo disegna il proprio sfondo in vetro.
    var drawsBackground = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancella ricerca")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: 40)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background {
            if drawsBackground {
                Capsule().fill(Theme.elevated)
                    .overlay(Capsule().strokeBorder(Theme.hairline))
            }
        }
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: text.isEmpty)
    }
}
