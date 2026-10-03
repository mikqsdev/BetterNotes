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
                            controller.addPage()
                        } label: {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 30, height: 34)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Aggiungi pagina")
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
                        if controller.isPaged && controller.pageCount > 1 {
                            Menu {
                                ForEach(1...controller.pageCount, id: \.self) { page in
                                    Button("Pagina \(page)") { controller.goToPage(page) }
                                }
                            } label: {
                                Label("Vai alla pagina", systemImage: "arrow.down.doc")
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
            HStack(spacing: 12) {
                Label(controller.hasSelectedImage ? "Trascina per spostare, usa gli angoli per ridimensionare" : "Tocca un'immagine per selezionarla",
                      systemImage: "hand.draw")
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)

                if controller.hasSelectedImage {
                    Button {
                        controller.bringSelectedImageToFront()
                    } label: {
                        Image(systemName: "square.3.layers.3d.top.filled").frame(width: 28, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Porta in primo piano")

                    Button(role: .destructive) {
                        controller.deleteSelectedImage()
                    } label: {
                        Image(systemName: "trash").frame(width: 28, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .tint(.red)
                    .accessibilityLabel("Elimina immagine")
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
