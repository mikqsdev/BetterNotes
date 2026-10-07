import PhotosUI
import SwiftUI

/// Bordo a cui è agganciato il pannello strumenti.
enum PaletteDock: String {
    case free, left, right, top, bottom
    var isVertical: Bool { self == .left || self == .right }
}

/// Pannello strumenti fluttuante: si espande con un morphing Liquid Glass, si trascina con inerzia,
/// ruota leggermente nella direzione del trascinamento (facendo perno sotto il dito) e si aggancia ai bordi.
struct FloatingToolPalette: View {
    @Bindable var controller: EditorController
    let bounds: CGSize

    @AppStorage(SettingsKey.paletteX) private var storedX: Double = -1
    @AppStorage(SettingsKey.paletteY) private var storedY: Double = -1
    @AppStorage(SettingsKey.paletteDock) private var dockRaw = PaletteDock.bottom.rawValue
    @AppStorage(SettingsKey.paletteSnapToEdges) private var snapToEdges = true

    /// Posizione della barra compatta.
    @State private var anchor: CGPoint = .zero
    /// Posizione del menu espanso, solo se l'utente lo ha spostato: altrimenti, alla chiusura,
    /// la barra torna esattamente dov'era.
    @State private var expandedAnchor: CGPoint?
    @State private var didPlace = false
    @State private var drag: CGSize = .zero
    @State private var isDragging = false
    @State private var tilt: Double = 0
    /// Punto del pannello sotto il dito: fa da perno per la rotazione, così il pannello non "scappa" dal dito.
    @State private var grabAnchor: UnitPoint = .center
    @State private var panelFrame: CGRect = .zero
    /// Ultime dimensioni misurate della barra compatta in orizzontale (servono anche a menu aperto).
    @State private var collapsedHorizontalSize = CGSize(width: 290, height: 56)
    @State private var snapFeedback = 0
    @State private var photoItem: PhotosPickerItem?
    @Namespace private var glassNamespace

    private let margin: CGFloat = 14
    private let topReserve: CGFloat = 66

    private var dock: PaletteDock { PaletteDock(rawValue: dockRaw) ?? .bottom }
    private var isVertical: Bool { snapToEdges && dock.isVertical && !controller.isPaletteExpanded }

