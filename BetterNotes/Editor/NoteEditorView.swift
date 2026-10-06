import SwiftUI

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct NoteEditorView: View {
    @Bindable var controller: EditorController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.lockZoom) private var lockZoom = false
    @AppStorage(SettingsKey.twoFingerUndo) private var twoFingerUndo = true
    @AppStorage(SettingsKey.threeFingerRedo) private var threeFingerRedo = true
    @AppStorage(SettingsKey.pencilOnly) private var pencilOnly = true
    @AppStorage(SettingsKey.ruler) private var ruler = false
    @AppStorage(SettingsKey.pencilDoubleTap) private var doubleTapRaw = PencilDoubleTapAction.system.rawValue
    @AppStorage(SettingsKey.showPageNumbers) private var showPageNumbers = true

    @State private var showQuickSettings = false
    @State private var showFullSettings = false
    @State private var showRename = false
    @State private var shareItem: ShareItem?
    @State private var showPages = false

    private var editorSettings: EditorSettings {
        EditorSettings(
            lockZoom: lockZoom,
            twoFingerUndo: twoFingerUndo,
            threeFingerRedo: threeFingerRedo,
            pencilOnly: pencilOnly,
            ruler: ruler,
            doubleTap: PencilDoubleTapAction(rawValue: doubleTapRaw) ?? .system
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                CanvasHost(view: controller.canvasView)
                    .ignoresSafeArea()

                if controller.isEditingImages {
                    imageEditingBar
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    FloatingToolPalette(controller: controller, bounds: proxy.size)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 6)

                if let toast = controller.toast {
                    Label(toast.text, systemImage: toast.systemImage)
                        .font(.serif(.headline, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .id(toast.id)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Theme.canvasSurround.ignoresSafeArea())
        .onAppear { controller.apply(settings: editorSettings) }
        .onChange(of: editorSettings) { _, settings in controller.apply(settings: settings) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.save(includeThumbnail: true) }
        }
        .sheet(isPresented: $showFullSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fine") { showFullSettings = false }
                        }
                    }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .modifier(RenameAlert(isPresented: $showRename, title: "Rinomina nota", current: controller.note.title) { name in
            controller.note.title = name
            controller.note.updatedAt = Date()
            try? controller.note.modelContext?.save()
        })
        .sensoryFeedback(.selection, trigger: controller.tool.kind)
        .statusBarHidden(false)
    }

    // MARK: - Barra superiore

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 30, height: 34)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Indietro")

                    Button {
                        showQuickSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 30, height: 34)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Menù rapido")
                    .popover(isPresented: $showQuickSettings, arrowEdge: .top) {
                        QuickSettingsView(controller: controller) {
                            showQuickSettings = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showFullSettings = true }
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            Button {
                showRename = true
            } label: {
                VStack(spacing: 1) {
                    Text(controller.note.displayTitle)
                        .font(.serif(.headline, weight: .semibold))
                        .lineLimit(1)
                    if showPageNumbers {
                        Text(statusLine)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: 360)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer(minLength: 12)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if controller.isPaged {
                        Button {
                            showPages = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("\(controller.pageCount)")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .contentTransition(.numericText())
                            }
                            .padding(.horizontal, 4)
                            .frame(height: 34)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Gestisci pagine, \(controller.pageCount) pagine")
                        .popover(isPresented: $showPages, arrowEdge: .top) {
                            PageManagerView(controller: controller) { url in
                                showPages = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { shareItem = ShareItem(url: url) }
                            }
                        }
                    } else {
                        Button {
                            controller.showAllContent()
                        } label: {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 30, height: 34)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Mostra tutto il contenuto")
                        .help("Mostra tutto il contenuto")
                    }

                    Menu {
                        Button {
                            controller.note.isFavorite.toggle()
                            try? controller.note.modelContext?.save()
                        } label: {
                            Label(controller.note.isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti",
                                  systemImage: controller.note.isFavorite ? "star.slash" : "star")
                        }
                        Button { showRename = true } label: { Label("Rinomina", systemImage: "pencil") }
                        if controller.isPaged {
                            Button { showPages = true } label: {
                                Label("Gestisci pagine", systemImage: "rectangle.portrait.on.rectangle.portrait")
                            }
                        }
                        Divider()
                        Button {
                            controller.save(includeThumbnail: false)
                            if let url = controller.exportPDF() { shareItem = ShareItem(url: url) }
                        } label: {
                            Label("Esporta PDF", systemImage: "doc.richtext")
                        }
                        Button {
                            if let url = controller.exportCurrentPageImage() { shareItem = ShareItem(url: url) }
                        } label: {
                            Label(controller.isPaged ? "Esporta pagina come immagine" : "Esporta come immagine", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 30, height: 34)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Condividi ed esporta")
                }
            }
        }
    }

    private var statusLine: String {
        if controller.isPaged {
            return "Pagina \(controller.currentPage) di \(controller.pageCount) · \(controller.zoomPercent)%"
        }
        return "Foglio infinito · \(controller.zoomPercent)%"
    }

    // MARK: - Modifica immagini

    private var imageEditingBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                if controller.hasSelectedImage {
                    HStack(spacing: 2) {
                        imageAction("Duplica", "plus.square.on.square") { controller.duplicateSelectedImage() }
                        imageAction("Taglia", "scissors") { controller.cutSelectedImage() }
                        imageAction("Copia", "doc.on.doc") { controller.copySelectedImage() }
                        imageAction("Incolla", "doc.on.clipboard", disabled: !controller.canPasteImage) { controller.pasteImage() }
                        imageAction("Ruota di 90°", "rotate.right") { controller.rotateSelectedImage() }
                        imageAction("Porta in primo piano", "square.3.layers.3d.top.filled") { controller.bringSelectedImageToFront() }
                        Menu {
                            Toggle(isOn: Binding(get: { controller.selectedImageRounded }, set: { controller.setSelectedImage(rounded: $0) })) {
                                Label("Angoli arrotondati", systemImage: "app")
                            }
                            Toggle(isOn: Binding(get: { controller.selectedImageShadow }, set: { controller.setSelectedImage(shadow: $0) })) {
                                Label("Ombra", systemImage: "shadow")
                            }
                        } label: {
                            Image(systemName: "paintbrush").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Aspetto")
                        imageAction("Elimina", "trash", tint: .red) { controller.deleteSelectedImage() }
                    }
                    .padding(.horizontal, 8)
                    .glassEffect(.regular, in: .capsule)
                } else {
                    HStack(spacing: 10) {
                        Label("Tocca un'immagine per selezionarla", systemImage: "hand.tap")
                            .font(.callout)
                            .padding(.leading, 16)
                        if controller.canPasteImage {
                            imageAction("Incolla", "doc.on.clipboard") { controller.pasteImage() }
                        }
                    }
                    .padding(.trailing, 6)
                    .frame(minHeight: 44)
                    .glassEffect(.regular, in: .capsule)
                }

                Button {
                    controller.finishImageEditing()
                } label: {
                    Text("Fine").font(.headline).padding(.horizontal, 8).frame(height: 30)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: controller.hasSelectedImage)
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            controller.refreshPasteAvailability()
        }
    }

    private func imageAction(_ title: String, _ systemImage: String, tint: Color = .primary, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary.opacity(0.5) : tint)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(title)
        .help(title)
    }

    private func close() {
        controller.close()
        dismiss()
    }
}

/// Ospita la tela UIKit dentro SwiftUI.
struct CanvasHost: UIViewRepresentable {
    let view: NoteCanvasView
    func makeUIView(context: Context) -> NoteCanvasView { view }
    func updateUIView(_ uiView: NoteCanvasView, context: Context) {}
}
