import PencilKit
import UIKit

struct CanvasState {
    var drawing: PKDrawing
    var images: [CanvasImage]
    /// Ordine delle pagine (vuoto per il foglio infinito): anche le operazioni sulle pagine sono annullabili.
    var pageSources: [Int]
}

/// PKCanvasView con l'undo nativo disattivato: BetterNotes gestisce una propria cronologia
/// (che include anche immagini e pagine).
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
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Bianco della carta e ombre delle pagine. È un unico layer vettoriale (non a tile), sempre presente:
/// mentre le tile di righe/quadretti/PDF vengono ridisegnate il foglio resta bianco, senza lampi scuri.
final class PaperBaseView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }
    private var shape: CAShapeLayer { layer as! CAShapeLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shape.fillColor = Theme.paperUI.cgColor
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOffset = CGSize(width: 0, height: 6)
        shape.shadowRadius = 11
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(for layout: PageLayout) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let path = CGMutablePath()
        if layout.isInfinite {
            path.addRect(CGRect(origin: .zero, size: layout.docSize))
            shape.shadowOpacity = 0
        } else {
            layout.pageRects.forEach { path.addRect($0) }
            shape.shadowOpacity = 0.13
        }
        shape.path = path
        shape.shadowPath = layout.isInfinite ? nil : path
    }
}

/// Delegate dei gesti separato (UIView ha già un metodo `gestureRecognizerShouldBegin`).
final class GestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: (UIGestureRecognizer) -> Bool = { _ in true }
    var simultaneous: (UIGestureRecognizer, UIGestureRecognizer) -> Bool = { _, _ in false }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        shouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        simultaneous(gestureRecognizer, other)
    }
}

@MainActor
final class NoteCanvasView: UIView, PKCanvasViewDelegate, UIPencilInteractionDelegate {
    weak var controller: EditorController?

    let canvas = BNCanvasView()
    let paperLayerView = ZoomLayerView()
    let imageLayerView = ZoomLayerView()
    let paperBaseView = PaperBaseView()
    let paperView = PaperView()
    let selectionView = ImageSelectionView()
    let gestureCoordinator = GestureCoordinator()

    var layout: PageLayout
    let pdf: PDFSource?

    // Immagini (vedi CanvasImages.swift)
    var images: [CanvasImage]
    var imageViews: [UUID: ImageItemView] = [:]
    var decodedImages: [UUID: UIImage] = [:]
    var selectedImageID: UUID?
    var isEditingImages = false
    var imageDragMode: ImageDragMode = .none
    var imageDragStart: CanvasImage?
    var imageDragStartAngle: CGFloat = 0
    var activeImageGestures = 0
    let imageTap = UITapGestureRecognizer()
    let imagePan = UIPanGestureRecognizer()
    let imagePinch = UIPinchGestureRecognizer()
    let imageRotation = UIRotationGestureRecognizer()
    let lassoImageTap = UITapGestureRecognizer()

    // Cronologia
    var lastState: CanvasState
    private var undoStack: [CanvasState] = []
    private var redoStack: [CanvasState] = []
    var isApplyingState = false
    private let maxHistory = 120
    /// Un singolo uso dello strumento (es. una passata di gomma pixel) può generare più
    /// notifiche di modifica: le raggruppiamo in un'unica voce di cronologia.
    private var toolSession = 0
    private var lastCommittedSession = -1
    /// Cresce a ogni modifica: serve a invalidare le anteprime delle pagine.
    private(set) var contentVersion = 0

    // Zoom
    private(set) var fitScale: CGFloat = 1
    private var isFittedToWidth = true
    private var lastWidth: CGFloat = 0
    private var didInitialScroll = false

    // Gesti e strumenti
    private let twoFingerTap = UITapGestureRecognizer()
    private let threeFingerTap = UITapGestureRecognizer()
    let inkGesture = InkInputGesture()
    private(set) lazy var inkEngine = LiveInkEngine(host: self)
    private(set) var settings = EditorSettings()
    private(set) var tool = ToolState()
    var isToolActive = false

    /// Il foglio infinito cresce a blocchi multipli di tutte le spaziature dei motivi
    /// (32, 36, 30 pt), così righe e quadretti restano allineati quando il contenuto viene traslato.
    static let infiniteChunk: CGFloat = 1440
    private var isExpandingCanvas = false

    var drawing: PKDrawing { canvas.drawing }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// L'inchiostro passa dal motore BetterNotes (stabilizzazione in tempo reale).
    /// PencilKit resta in carico di gomma, lazo e righello.
    var usesLiveInk: Bool { tool.kind.isInk && !settings.ruler && !isEditingImages }