    var body: some View {
        GlassEffectContainer(spacing: 30) {
            Group {
                if controller.isPaletteExpanded {
                    // Intestazione e riga strumenti hanno priorità sul trascinamento (anche partendo da un tasto);
                    // il resto della scheda lascia la precedenza a slider e selettori.
                    ExpandedToolCard(controller: controller, photoItem: $photoItem, dragGesture: dragGesture)
                        .gesture(dragGesture)
                        .rotationEffect(.degrees(tilt), anchor: grabAnchor)
                        // Liquid Glass non ruota la vista: si ruota la *forma* del vetro, così il pannello
                        // mantiene il suo aspetto (e il suo adattamento ai colori) anche durante il trascinamento.
                        .glassEffect(
                            .regular.tint(Theme.elevated.opacity(0.35)),
                            in: RoundedRectangle(cornerRadius: 30, style: .continuous).rotation(.degrees(tilt), anchor: grabAnchor)
                        )
                        .glassEffectID("palette", in: glassNamespace)
                } else {
                    CollapsedToolBar(controller: controller, vertical: isVertical)
                        // Tutta la barra (anche lo spazio tra i tasti) è trascinabile.
                        .contentShape(Capsule())
                        .highPriorityGesture(dragGesture)
                        .rotationEffect(.degrees(tilt), anchor: grabAnchor)
                        .glassEffect(.regular, in: Capsule().rotation(.degrees(tilt), anchor: grabAnchor))
                        .glassEffectID("palette", in: glassNamespace)
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            panelFrame = frame
            if !controller.isPaletteExpanded, frame.width > 0, !isDragging {
                collapsedHorizontalSize = isVertical ? CGSize(width: frame.height, height: frame.width) : frame.size
            }
        }
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0.12), radius: 14, y: 6)
        .position(displayPosition)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: panelFrame.size)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: controller.isPaletteExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: controller.tool.kind)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: snapFeedback)
        .onAppear(perform: placeInitially)
        .onChange(of: bounds) { _, _ in placeFromStorage() }
        .onChange(of: controller.isPaletteExpanded) { _, expanded in
            guard !expanded, let moved = expandedAnchor else {
                expandedAnchor = nil
                return
            }
            // Il menu è stato spostato: la barra si chiude dove si trova il menu (agganciandosi a un bordo).
            expandedAnchor = nil
            let (target, newDock) = snapTarget(for: moved, size: collapsedSize(vertical: false))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                anchor = target
                dockRaw = newDock.rawValue
            }
            persist(target)
        }
        .onChange(of: snapToEdges) { _, _ in
            let (target, newDock) = snapTarget(for: anchor, size: collapsedSize(vertical: false))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                anchor = target
                dockRaw = newDock.rawValue
            }
            persist(target)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    controller.insertImage(data: data)
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Geometria

    private var panelSize: CGSize {
        panelFrame.size == .zero ? CGSize(width: 280, height: 60) : panelFrame.size
    }

    /// Dimensioni della barra compatta nell'orientamento richiesto (verticale = ruotata di 90°).
    private func collapsedSize(vertical: Bool) -> CGSize {
        let horizontal = collapsedHorizontalSize
        return vertical ? CGSize(width: horizontal.height, height: horizontal.width) : horizontal
    }

    private func allowedRect(for size: CGSize) -> CGRect {
        let halfW = size.width / 2, halfH = size.height / 2
        let minX = margin + halfW
        let maxX = max(minX, bounds.width - margin - halfW)
        let minY = topReserve + halfH
        let maxY = max(minY, bounds.height - margin - halfH)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func clamp(_ point: CGPoint, size: CGSize) -> CGPoint {
        let r = allowedRect(for: size)
        return CGPoint(x: min(max(point.x, r.minX), r.maxX), y: min(max(point.y, r.minY), r.maxY))
    }

    /// Resistenza elastica oltre i bordi (come lo scroll di iOS).
    private func rubberBand(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        let dimension: CGFloat = 160
        func band(_ distance: CGFloat) -> CGFloat { (1 - 1 / (distance * 0.55 / dimension + 1)) * dimension }
        if value < lower { return lower - band(lower - value) }
        if value > upper { return upper + band(value - upper) }
        return value
    }

    /// Posizione a riposo: il menu espanso viene spinto dentro lo schermo senza modificare la posizione della barra.
    private var restingPosition: CGPoint {
        if controller.isPaletteExpanded { return clamp(expandedAnchor ?? anchor, size: panelSize) }
        return clamp(anchor, size: panelSize)
    }

    private var displayPosition: CGPoint {
        let base = restingPosition
        guard isDragging else { return base }
        let raw = CGPoint(x: base.x + drag.width, y: base.y + drag.height)
        let r = allowedRect(for: panelSize)
        return CGPoint(x: rubberBand(raw.x, r.minX, r.maxX), y: rubberBand(raw.y, r.minY, r.maxY))
    }

    /// Destinazione dopo il rilascio: il bordo più vicino (se l'aggancio ai bordi è attivo) o una posizione libera.
    private func snapTarget(for point: CGPoint, size horizontalSize: CGSize) -> (CGPoint, PaletteDock) {
        let verticalSize = CGSize(width: horizontalSize.height, height: horizontalSize.width)
        guard snapToEdges else {
            let r = allowedRect(for: horizontalSize)
            var target = clamp(point, size: horizontalSize)
            let magnet: CGFloat = 70
            if target.x - r.minX < magnet { target.x = r.minX }
            else if r.maxX - target.x < magnet { target.x = r.maxX }
            else if abs(target.x - r.midX) < 46 { target.x = r.midX }
            if r.maxY - target.y < magnet { target.y = r.maxY }
            else if target.y - r.minY < magnet * 0.6 { target.y = r.minY }
            return (target, .free)
        }
        let distances: [(PaletteDock, CGFloat)] = [
            (.left, point.x),
            (.right, bounds.width - point.x),
            (.bottom, bounds.height - point.y),
            (.top, point.y - topReserve),
        ]
        let edge = distances.min { $0.1 < $1.1 }?.0 ?? .bottom
        let size = edge.isVertical ? verticalSize : horizontalSize
        let r = allowedRect(for: size)
        var target = clamp(point, size: size)
        switch edge {
        case .left: target.x = r.minX
        case .right: target.x = r.maxX
        case .top: target.y = r.minY
        default: target.y = r.maxY
        }
        if edge.isVertical, abs(target.y - r.midY) < 50 { target.y = r.midY }
        if !edge.isVertical, abs(target.x - r.midX) < 50 { target.x = r.midX }
        return (target, edge)
    }

    // MARK: - Trascinamento

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    if panelFrame.width > 0, panelFrame.height > 0 {
                        grabAnchor = UnitPoint(
                            x: min(1, max(0, (value.startLocation.x - panelFrame.minX) / panelFrame.width)),
                            y: min(1, max(0, (value.startLocation.y - panelFrame.minY) / panelFrame.height))
                        )
                    }
                    isDragging = true
                }
                drag = value.translation
                // Leggera rotazione nella direzione del movimento (solo rotazione, nessun ingrandimento).
                let velocity = isVertical ? -value.velocity.height : value.velocity.width
                let targetTilt = max(-7, min(7, Double(velocity) / 170))
                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.65)) { tilt = targetTilt }
            }
            .onEnded { value in
                let start = restingPosition
                // Inerzia: proietta la posizione finale secondo la velocità del lancio.
                let projected = CGPoint(
                    x: start.x + value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.85,
                    y: start.y + value.translation.height + (value.predictedEndTranslation.height - value.translation.height) * 0.85
                )
                let speed = hypot(value.velocity.width, value.velocity.height)
                let spring = Animation.interpolatingSpring(mass: 1, stiffness: 190, damping: speed > 1400 ? 16 : 21)
                if controller.isPaletteExpanded {
                    let target = clamp(projected, size: panelSize)
                    withAnimation(spring) {
                        expandedAnchor = target
                        drag = .zero
                        tilt = 0
                        isDragging = false
                    }
                } else {
                    let (target, newDock) = snapTarget(for: projected, size: collapsedSize(vertical: false))
                    withAnimation(spring) {
                        anchor = target
                        dockRaw = newDock.rawValue
                        drag = .zero
                        tilt = 0
                        isDragging = false
                    }
                    persist(target)
                }
                snapFeedback += 1
            }
    }

    // MARK: - Posizione salvata

    private func placeInitially() {
        guard !didPlace, bounds.width > 0 else { return }
        didPlace = true
        placeFromStorage()
    }

    private func placeFromStorage() {
        guard bounds.width > 0 else { return }
        let stored = (storedX >= 0 && storedY >= 0)
            ? CGPoint(x: storedX * bounds.width, y: storedY * bounds.height)
            : CGPoint(x: bounds.width / 2, y: bounds.height)
        if snapToEdges {
            anchor = snapTarget(for: stored, size: collapsedSize(vertical: false)).0
        } else {
            anchor = clamp(stored, size: collapsedSize(vertical: false))
        }
    }

    private func persist(_ point: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        storedX = point.x / bounds.width
        storedY = point.y / bounds.height
    }
}

