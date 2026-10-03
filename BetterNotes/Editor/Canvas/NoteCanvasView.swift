import PencilKit
import UIKit

struct CanvasImage: Identifiable {
    let id: UUID
    var frame: CGRect
    let data: Data
}

struct CanvasState {
    var drawing: PKDrawing
    var images: [CanvasImage]
}

/// PKCanvasView con l'undo nativo disattivato: BetterNotes gestisce una propria cronologia
/// (che include anche le immagini e la stabilizzazione del tratto).
final class BNCanvasView: PKCanvasView {
    private let silentUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.disableUndoRegistration()
        return manager
    }()

    override var undoManager: UndoManager? { silentUndoManager }
}

/// Vista in coordinate documento, scalata insieme allo zoom della tela.
final class ZoomLayerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Bordo tratteggiato e maniglie dell'immagine selezionata.
final class ImageSelectionView: UIView {
    private let border = CAShapeLayer()
    private let handles: [CAShapeLayer] = (0..<4).map { _ in CAShapeLayer() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let accent = UIColor(named: "AccentColor") ?? .systemOrange
        border.fillColor = nil
        border.strokeColor = accent.cgColor
        layer.addSublayer(border)
        for handle in handles {
            handle.fillColor = UIColor.white.cgColor
            handle.strokeColor = accent.cgColor
            layer.addSublayer(handle)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(frame selection: CGRect?, zoom: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let selection else {
            border.path = nil
            handles.forEach { $0.path = nil }
            return
        }
        let z = max(zoom, 0.05)
        border.lineWidth = 2 / z
        border.lineDashPattern = [NSNumber(value: Double(7 / z)), NSNumber(value: Double(5 / z))]
        border.path = UIBezierPath(rect: selection).cgPath
        let radius = 9 / z
        let corners = [
            CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY),
            CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY),
        ]
        for (handle, corner) in zip(handles, corners) {
            handle.lineWidth = 2.5 / z
            handle.path = UIBezierPath(ovalIn: CGRect(x: corner.x - radius, y: corner.y - radius, width: radius * 2, height: radius * 2)).cgPath
        }
    }
}

/// Delegate dei gesti separato (UIView ha già un metodo `gestureRecognizerShouldBegin`).
private final class GestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: (UIGestureRecognizer) -> Bool = { _ in true }
    var simultaneous: Set<ObjectIdentifier> = []

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        shouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        simultaneous.contains(ObjectIdentifier(gestureRecognizer))
    }
}

@MainActor
final class NoteCanvasView: UIView, PKCanvasViewDelegate, UIPencilInteractionDelegate {
    weak var controller: EditorController?

    let canvas = BNCanvasView()
    private let paperLayerView = ZoomLayerView()
    private let imageLayerView = ZoomLayerView()
    private let paperView = PaperView()
    private let selectionView = ImageSelectionView()
    private let gestureCoordinator = GestureCoordinator()

    private(set) var layout: PageLayout
    let pdf: PDFSource?

    private(set) var images: [CanvasImage]
    private var imageViews: [UUID: UIImageView] = [:]
    private var decodedImages: [UUID: UIImage] = [:]

    private var lastState: CanvasState
    private var undoStack: [CanvasState] = []
    private var redoStack: [CanvasState] = []
    private var isApplyingState = false
    private let maxHistory = 120
    /// Un singolo uso dello strumento (es. una passata di gomma pixel) può generare più
    /// notifiche di modifica: le raggruppiamo in un'unica voce di cronologia.
    private var toolSession = 0
    private var lastCommittedSession = -1

    private(set) var fitScale: CGFloat = 1
    private var isFittedToWidth = true
    private var lastWidth: CGFloat = 0
    private var didInitialScroll = false

    private let twoFingerTap = UITapGestureRecognizer()
    private let threeFingerTap = UITapGestureRecognizer()
    private let imageTap = UITapGestureRecognizer()
    private let imagePan = UIPanGestureRecognizer()
    private let imagePinch = UIPinchGestureRecognizer()

