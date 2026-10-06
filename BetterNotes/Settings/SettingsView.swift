import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(Persistence.self) private var persistence
    @Environment(\.modelContext) private var context
    @Query private var folders: [Folder]
    @Query private var notes: [Note]

    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(SettingsKey.showRecents) private var showRecents = true
    @AppStorage(SettingsKey.pencilOnly) private var pencilOnly = true
    @AppStorage(SettingsKey.twoFingerUndo) private var twoFingerUndo = true
    @AppStorage(SettingsKey.threeFingerRedo) private var threeFingerRedo = true
    @AppStorage(SettingsKey.lockZoom) private var lockZoom = false
    @AppStorage(SettingsKey.ruler) private var ruler = false
    @AppStorage(SettingsKey.pencilDoubleTap) private var doubleTap = PencilDoubleTapAction.system.rawValue
    @AppStorage(SettingsKey.showPageNumbers) private var showPageNumbers = true
    @AppStorage(SettingsKey.iCloudSync) private var iCloudSync = false
    @AppStorage(SettingsKey.paletteX) private var paletteX = -1.0
    @AppStorage(SettingsKey.paletteDock) private var paletteDock = PaletteDock.bottom.rawValue
    @AppStorage(SettingsKey.paletteSnapToEdges) private var paletteSnapToEdges = true
    @AppStorage(SettingsKey.paletteY) private var paletteY = -1.0

    @State private var confirmEmptyTrash = false

    private var activeNotes: Int { notes.filter { !$0.isEffectivelyTrashed }.count }
    private var activeFolders: Int { folders.filter { !$0.isEffectivelyTrashed }.count }
    private var trashedCount: Int { notes.filter { $0.deletedAt != nil }.count + folders.filter { $0.deletedAt != nil }.count }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Theme.accent.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BetterNotes").font(.serif(.title2, weight: .bold))
                        Text("\(activeNotes == 1 ? "1 nota" : "\(activeNotes) note") · \(activeFolders == 1 ? "1 cartella" : "\(activeFolders) cartelle")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Aspetto") {
                Picker("Tema", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                Toggle("Mostra note recenti nella Libreria", isOn: $showRecents)
                Toggle("Mostra pagina e zoom nell'editor", isOn: $showPageNumbers)
            }

            Section {
                Toggle(isOn: $pencilOnly) {
                    Label("Favorisci Apple Pencil", systemImage: "applepencil.tip")
                }
                Picker(selection: $doubleTap) {
                    ForEach(PencilDoubleTapAction.allCases) { action in
                        Text(action.title).tag(action.rawValue)
                    }
                } label: {
                    Label("Doppio tocco sulla Pencil", systemImage: "hand.tap")
                }
            } header: {
                Text("Apple Pencil")
            } footer: {
                Text("Con “Favorisci Apple Pencil” attivo, la Pencil scrive e le dita scorrono la pagina. Su Apple Pencil Pro, lo squeeze apre e chiude il pannello strumenti.")
            }

            Section("Gesti e tela") {
                Toggle(isOn: $twoFingerUndo) { Label("Undo con due dita", systemImage: "arrow.uturn.backward") }
                Toggle(isOn: $threeFingerRedo) { Label("Redo con tre dita", systemImage: "arrow.uturn.forward") }
                Toggle(isOn: $lockZoom) { Label("Blocca zoom", systemImage: "lock") }
                Toggle(isOn: $ruler) { Label("Righello", systemImage: "ruler") }
                Toggle(isOn: $paletteSnapToEdges) {
                    Label("Pannello strumenti sui bordi", systemImage: "rectangle.righthalf.inset.filled")
                }
                Button {
                    paletteX = -1
                    paletteY = -1
                    paletteDock = PaletteDock.bottom.rawValue
                } label: {
                    Label("Riposiziona il pannello strumenti", systemImage: "rectangle.bottomhalf.inset.filled")
                }
            }

            Section {
                Toggle(isOn: Binding(get: { BuildFeatures.iCloudSync && iCloudSync }, set: { iCloudSync = $0 })) {
                    Label("Sincronizza con iCloud", systemImage: "icloud")
                }
                .disabled(!BuildFeatures.iCloudSync)
                LabeledContent("Stato") {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(statusText)
                    }
                    .foregroundStyle(.secondary)
                }
                if BuildFeatures.iCloudSync, iCloudSync != persistence.isCloudSyncActive {
                    Label("Chiudi e riapri BetterNotes per applicare la modifica.", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)
                }
                if BuildFeatures.iCloudSync, let error = persistence.cloudError, iCloudSync {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("iCloud")
            } footer: {
                if BuildFeatures.iCloudSync {
                    Text("Facoltativa. Mantiene note e cartelle allineate su tutti i tuoi dispositivi con lo stesso Apple Account. Richiede iCloud attivo nelle Impostazioni di sistema.")
                } else {
                    Text("Non inclusa in questa build: la sincronizzazione iCloud richiede un account Apple Developer. Le note restano salvate solo su questo iPad.")
                }
            }

            Section {
                LabeledContent("Eliminazione automatica", value: "dopo \(LibraryActions.trashRetentionDays) giorni")
                LabeledContent("Elementi nel cestino", value: "\(trashedCount)")
                Button("Svuota cestino", role: .destructive) { confirmEmptyTrash = true }
                    .disabled(trashedCount == 0)
            } header: {
                Text("Cestino")
            }

            Section("Informazioni") {
                LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Formati importabili", value: "PDF, DOCX, DOC")
                LabeledContent("Esportazione", value: "PDF, PNG")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Impostazioni")
        .tint(Theme.accent)
        .confirmationDialog("Svuotare il cestino?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
            Button("Svuota cestino", role: .destructive) { LibraryActions.emptyTrash(context: context) }
        } message: {
            Text("Gli elementi verranno eliminati per sempre.")
        }
    }

    private var statusText: String {
        if !BuildFeatures.iCloudSync { return "Non disponibile in questa build" }
        if persistence.isCloudSyncActive {
            return persistence.iCloudAccountAvailable ? "Sincronizzazione attiva" : "Accedi a iCloud per sincronizzare"
        }
        if iCloudSync, persistence.cloudError != nil { return "Non disponibile" }
        return "Solo su questo iPad"
    }

    private var statusColor: Color {
        if persistence.isCloudSyncActive && persistence.iCloudAccountAvailable { return .green }
        if iCloudSync && persistence.cloudError != nil { return .red }
        return .secondary
    }
}