// MARK: - Barra compatta

private struct CollapsedToolBar: View {
    @Bindable var controller: EditorController
    let vertical: Bool

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            Button { controller.tapPencil() } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: controller.tool.kind.isInk ? controller.tool.kind.systemImage : controller.tool.lastInkKind.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(Color(uiColor: UIColor(hexString: controller.tool.kind == .marker ? controller.tool.markerColorHex : controller.tool.colorHex) ?? .black))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .offset(x: -6, y: -7)
                }
            }
            .buttonStyle(PaletteIconStyle(isActive: controller.tool.kind.isInk && !controller.isEditingImages))
            .accessibilityLabel("Matita")

            Button { controller.tapEraser() } label: {
                Image(systemName: controller.tool.eraserMode == .pixel ? "eraser.fill" : "eraser.line.dashed.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PaletteIconStyle(isActive: controller.tool.kind == .eraser))
            .accessibilityLabel("Gomma")

            Button { controller.select(.lasso) } label: {
                Image(systemName: "lasso")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PaletteIconStyle(isActive: controller.tool.kind == .lasso))
            .accessibilityLabel("Lazo")

            Capsule().fill(.primary.opacity(0.15))
                .frame(width: vertical ? 24 : 1, height: vertical ? 1 : 24)
                .padding(vertical ? .vertical : .horizontal, 4)

            Button { controller.undo() } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 17, weight: .semibold))
                    .frame(width: vertical ? 44 : 40, height: vertical ? 40 : 44)
            }
            .buttonStyle(PaletteIconStyle(isActive: false))
            .disabled(!controller.canUndo)
            .keyboardShortcut("z", modifiers: .command)

            Button { controller.redo() } label: {
                Image(systemName: "arrow.uturn.forward").font(.system(size: 17, weight: .semibold))
                    .frame(width: vertical ? 44 : 40, height: vertical ? 40 : 44)
            }
            .buttonStyle(PaletteIconStyle(isActive: false))
            .disabled(!controller.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .padding(.horizontal, vertical ? 6 : 8)
        .padding(.vertical, vertical ? 8 : 6)
    }
}