    init(drawing: PKDrawing, images: [CanvasImage], layout: PageLayout, pdf: PDFSource?) {
        var drawing = drawing
        var images = images
        var layout = layout
        if layout.isInfinite {
            (drawing, images, layout) = Self.normalizeInfinite(drawing: drawing, images: images, layout: layout)
        }
        self.layout = layout
        self.pdf = pdf
        self.images = images
        self.lastState = CanvasState(drawing: drawing, images: images, pageSources: layout.pageSources)
        super.init(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        setup(drawing: drawing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// All'apertura ricentra il foglio infinito sul contenuto: lascia un margine attorno
    /// e scarta lo spazio vuoto accumulato navigando.
    private static func normalizeInfinite(drawing: PKDrawing, images: [CanvasImage], layout: PageLayout) -> (PKDrawing, [CanvasImage], PageLayout) {
        let content = contentBounds(drawing: drawing, images: images)
        guard !content.isNull else {
            return (drawing, images, layout.withGrownInfiniteSize(PageLayout.defaultInfiniteSize))
        }
        let chunk = infiniteChunk
        let dx = -floor((content.minX - chunk) / chunk) * chunk
        let dy = -floor((content.minY - chunk) / chunk) * chunk
        let movedDrawing = (dx == 0 && dy == 0) ? drawing : drawing.transformed(using: CGAffineTransform(translationX: dx, y: dy))
        let movedImages = images.map { image -> CanvasImage in
            var image = image
            image.frame = image.frame.offsetBy(dx: dx, dy: dy)
            return image
        }
        let moved = content.offsetBy(dx: dx, dy: dy)
        let size = CGSize(
            width: max(PageLayout.defaultInfiniteSize.width, ceil((moved.maxX + chunk) / chunk) * chunk),
            height: max(PageLayout.defaultInfiniteSize.height, ceil((moved.maxY + chunk) / chunk) * chunk)
        )
        return (movedDrawing, movedImages, layout.withGrownInfiniteSize(size))
    }

    static func contentBounds(drawing: PKDrawing, images: [CanvasImage]) -> CGRect {
        var content = drawing.strokes.isEmpty ? CGRect.null : drawing.bounds
        for image in images {
            content = content.isNull ? image.boundingBox : content.union(image.boundingBox)
        }
        return content
    }

    var contentBounds: CGRect { Self.contentBounds(drawing: canvas.drawing, images: images) }

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

        let docRect = CGRect(origin: .zero, size: layout.docSize)
        paperBaseView.frame = docRect
        paperBaseView.update(for: layout)
        paperView.frame = docRect
        paperView.tiledLayer.renderer = PaperRenderer(layout: layout, pdf: pdf)
        paperLayerView.isUserInteractionEnabled = false
        paperLayerView.addSubview(paperBaseView)
        paperLayerView.addSubview(paperView)

        imageLayerView.isUserInteractionEnabled = false
        selectionView.frame = docRect
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
            canvas.addGestureRecognizer(tap)
        }

        // Motore d'inchiostro.
        inkGesture.engine = inkEngine
        inkGesture.delegate = gestureCoordinator
        canvas.addGestureRecognizer(inkGesture)
        layer.addSublayer(inkEngine.previewContainer)

        setupImageGestures()

        gestureCoordinator.shouldBegin = { [weak self] gesture in
            self?.gestureShouldBegin(gesture) ?? true
        }
        gestureCoordinator.simultaneous = { [weak self] first, second in
            self?.gesturesRecognizeSimultaneously(first, second) ?? false
        }

        let pencilInteraction = UIPencilInteraction(delegate: self)
        canvas.addInteraction(pencilInteraction)
        updateInputMode()
    }

    private func gestureShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if gesture === inkGesture { return usesLiveInk }
        return imageGestureShouldBegin(gesture)
    }

    private func gesturesRecognizeSimultaneously(_ first: UIGestureRecognizer, _ second: UIGestureRecognizer) -> Bool {
        let taps: [UIGestureRecognizer] = [twoFingerTap, threeFingerTap, lassoImageTap]
        if taps.contains(where: { $0 === first || $0 === second }) { return true }
        // L'inchiostro convive con pan e pizzico: se arriva un secondo dito il tratto viene annullato
        // e la tela scorre/zooma normalmente.
        if first === inkGesture || second === inkGesture {
            let other = first === inkGesture ? second : first
            return other === canvas.panGestureRecognizer || other === canvas.pinchGestureRecognizer
        }
        let imageGestures: [UIGestureRecognizer] = [imagePinch, imageRotation]
        return imageGestures.contains(where: { $0 === first }) && imageGestures.contains(where: { $0 === second })
    }

