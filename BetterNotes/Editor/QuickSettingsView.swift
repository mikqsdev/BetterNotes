import SwiftUI

/// Menù rapido dell'editor: le impostazioni che servono mentre si scrive.
struct QuickSettingsView: View {
    let controller: EditorController
    var openFullSettings: () -> Void

    @AppStorage(SettingsKey.lockZoom) private var lockZoom = false
    @AppStorage(SettingsKey.twoFingerUndo) private var twoFingerUndo = true
    @AppStorage(SettingsKey.threeFingerRedo) private var threeFingerRedo = true
    @AppStorage(SettingsKey.pencilOnly) private var pencilOnly = true
    @AppStorage(SettingsKey.ruler) private var ruler = false
    @AppStorage(SettingsKey.paletteSnapToEdges) private var paletteSnapToEdges = true
    @AppStorage(SettingsKey.showPageNumbers) private var showPageNumbers = true
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $pencilOnly) {
                        QuickRow(title: "Favorisci Apple Pencil", subtitle: "La Pencil scrive, le dita scorrono", systemImage: "applepencil.tip")
                    }
                } footer: {
                    Text("Disattiva per scrivere anche con il dito.")
                }

                Section("Zoom") {
                    Toggle(isOn: $lockZoom) {
                        QuickRow(title: "Blocca zoom", subtitle: "Evita zoom accidentali con il palmo", systemImage: lockZoom ? "lock.fill" : "lock.open")
                    }
                    Button {
                        controller.zoomToFit()
                    } label: {
                        QuickRow(title: "Adatta alla larghezza", subtitle: "Zoom attuale \(controller.zoomPercent)%", systemImage: "arrow.left.and.right.square")
                    }
                    .foregroundStyle(.primary)
                }

                Section("Gesti") {
                    Toggle(isOn: $twoFingerUndo) {
                        QuickRow(title: "Undo con due dita", subtitle: "Tocca con due dita per annullare", systemImage: "arrow.uturn.backward.circle")
                    }
                    Toggle(isOn: $threeFingerRedo) {
                        QuickRow(title: "Redo con tre dita", subtitle: "Tocca con tre dita per ripristinare", systemImage: "arrow.uturn.forward.circle")
                    }
                }

                Section("Strumenti") {
                    Toggle(isOn: $ruler) {
                        QuickRow(title: "Righello", subtitle: "Traccia linee perfettamente dritte", systemImage: "ruler")
                    }
                    Toggle(isOn: $paletteSnapToEdges) {
                        QuickRow(title: "Strumenti sui bordi", subtitle: "Il pannello si aggancia ai bordi dello schermo", systemImage: "rectangle.righthalf.inset.filled")
                    }
                    Toggle(isOn: $showPageNumbers) {
                        QuickRow(title: "Mostra pagina e zoom", subtitle: "Sotto il titolo della nota", systemImage: "number")
                    }
                }

                Section("Aspetto") {
                    Picker(selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    } label: {
                        QuickRow(title: "Tema", subtitle: nil, systemImage: "circle.lefthalf.filled")
                    }
                }

                Section {
                    Button(action: openFullSettings) {
                        HStack {
                            QuickRow(title: "Tutte le impostazioni", subtitle: nil, systemImage: "gearshape")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Menù rapido")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.accent)
        }
        .frame(width: 380, height: 600)
        .presentationCompactAdaptation(.popover)
    }
}

private struct QuickRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.serif(.body, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Theme.accent)
        }
    }
}