    private var settings = EditorSettings()
    private var tool = ToolState()
    private(set) var isEditingImages = false
    private(set) var selectedImageID: UUID?

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    private enum DragMode { case none, move, resize(Corner) }
    private var dragMode: DragMode = .none
    private var dragStartFrame: CGRect = .zero

    var drawing: PKDrawing { canvas.drawing }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(drawing: PKDrawing, images: [CanvasImage], layout: PageLayout, pdf: PDFSource?) {
        self.layout = layout
        self.pdf = pdf
        self.images = images
        self.lastState = CanvasState(drawing: drawing, images: images)
        super.init(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        setup(drawing: drawing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    private func setup(drawing: PKDrawing) {
        backgroundColor = Theme.canvasSurroundUI

        canvas.frame = bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.delegate = self
        canvas.drawing = drawing
        // La carta è sempre bianca: niente inversione automatica dei colori dell'inchiostro.
        canvas.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.alwaysBounceHorizontal = layout.isInfinite
        canvas.showsHorizontalScrollIndicator = layout.isInfinite
        canvas.bouncesZoom = true
        addSubview(canvas)

        paperView.frame = CGRect(origin: .zero, size: layout.docSize)
        paperView.tiledLayer.renderer = PaperRenderer(layout: layout, pdf: pdf)
        paperLayerView.isUserInteractionEnabled = false
        paperLayerView.addSubview(paperView)

        imageLayerView.isUserInteractionEnabled = false
        selectionView.frame = CGRect(origin: .zero, size: layout.docSize)
        imageLayerView.addSubview(selectionView)

        canvas.insertSubview(paperLayerView, at: 0)
        canvas.insertSubview(imageLayerView, aboveSubview: paperLayerView)
        images.forEach(addImageView(for:))

        // Undo con due dita / redo con tre dita.
        let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.allowedTouchTypes = direct
        twoFingerTap.addTarget(self, action: #selector(handleTwoFingerTap))
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.allowedTouchTypes = direct
        threeFingerTap.addTarget(self, action: #selector(handleThreeFingerTap))
        for tap in [twoFingerTap, threeFingerTap] {
            tap.delegate = gestureCoordinator
            gestureCoordinator.simultaneous.insert(ObjectIdentifier(tap))
            canvas.addGestureRecognizer(tap)
        }

        // Gesti per spostare/ridimensionare le immagini.
        imageTap.addTarget(self, action: #selector(handleImageTap(_:)))
        imagePan.addTarget(self, action: #selector(handleImagePan(_:)))
        imagePan.maximumNumberOfTouches = 1
        imagePinch.addTarget(self, action: #selector(handleImagePinch(_:)))
        for gesture in [imageTap, imagePan, imagePinch] as [UIGestureRecognizer] {
            gesture.delegate = gestureCoordinator
            imageLayerView.addGestureRecognizer(gesture)
        }
        canvas.panGestureRecognizer.require(toFail: imagePan)
        canvas.pinchGestureRecognizer?.require(toFail: imagePinch)

        gestureCoordinator.shouldBegin = { [weak self] gesture in
            guard let self else { return true }
            return self.imageGestureShouldBegin(gesture)
        }

        let pencilInteraction = UIPencilInteraction(delegate: self)
        canvas.addInteraction(pencilInteraction)
    }

    // MARK: - Layout & zoom

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1 else { return }
        if abs(bounds.width - lastWidth) > 0.5 {
            let refit = isFittedToWidth || !didInitialScroll
            lastWidth = bounds.width
            updateZoomLimits()
            if refit { canvas.setZoomScale(fitScale, animated: false) }
        }
        updateContentGeometry()
        if !didInitialScroll {
            didInitialScroll = true
            scrollToTop(animated: false)
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateInsets()
    }

    private func updateZoomLimits() {
        if layout.isInfinite {
            fitScale = 1
            canvas.minimumZoomScale = max(0.2, min(1, bounds.width / layout.docSize.width))
            canvas.maximumZoomScale = 5
        } else {
            fitScale = min(bounds.width * 0.96 / layout.docSize.width, 1.35)
            canvas.minimumZoomScale = fitScale * 0.45
            canvas.maximumZoomScale = fitScale * 5
        }
    }

    private func updateContentGeometry() {
        let zoom = canvas.zoomScale
        let size = layout.docSize
        let scaled = CGSize(width: size.width * zoom, height: size.height * zoom)
        if canvas.contentSize != scaled { canvas.contentSize = scaled }
        for view in [paperLayerView, imageLayerView] {
            view.transform = .identity
            view.bounds = CGRect(origin: .zero, size: size)
            view.transform = CGAffineTransform(scaleX: zoom, y: zoom)
            view.center = CGPoint(x: scaled.width / 2, y: scaled.height / 2)
        }
        let docRect = CGRect(origin: .zero, size: size)
        if paperView.frame != docRect { paperView.frame = docRect }
        if selectionView.frame != docRect { selectionView.frame = docRect }
        updateSelectionView()
        updateInsets()
    }

    private func updateInsets() {
        let top = safeAreaInsets.top + 70
        let bottom = safeAreaInsets.bottom + 90
        let side = max(0, (canvas.bounds.width - canvas.contentSize.width) / 2)
        let extraV = max(0, (canvas.bounds.height - top - bottom - canvas.contentSize.height) / 2)
        let insets = UIEdgeInsets(top: top + extraV, left: side, bottom: bottom + extraV, right: side)
        if canvas.contentInset != insets { canvas.contentInset = insets }
    }

    func scrollToTop(animated: Bool) {
        canvas.setContentOffset(CGPoint(x: -canvas.contentInset.left, y: -canvas.contentInset.top), animated: animated)
    }

    func zoomToFit(animated: Bool) {
        canvas.setZoomScale(fitScale, animated: animated)
        isFittedToWidth = true
    }

    func scrollToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < layout.pageRects.count else { return }
        let zoom = canvas.zoomScale
        let target = layout.pageRects[index].minY * zoom - canvas.contentInset.top - 16 * zoom
        let maxY = max(-canvas.contentInset.top, canvas.contentSize.height - canvas.bounds.height + canvas.contentInset.bottom)
        canvas.setContentOffset(CGPoint(x: canvas.contentOffset.x, y: min(max(target, -canvas.contentInset.top), maxY)), animated: animated)
    }

    /// Porzione di documento visibile (coordinate tela).
    func visibleDocumentRect() -> CGRect {
        let zoom = canvas.zoomScale
        let rect = CGRect(
            x: canvas.contentOffset.x / zoom, y: canvas.contentOffset.y / zoom,
            width: canvas.bounds.width / zoom, height: canvas.bounds.height / zoom
        )
        let visible = rect.intersection(CGRect(origin: .zero, size: layout.docSize))
        return visible.isNull || visible.isEmpty ? CGRect(origin: .zero, size: layout.docSize) : visible
    }

    var currentPageIndex: Int {
        let zoom = canvas.zoomScale
        let centerY = (canvas.contentOffset.y + canvas.bounds.height / 2) / zoom
        return layout.pageIndex(nearY: centerY)
    }

    private func reportViewport() {
        let percent = Int((canvas.zoomScale / max(fitScale, 0.01) * 100).rounded())
        controller?.viewportDidChange(page: currentPageIndex + 1, zoomPercent: percent)
    }

    // MARK: - Pagine

    private func setLayout(_ newLayout: PageLayout, invalidating rects: [CGRect]) {
        layout = newLayout
        paperView.tiledLayer.renderer = PaperRenderer(layout: newLayout, pdf: pdf)
        updateZoomLimits()
        updateContentGeometry()
        for rect in rects where !rect.isEmpty && !rect.isNull {
            paperView.setNeedsDisplay(rect)
        }
    }

    func addPage() {
        guard !layout.isInfinite else { return }
        let newLayout = PageLayout.make(
            style: layout.style,
            pageCount: layout.pageCount + 1,
            pdfPageSizes: pdf?.pageSizes,
            infiniteSize: .zero
        )
        guard let newPage = newLayout.pageRects.last else { return }
        setLayout(newLayout, invalidating: [newPage.insetBy(dx: -40, dy: -40)])
        controller?.contentDidChange()
        DispatchQueue.main.async { [weak self] in
            self?.scrollToPage(newLayout.pageCount - 1, animated: true)
        }
    }

    private func growInfiniteCanvasIfNeeded() {
        guard layout.isInfinite else { return }
        var content = canvas.drawing.bounds
        for image in images {
            content = content.isNull ? image.frame : content.union(image.frame)
        }
        guard !content.isNull else { return }
        let old = layout.docSize
        var size = old
        let threshold: CGFloat = 600
        let growth: CGFloat = 1600
        if content.maxX > size.width - threshold { size.width = content.maxX + growth }
        if content.maxY > size.height - threshold { size.height = content.maxY + growth }
        guard size != old else { return }
        setLayout(layout.withGrownInfiniteSize(size), invalidating: [
            CGRect(x: old.width - 2, y: 0, width: size.width - old.width + 2, height: size.height),
            CGRect(x: 0, y: old.height - 2, width: size.width, height: size.height - old.height + 2),
        ])
    }

    // MARK: - Strumenti e impostazioni

    func apply(tool newTool: ToolState) {
        tool = newTool
        canvas.tool = newTool.pkTool
    }

    func apply(settings newSettings: EditorSettings) {
        settings = newSettings
        canvas.drawingPolicy = newSettings.pencilOnly ? .pencilOnly : .anyInput
        canvas.pinchGestureRecognizer?.isEnabled = !newSettings.lockZoom
        twoFingerTap.isEnabled = newSettings.twoFingerUndo
        threeFingerTap.isEnabled = newSettings.threeFingerRedo
        canvas.isRulerActive = newSettings.ruler
    }

    // MARK: - PKCanvasViewDelegate

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingState else { return }
        var drawing = canvasView.drawing
        guard drawing != lastState.drawing else { return }

        // Stabilizzazione: smussa il tratto appena tracciato.
        if tool.kind.isInk, tool.stabilization > 0.01,
           drawing.strokes.count == lastState.drawing.strokes.count + 1,
           let last = drawing.strokes.last {
            drawing.strokes[drawing.strokes.count - 1] = StrokeSmoother.smooth(last, amount: tool.stabilization)
            isApplyingState = true
            canvasView.drawing = drawing
            isApplyingState = false
        }
        growInfiniteCanvasIfNeeded()
        if lastCommittedSession == toolSession {
            // Stesso gesto: aggiorna lo stato senza aggiungere una nuova voce di undo.
            lastState = currentState
            controller?.contentDidChange()
        } else {
            commit()
            lastCommittedSession = toolSession
        }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        if tool.kind == .eraser && tool.returnToPen {
            controller?.returnToInk()
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        toolSession += 1
        controller?.userDidBeginDrawing()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentGeometry()
        isFittedToWidth = abs(canvas.zoomScale - fitScale) < 0.01
        reportViewport()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        reportViewport()
    }

    // MARK: - Cronologia (undo / redo)

    private var currentState: CanvasState { CanvasState(drawing: canvas.drawing, images: images) }

    private func commit() {
        undoStack.append(lastState)
        if undoStack.count > maxHistory { undoStack.removeFirst(undoStack.count - maxHistory) }
        redoStack.removeAll()
        lastState = currentState
        controller?.historyDidChange()
        controller?.contentDidChange()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentState)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentState)
        restore(next)
    }

    private func restore(_ state: CanvasState) {
        lastCommittedSession = -1
        isApplyingState = true
        canvas.drawing = state.drawing
        isApplyingState = false
        images = state.images
        syncImageViews()
        if let selected = selectedImageID, !images.contains(where: { $0.id == selected }) {
            selectImage(nil)
        } else {
            updateSelectionView()
        }
        lastState = state
        controller?.historyDidChange()
        controller?.contentDidChange()
    }

    @objc private func handleTwoFingerTap() {
        guard settings.twoFingerUndo, canUndo else { return }
        undo()
        controller?.showToast("Annullato", systemImage: "arrow.uturn.backward")
    }

    @objc private func handleThreeFingerTap() {
        guard settings.threeFingerRedo, canRedo else { return }
        redo()
        controller?.showToast("Ripristinato", systemImage: "arrow.uturn.forward")
    }

    // MARK: - Apple Pencil

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        controller?.handlePencilDoubleTap()
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if squeeze.phase == .ended { controller?.togglePalette() }
    }

    // MARK: - Immagini

    private func uiImage(for image: CanvasImage) -> UIImage? {
        if let cached = decodedImages[image.id] { return cached }
        let decoded = UIImage(data: image.data)
        decodedImages[image.id] = decoded
        return decoded
    }

    private func addImageView(for image: CanvasImage) {
        let view = UIImageView(image: uiImage(for: image))
        view.contentMode = .scaleToFill
        view.frame = image.frame
        view.layer.minificationFilter = .trilinear
        view.isUserInteractionEnabled = false
        imageLayerView.insertSubview(view, belowSubview: selectionView)
        imageViews[image.id] = view
    }

    private func syncImageViews() {
        let ids = Set(images.map(\.id))
        for (id, view) in imageViews where !ids.contains(id) {
            view.removeFromSuperview()
            imageViews[id] = nil
        }
        for image in images {
            if let view = imageViews[image.id] {
                view.frame = image.frame
                imageLayerView.insertSubview(view, belowSubview: selectionView)
            } else {
                addImageView(for: image)
            }
        }
    }

    func insertImage(data: Data, pixelSize: CGSize) {
        var target = visibleDocumentRect()
        if !layout.isInfinite, layout.pageRects.indices.contains(currentPageIndex) {
            let page = layout.pageRects[currentPageIndex]
            let clipped = target.intersection(page)
            target = clipped.isNull || clipped.isEmpty ? page : clipped
        }
        let maxSide = min(target.width, target.height) * 0.6
        let aspect = max(0.05, pixelSize.width / max(1, pixelSize.height))
        let size = aspect >= 1
            ? CGSize(width: maxSide, height: maxSide / aspect)
            : CGSize(width: maxSide * aspect, height: maxSide)
        let frame = CGRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2, width: size.width, height: size.height)
        let image = CanvasImage(id: UUID(), frame: frame, data: data)
        images.append(image)
        addImageView(for: image)
        growInfiniteCanvasIfNeeded()
        commit()
        setEditingImages(true)
        selectImage(image.id)
    }

    func setEditingImages(_ editing: Bool) {
        guard editing != isEditingImages else { return }
        isEditingImages = editing
        canvas.drawingGestureRecognizer.isEnabled = !editing
        imageLayerView.isUserInteractionEnabled = editing
        if editing {
            canvas.bringSubviewToFront(imageLayerView)
        } else {
            canvas.insertSubview(imageLayerView, aboveSubview: paperLayerView)
            selectImage(nil)
        }
        controller?.imageEditingDidChange(editing)
    }

    func selectImage(_ id: UUID?) {
        selectedImageID = id
        updateSelectionView()
        controller?.imageSelectionDidChange(id != nil)
    }

    func deleteSelectedImage() {
        guard let id = selectedImageID else { return }
        images.removeAll { $0.id == id }
        decodedImages[id] = nil
        syncImageViews()
        selectImage(nil)
        commit()
    }

    func bringSelectedImageToFront() {
        guard let id = selectedImageID, let index = images.firstIndex(where: { $0.id == id }) else { return }
        let image = images.remove(at: index)
        images.append(image)
        syncImageViews()
        commit()
    }

    private func updateSelectionView() {
        let frame = selectedImageID.flatMap { id in images.first(where: { $0.id == id })?.frame }
        selectionView.update(frame: isEditingImages ? frame : nil, zoom: canvas.zoomScale)
    }

    private func imageIndex(at point: CGPoint) -> Int? {
        images.lastIndex { $0.frame.contains(point) }
    }

    private func corner(at point: CGPoint) -> Corner? {
        guard let id = selectedImageID, let frame = images.first(where: { $0.id == id })?.frame else { return nil }
        let radius = 30 / canvas.zoomScale
        let candidates: [(Corner, CGPoint)] = [
            (.topLeft, CGPoint(x: frame.minX, y: frame.minY)), (.topRight, CGPoint(x: frame.maxX, y: frame.minY)),
            (.bottomLeft, CGPoint(x: frame.minX, y: frame.maxY)), (.bottomRight, CGPoint(x: frame.maxX, y: frame.maxY)),
        ]
        return candidates.first { hypot($0.1.x - point.x, $0.1.y - point.y) <= radius }?.0
    }

    private func imageGestureShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if gesture === imagePan {
            let point = gesture.location(in: imageLayerView)
            return corner(at: point) != nil || imageIndex(at: point) != nil
        }
        if gesture === imagePinch {
            guard let id = selectedImageID, let frame = images.first(where: { $0.id == id })?.frame else { return false }
            let slack = 60 / canvas.zoomScale
            return frame.insetBy(dx: -slack, dy: -slack).contains(gesture.location(in: imageLayerView))
        }
        return true
    }

    private func setFrame(_ frame: CGRect, forImage id: UUID) {
        guard let index = images.firstIndex(where: { $0.id == id }) else { return }
        images[index].frame = frame
        imageViews[id]?.frame = frame
        updateSelectionView()
    }

    @objc private func handleImageTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: imageLayerView)
        if let index = imageIndex(at: point) {
            selectImage(images[index].id)
        } else {
            selectImage(nil)
        }
    }