    /// Chi riceve l'input: il motore BetterNotes (inchiostro) o PencilKit (gomma, lazo, righello).
    func updateInputMode() {
        let live = usesLiveInk
        inkGesture.isEnabled = live
        inkGesture.acceptsFinger = !settings.pencilOnly
        canvas.drawingGestureRecognizer.isEnabled = !live && !isEditingImages
        lassoImageTap.isEnabled = tool.kind == .lasso && !isEditingImages

        let pan = canvas.panGestureRecognizer
        pan.allowedTouchTypes = [UITouch.TouchType.direct, .indirect, .indirectPointer].map { NSNumber(value: $0.rawValue) }
        // Con "Favorisci Apple Pencil" le dita scorrono; altrimenti un dito scrive e due dita scorrono.
        pan.minimumNumberOfTouches = (settings.pencilOnly || isEditingImages) ? 1 : 2
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
        inkEngine.previewContainer.frame = bounds
        if !didInitialScroll {
            didInitialScroll = true
            if layout.isInfinite {
                scrollToContentStart()
                expandInfiniteCanvasIfNeeded()
            } else {
                scrollToTop(animated: false)
            }
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateInsets()
    }

    private func updateZoomLimits() {
        if layout.isInfinite {
            fitScale = 1
            canvas.minimumZoomScale = 0.25
            canvas.maximumZoomScale = 5
        } else {
            fitScale = min(bounds.width * 0.96 / layout.docSize.width, 1.35)
            canvas.minimumZoomScale = fitScale * 0.45
            canvas.maximumZoomScale = fitScale * 5
        }
    }

    /// Aggiorna geometria e trasformazioni dei layer della carta e delle immagini.
    /// Tocca le proprietà solo se cambiano davvero: reimpostarle (anche passando per valori intermedi)
    /// può far scartare le tile della carta, che poi ricompaiono "a griglia".
    func updateContentGeometry() {
        let zoom = canvas.zoomScale
        let size = layout.docSize
        let scaled = CGSize(width: size.width * zoom, height: size.height * zoom)
        if canvas.contentSize != scaled { canvas.contentSize = scaled }
        let docRect = CGRect(origin: .zero, size: size)
        let transform = CGAffineTransform(scaleX: zoom, y: zoom)
        let center = CGPoint(x: scaled.width / 2, y: scaled.height / 2)
        for view in [paperLayerView, imageLayerView] {
            if view.bounds != docRect { view.bounds = docRect }
            if view.transform != transform { view.transform = transform }
            if view.center != center { view.center = center }
        }
        if paperBaseView.frame != docRect { paperBaseView.frame = docRect }
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

    /// Foglio infinito: posiziona la vista sull'angolo in alto a sinistra del contenuto.
    private func scrollToContentStart() {
        let content = contentBounds
        let zoom = canvas.zoomScale
        let origin = content.isNull
            ? CGPoint(x: Self.infiniteChunk, y: Self.infiniteChunk)
            : CGPoint(x: content.minX - 60, y: content.minY - 60)
        canvas.contentOffset = CGPoint(x: origin.x * zoom - canvas.contentInset.left, y: origin.y * zoom - canvas.contentInset.top)
    }

    /// Inquadra tutto il contenuto della nota (utile per orientarsi nel foglio infinito).
    func showAllContent() {
        let content = contentBounds
        guard !content.isNull else {
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
                self.canvas.zoomScale = self.fitScale
                self.scrollToContentStart()
            }
            return
        }
        let target = content.insetBy(dx: -80, dy: -80)
        let availableWidth = canvas.bounds.width
        let availableHeight = canvas.bounds.height - canvas.contentInset.top - canvas.contentInset.bottom
        let zoom = min(max(min(availableWidth / target.width, availableHeight / target.height), canvas.minimumZoomScale), 1.5)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            self.canvas.zoomScale = zoom
            self.updateContentGeometry()
            self.canvas.contentOffset = CGPoint(
                x: target.midX * zoom - availableWidth / 2,
                y: target.midY * zoom - availableHeight / 2 - self.canvas.contentInset.top
            )
        } completion: { _ in
            self.expandInfiniteCanvasIfNeeded()
        }
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

    /// Converte un punto del documento in coordinate di questa vista (per l'anteprima dell'inchiostro).
    func screenPoint(fromDocument point: CGPoint) -> CGPoint {
        let zoom = canvas.zoomScale
        return CGPoint(x: point.x * zoom - canvas.contentOffset.x + canvas.frame.minX,
                       y: point.y * zoom - canvas.contentOffset.y + canvas.frame.minY)
    }

    // MARK: - Layout delle pagine

    /// Sostituisce il layout. `redrawPaper` ridisegna tutte le tile (serve quando le pagine cambiano ordine o stile).
    func setLayout(_ newLayout: PageLayout, redrawPaper: Bool, invalidating rects: [CGRect] = []) {
        layout = newLayout
        paperView.tiledLayer.renderer = PaperRenderer(layout: newLayout, pdf: pdf)
        paperBaseView.update(for: newLayout)
        updateZoomLimits()
        updateContentGeometry()
        if redrawPaper {
            paperView.setNeedsDisplay()
        } else {
            for rect in rects where !rect.isEmpty && !rect.isNull { paperView.setNeedsDisplay(rect) }
        }
        controller?.pageLayoutDidChange()
    }

    func changePaperStyle(to style: PaperStyle) {
        guard !layout.isInfinite, style != layout.style, layout.style != .pdf, !style.isInfinite else { return }
        setLayout(layout.withStyle(style, pdfPageSizes: pdf?.pageSizes), redrawPaper: true)
        contentVersion += 1
        controller?.contentDidChange()
    }

    /// Foglio davvero infinito: quando la vista (o il contenuto) si avvicina a un bordo, in qualsiasi
    /// direzione, il foglio si allarga. Se cresce a sinistra o in alto, contenuto e vista vengono traslati
    /// insieme, così l'utente non vede alcun salto.
    func expandInfiniteCanvasIfNeeded() {
        guard layout.isInfinite, !isToolActive, !isExpandingCanvas, !isApplyingState,
              !canvas.isZooming, canvas.bounds.width > 1 else { return }
        isExpandingCanvas = true
        defer { isExpandingCanvas = false }

        let zoom = canvas.zoomScale
        let visible = CGRect(
            x: canvas.contentOffset.x / zoom, y: canvas.contentOffset.y / zoom,
            width: canvas.bounds.width / zoom, height: canvas.bounds.height / zoom
        )
        var needed = visible.insetBy(dx: -visible.width * 0.75, dy: -visible.height * 0.75)
        let content = contentBounds
        if !content.isNull { needed = needed.union(content.insetBy(dx: -900, dy: -900)) }

        let chunk = Self.infiniteChunk
        func chunks(_ value: CGFloat) -> CGFloat { value <= 0 ? 0 : ceil(value / chunk) * chunk }
        let size = layout.docSize
        let left = chunks(-needed.minX)
        let top = chunks(-needed.minY)
        let right = chunks(needed.maxX - size.width)
        let bottom = chunks(needed.maxY - size.height)
        guard left + top + right + bottom > 0 else { return }

        if left > 0 || top > 0 { shiftContent(dx: left, dy: top) }
        let newSize = CGSize(width: size.width + left + right, height: size.height + top + bottom)
        let oldOffset = canvas.contentOffset
        layout = layout.withGrownInfiniteSize(newSize)
        paperView.tiledLayer.renderer = PaperRenderer(layout: layout, pdf: pdf)
        paperBaseView.update(for: layout)
        updateContentGeometry()
        if left > 0 || top > 0 {
            canvas.contentOffset = CGPoint(x: oldOffset.x + left * zoom, y: oldOffset.y + top * zoom)
        }
    }

    /// Trasla tratti, immagini e cronologia (per far crescere il foglio a sinistra o in alto).
    private func shiftContent(dx: CGFloat, dy: CGFloat) {
        let transform = CGAffineTransform(translationX: dx, y: dy)
        func shifted(_ images: [CanvasImage]) -> [CanvasImage] {
            images.map { image in
                var image = image
                image.frame = image.frame.offsetBy(dx: dx, dy: dy)
                return image
            }
        }
        func shifted(_ state: CanvasState) -> CanvasState {
            CanvasState(drawing: state.drawing.transformed(using: transform), images: shifted(state.images), pageSources: state.pageSources)
        }
        isApplyingState = true
        canvas.drawing = canvas.drawing.transformed(using: transform)
        isApplyingState = false
        images = shifted(images)
        syncImageViews()
        updateSelectionView()
        lastState = shifted(lastState)
        undoStack = undoStack.map(shifted)
        redoStack = redoStack.map(shifted)
    }

    // MARK: - Strumenti e impostazioni

    func apply(tool newTool: ToolState) {
        if tool.kind != newTool.kind { inkEngine.cancel() }
        tool = newTool
        canvas.tool = newTool.pkTool
        updateInputMode()
    }

    func apply(settings newSettings: EditorSettings) {
        settings = newSettings
        canvas.drawingPolicy = newSettings.pencilOnly ? .pencilOnly : .anyInput
        canvas.pinchGestureRecognizer?.isEnabled = !newSettings.lockZoom
        twoFingerTap.isEnabled = newSettings.twoFingerUndo
        threeFingerTap.isEnabled = newSettings.threeFingerRedo
        canvas.isRulerActive = newSettings.ruler
        updateInputMode()
    }

    // MARK: - Inchiostro (motore BetterNotes)

    func liveInkDidBegin() {
        isToolActive = true
        controller?.userDidBeginDrawing()
    }

    func liveInkDidCancel() {
        isToolActive = false
    }

    /// Aggiunge al disegno il tratto completato dal motore d'inchiostro.
    /// I tratti esistenti non vengono mai toccati: niente tratti che spariscono o ricompaiono.
    func commitLiveStroke(_ stroke: PKStroke) {
        isToolActive = false
        var drawing = canvas.drawing
        drawing.strokes.append(stroke)
        isApplyingState = true
        canvas.drawing = drawing
        isApplyingState = false
        toolSession += 1
        commit()
        lastCommittedSession = toolSession
        expandInfiniteCanvasIfNeeded()
    }

    // MARK: - PKCanvasViewDelegate (gomma, lazo, righello)

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingState else { return }
        guard canvasView.drawing != lastState.drawing else { return }
        if lastCommittedSession == toolSession {
            // Stesso gesto (o aggiornamento tardivo della Pencil): nessuna nuova voce di cronologia.
            lastState = currentState
            contentVersion += 1
            controller?.contentDidChange()
        } else {
            commit()
            lastCommittedSession = toolSession
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        toolSession += 1
        isToolActive = true
        controller?.userDidBeginDrawing()
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isToolActive = false
        if tool.kind == .eraser && tool.returnToPen {
            controller?.returnToInk()
        }
        DispatchQueue.main.async { [weak self] in self?.expandInfiniteCanvasIfNeeded() }
    }

    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        inkEngine.canvasDidFinishRendering()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentGeometry()
        isFittedToWidth = abs(canvas.zoomScale - fitScale) < 0.01
        reportViewport()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        expandInfiniteCanvasIfNeeded()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        inkEngine.canvasDidScroll()
        expandInfiniteCanvasIfNeeded()
        reportViewport()
    }