private struct PaletteIconStyle: ButtonStyle {
    var isActive: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Color.white : Color.primary.opacity(isEnabled ? 0.85 : 0.3))
            .background {
                if isActive {
                    Circle().fill(Theme.accent.gradient).padding(2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - Sottomenu espanso

private struct ExpandedToolCard<DragG: Gesture>: View {
    @Bindable var controller: EditorController
    @Binding var photoItem: PhotosPickerItem?
    let dragGesture: DragG

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                header
                toolSelector
            }
            .contentShape(.rect)
            .highPriorityGesture(dragGesture)
            Divider().opacity(0.5)
            Group {
                switch controller.tool.kind {
                case .eraser: EraserSection(controller: controller)
                case .lasso: LassoSection(controller: controller)
                default: InkSection(controller: controller)
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        }
        .padding(20)
        .frame(width: 368)
        .contentShape(.rect)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.primary.opacity(0.22))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
            HStack {
                Text(controller.tool.kind.isInk ? "Matita" : controller.tool.kind.title)
                    .font(.serif(.title3, weight: .semibold))
                    .contentTransition(.opacity)
                Spacer()
                Button { controller.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!controller.canUndo)
                Button { controller.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!controller.canRedo)
                Button {
                    controller.isPaletteExpanded = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.primary.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Chiudi strumenti")
            }
            .buttonStyle(.plain)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
        }
    }

    private var toolSelector: some View {
        HStack(spacing: 2) {
            ForEach(ToolKind.inkKinds) { kind in
                toolButton(kind)
            }
            Capsule().fill(.primary.opacity(0.15)).frame(width: 1, height: 26).padding(.horizontal, 3)
            toolButton(.eraser)
            toolButton(.lasso)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 40)
            }
            .buttonStyle(PaletteIconStyle(isActive: false))
            .accessibilityLabel("Aggiungi immagine dalla galleria")
        }
    }

    private func toolButton(_ kind: ToolKind) -> some View {
        Button {
            controller.select(kind)
        } label: {
            Image(systemName: kind.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 40)
        }
        .buttonStyle(PaletteIconStyle(isActive: controller.tool.kind == kind))
        .accessibilityLabel(kind.title)
    }
}