    @objc private func handleImagePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: imageLayerView)
        switch gesture.state {
        case .began:
            if let corner = corner(at: point) {
                dragMode = .resize(corner)
            } else if let index = imageIndex(at: point) {
                selectImage(images[index].id)
                dragMode = .move
            } else {
                dragMode = .none
            }
            if let id = selectedImageID, let frame = images.first(where: { $0.id == id })?.frame {
                dragStartFrame = frame
            }
        case .changed:
            guard let id = selectedImageID else { return }
            let t = gesture.translation(in: imageLayerView)
            switch dragMode {
            case .move:
                setFrame(dragStartFrame.offsetBy(dx: t.x, dy: t.y), forImage: id)
            case .resize(let corner):
                setFrame(resized(dragStartFrame, corner: corner, translation: t), forImage: id)
            case .none:
                break
            }
        case .ended, .cancelled:
            if case .none = dragMode { return }
            dragMode = .none
            growInfiniteCanvasIfNeeded()
            commit()
        default:
            break
        }
    }

    private func resized(_ start: CGRect, corner: Corner, translation t: CGPoint) -> CGRect {
        let aspect = start.width / max(start.height, 1)
        let minWidth: CGFloat = 40
        switch corner {
        case .bottomRight:
            let width = max(minWidth, start.width + t.x)
            return CGRect(x: start.minX, y: start.minY, width: width, height: width / aspect)
        case .bottomLeft:
            let width = max(minWidth, start.width - t.x)
            return CGRect(x: start.maxX - width, y: start.minY, width: width, height: width / aspect)
        case .topRight:
            let width = max(minWidth, start.width + t.x)
            let height = width / aspect
            return CGRect(x: start.minX, y: start.maxY - height, width: width, height: height)
        case .topLeft:
            let width = max(minWidth, start.width - t.x)
            let height = width / aspect
            return CGRect(x: start.maxX - width, y: start.maxY - height, width: width, height: height)
        }
    }

    @objc private func handleImagePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let id = selectedImageID else { return }
        switch gesture.state {
        case .began:
            dragStartFrame = images.first(where: { $0.id == id })?.frame ?? .zero
        case .changed:
            let scale = max(0.1, gesture.scale)
            let width = max(40, dragStartFrame.width * scale)
            let height = width * dragStartFrame.height / max(dragStartFrame.width, 1)
            setFrame(CGRect(x: dragStartFrame.midX - width / 2, y: dragStartFrame.midY - height / 2, width: width, height: height), forImage: id)
        case .ended, .cancelled:
            growInfiniteCanvasIfNeeded()
            commit()
        default:
            break
        }
    }
}