    // MARK: - Cronologia (undo / redo)

    var currentState: CanvasState { CanvasState(drawing: canvas.drawing, images: images, pageSources: layout.pageSources) }

    func commit() {
        undoStack.append(lastState)
        if undoStack.count > maxHistory { undoStack.removeFirst(undoStack.count - maxHistory) }
        redoStack.removeAll()
        lastState = currentState
        contentVersion += 1
        controller?.historyDidChange()
        controller?.contentDidChange()
    }

    func undo() {
        cancelActiveStroke()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentState)
        restore(previous)
    }

    func redo() {
        cancelActiveStroke()
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
        if !layout.isInfinite, state.pageSources != layout.pageSources {
            setLayout(PageLayout.make(style: layout.style, pageSources: state.pageSources, pdfPageSizes: pdf?.pageSizes, infiniteSize: .zero), redrawPaper: true)
        }
        if let selected = selectedImageID, !images.contains(where: { $0.id == selected }) {
            selectImage(nil)
        } else {
            updateSelectionView()
        }
        lastState = state
        contentVersion += 1
        controller?.historyDidChange()
        controller?.contentDidChange()
    }

    /// Interrompe il tratto eventualmente in corso (es. il primo dito di un tap a due dita).
    private func cancelActiveStroke() {
        inkEngine.cancel()
        if !isEditingImages, canvas.drawingGestureRecognizer.isEnabled {
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = true
        }
        isToolActive = false
    }

    @objc private func handleTwoFingerTap() {
        guard settings.twoFingerUndo, canUndo else { return }
        cancelActiveStroke()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.canUndo else { return }
            self.undo()
            self.controller?.showToast("Annullato", systemImage: "arrow.uturn.backward")
        }
    }

    @objc private func handleThreeFingerTap() {
        guard settings.threeFingerRedo, canRedo else { return }
        cancelActiveStroke()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.canRedo else { return }
            self.redo()
            self.controller?.showToast("Ripristinato", systemImage: "arrow.uturn.forward")
        }
    }

    // MARK: - Apple Pencil

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        controller?.handlePencilDoubleTap()
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if squeeze.phase == .ended { controller?.togglePalette() }
    }
}