private struct InkSection: View {
    @Bindable var controller: EditorController

    private var currentColor: Binding<Color> {
        Binding(
            get: { Color(uiColor: controller.tool.uiColor) },
            set: { controller.setColor(UIColor($0).hexString) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StrokePreview(tool: controller.tool)
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.06)))

            SectionLabel("Colore")
            let colors = ToolState.palette + controller.tool.recentColors
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10), count: 8), alignment: .leading, spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    ColorSwatch(hex: hex, isSelected: controller.tool.activeColorHex == hex) {
                        controller.setColor(hex)
                    }
                }
                ColorPicker("Colore personalizzato", selection: currentColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 34, height: 34)
            }

            ToolSlider(title: "Spessore", systemImage: "lineweight", value: $controller.tool.width, range: 0.02...1) {
                String(format: "%.1f pt", controller.tool.inkWidth)
            }
            ToolSlider(title: "Intensità", systemImage: "circle.lefthalf.filled", value: $controller.tool.opacity, range: 0.1...1) {
                "\(Int((controller.tool.opacity * 100).rounded()))%"
            }
            ToolSlider(title: "Stabilizzazione", systemImage: "scribble.variable", value: $controller.tool.stabilization, range: 0...1) {
                controller.tool.stabilization < 0.02 ? "Off" : "\(Int((controller.tool.stabilization * 100).rounded()))%"
            }
        }
    }
}

private struct EraserSection: View {
    @Bindable var controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Tipo di gomma")
            Picker("Tipo di gomma", selection: $controller.tool.eraserMode) {
                ForEach(EraserMode.allCases) { mode in
                    Text(mode == .pixel ? "Gomma pixel" : "Gomma tradizionale").tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(controller.tool.eraserMode.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ToolSlider(title: "Intensità gomma", systemImage: "circle.dashed", value: $controller.tool.eraserWidth, range: 0...1) {
                "\(Int(controller.tool.eraserPointWidth)) pt"
            }

            Toggle(isOn: $controller.tool.returnToPen) {
                Label("Torna alla penna dopo l'uso", systemImage: "arrow.uturn.left.circle")
            }
            .tint(Theme.accent)
        }
    }
}

private struct LassoSection: View {
    @Bindable var controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Cerchia i tratti per selezionarli, poi trascinali per spostarli. Tocca la selezione per copiare, duplicare o eliminare. Tocca un'immagine per spostarla, ruotarla o modificarne l'aspetto.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lasso.badge.sparkles")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button {
                controller.startImageEditing()
            } label: {
                Label("Modifica immagini", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }
}

// MARK: - Componenti

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

private struct ColorSwatch: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(uiColor: UIColor(hexString: hex) ?? .black))
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                .padding(isSelected ? 5 : 1)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color(uiColor: UIColor(hexString: hex) ?? .black), lineWidth: 2.5)
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isSelected)
        .accessibilityLabel("Colore \(hex)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ToolSlider: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueLabel: () -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(valueLabel())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Slider(value: $value, in: range)
                .tint(Theme.accent)
        }
    }
}

/// Anteprima dal vivo del tratto con colore, spessore e intensità correnti.
private struct StrokePreview: View {
    let tool: ToolState

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let midY = size.height / 2
            let start = CGPoint(x: 22, y: midY + 6)
            path.move(to: start)
            path.addCurve(
                to: CGPoint(x: size.width - 22, y: midY - 4),
                control1: CGPoint(x: size.width * 0.33, y: midY - 22),
                control2: CGPoint(x: size.width * 0.62, y: midY + 26)
            )
            let width = min(tool.inkWidth, size.height - 10)
            var color = Color(uiColor: tool.uiColor).opacity(tool.opacity)
            if tool.kind == .marker { color = color.opacity(0.55) }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(1, width), lineCap: tool.kind == .marker ? .square : .round, lineJoin: .round))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: tool)
        .accessibilityHidden(true)
    }
}
