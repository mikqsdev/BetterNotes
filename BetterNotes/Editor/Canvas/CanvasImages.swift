import UIKit

/// Immagine sulla tela. `frame` è il rettangolo *non ruotato*; la rotazione avviene attorno al centro.
struct CanvasImage: Identifiable {
    let id: UUID
    var frame: CGRect
    let data: Data
    var rotation: CGFloat = 0
    var rounded = false
    var shadow = false

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    var cornerRadius: CGFloat { rounded ? min(frame.width, frame.height) * 0.08 : 0 }

    /// Da coordinate documento a coordinate locali (origine al centro, assi dell'immagine).
    func localPoint(_ point: CGPoint) -> CGPoint {
        let dx = point.x - center.x, dy = point.y - center.y
        let c = cos(-rotation), s = sin(-rotation)
        return CGPoint(x: dx * c - dy * s, y: dx * s + dy * c)
    }

    func documentPoint(_ local: CGPoint) -> CGPoint {
        let c = cos(rotation), s = sin(rotation)
        return CGPoint(x: center.x + local.x * c - local.y * s, y: center.y + local.x * s + local.y * c)
    }

    func contains(_ point: CGPoint, slack: CGFloat = 0) -> Bool {
        let p = localPoint(point)
        return abs(p.x) <= frame.width / 2 + slack && abs(p.y) <= frame.height / 2 + slack
    }

    var corners: [CGPoint] {
        let w = frame.width / 2, h = frame.height / 2
        return [CGPoint(x: -w, y: -h), CGPoint(x: w, y: -h), CGPoint(x: w, y: h), CGPoint(x: -w, y: h)].map(documentPoint)
    }

    /// Rettangolo che contiene l'immagine ruotata.
    var boundingBox: CGRect {
        guard rotation != 0 else { return frame }
        let pts = corners
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    func withCenter(_ point: CGPoint) -> CanvasImage {
        var copy = self
        copy.frame = CGRect(x: point.x - frame.width / 2, y: point.y - frame.height / 2, width: frame.width, height: frame.height)
        return copy
    }
}

/// Vista di un'immagine: contenitore con ombra + immagine con angoli eventualmente arrotondati.
final class ImageItemView: UIView {
    private let imageView = UIImageView()

    init(image: UIImage?) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        imageView.image = image
        imageView.contentMode = .scaleToFill
        imageView.layer.masksToBounds = true
        imageView.layer.cornerCurve = .continuous
        imageView.layer.minificationFilter = .trilinear
        addSubview(imageView)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowRadius = 12
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ item: CanvasImage) {
        let size = item.frame.size
        bounds = CGRect(origin: .zero, size: size)
        center = item.center
        transform = CGAffineTransform(rotationAngle: item.rotation)
        imageView.frame = bounds
        imageView.layer.cornerRadius = item.cornerRadius
        layer.shadowOpacity = item.shadow ? 0.32 : 0
        layer.shadowPath = item.shadow ? UIBezierPath(roundedRect: bounds, cornerRadius: item.cornerRadius).cgPath : nil
    }
}

/// Bordo, maniglie di ridimensionamento e maniglia di rotazione dell'immagine selezionata.
final class ImageSelectionView: UIView {
    private let border = CAShapeLayer()
    private let handles: [CAShapeLayer] = (0..<4).map { _ in CAShapeLayer() }
    private let rotationStem = CAShapeLayer()
    private let rotationKnob = CAShapeLayer()

    static func rotationHandleDistance(zoom: CGFloat) -> CGFloat { 38 / max(zoom, 0.05) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let accent = UIColor(named: "AccentColor") ?? .systemOrange
        border.fillColor = nil
        border.strokeColor = accent.cgColor
        rotationStem.strokeColor = accent.cgColor
        rotationStem.fillColor = nil
        rotationKnob.fillColor = accent.cgColor
        rotationKnob.strokeColor = UIColor.white.cgColor
        [border, rotationStem, rotationKnob].forEach(layer.addSublayer)
        for handle in handles {
            handle.fillColor = UIColor.white.cgColor
            handle.strokeColor = accent.cgColor
            layer.addSublayer(handle)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(image: CanvasImage?, zoom: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let image else {
            ([border, rotationStem, rotationKnob] + handles).forEach { $0.path = nil }
            return
        }
        let z = max(zoom, 0.05)
        let corners = image.corners
        let outline = CGMutablePath()
        outline.addLines(between: corners + [corners[0]])
        border.lineWidth = 2 / z
        border.lineDashPattern = [NSNumber(value: Double(7 / z)), NSNumber(value: Double(5 / z))]
        border.path = outline

        let radius = 9 / z
        for (handle, corner) in zip(handles, corners) {
            handle.lineWidth = 2.5 / z
            handle.path = UIBezierPath(ovalIn: CGRect(x: corner.x - radius, y: corner.y - radius, width: radius * 2, height: radius * 2)).cgPath
        }

        let top = image.documentPoint(CGPoint(x: 0, y: -image.frame.height / 2))
        let knob = image.documentPoint(CGPoint(x: 0, y: -image.frame.height / 2 - Self.rotationHandleDistance(zoom: z)))
        let stem = CGMutablePath()
        stem.move(to: top)
        stem.addLine(to: knob)
        rotationStem.lineWidth = 2 / z
        rotationStem.path = stem
        let knobRadius = 10 / z
        rotationKnob.lineWidth = 2.5 / z
        rotationKnob.path = UIBezierPath(ovalIn: CGRect(x: knob.x - knobRadius, y: knob.y - knobRadius, width: knobRadius * 2, height: knobRadius * 2)).cgPath
    }
}

enum ImageDragMode {
    case none, move, rotate
    /// Angolo trascinato, come segni (±1, ±1) in coordinate locali.
    case resize(CGPoint)
}

/// Appunti interni: conservano anche l'aspetto dell'immagine copiata.
@MainActor
enum ImageClipboard {
    static var item: CanvasImage?
    static var changeCount = -1

    static var hasOwnItem: Bool { item != nil && changeCount == UIPasteboard.general.changeCount }
}

// MARK: - Immagini sulla tela

extension NoteCanvasView {
    func setupImageGestures() {
        imageTap.addTarget(self, action: #selector(handleImageTap(_:)))
        imagePan.addTarget(self, action: #selector(handleImagePan(_:)))
        imagePan.maximumNumberOfTouches = 1
        imagePinch.addTarget(self, action: #selector(handleImagePinch(_:)))
        imageRotation.addTarget(self, action: #selector(handleImageRotation(_:)))
        for gesture in [imageTap, imagePan, imagePinch, imageRotation] as [UIGestureRecognizer] {
            gesture.delegate = gestureCoordinator
            imageLayerView.addGestureRecognizer(gesture)
        }
        canvas.panGestureRecognizer.require(toFail: imagePan)
        canvas.pinchGestureRecognizer?.require(toFail: imagePinch)

        // Con il lazo, toccare un'immagine la seleziona.
        lassoImageTap.addTarget(self, action: #selector(handleLassoImageTap(_:)))
        lassoImageTap.delegate = gestureCoordinator
        canvas.addGestureRecognizer(lassoImageTap)
    }

    var selectedImage: CanvasImage? {
        selectedImageID.flatMap { id in images.first { $0.id == id } }
    }

    func uiImage(for image: CanvasImage) -> UIImage? {
        if let cached = decodedImages[image.id] { return cached }
        let decoded = UIImage(data: image.data)
        decodedImages[image.id] = decoded
        return decoded
    }

    func addImageView(for image: CanvasImage) {
        let view = ImageItemView(image: uiImage(for: image))
        view.apply(image)
        imageLayerView.insertSubview(view, belowSubview: selectionView)
        imageViews[image.id] = view
    }

    func syncImageViews() {
        let ids = Set(images.map(\.id))
        for (id, view) in imageViews where !ids.contains(id) {
            view.removeFromSuperview()
            imageViews[id] = nil
        }
        for image in images {
            if let view = imageViews[image.id] {
                view.apply(image)
                imageLayerView.insertSubview(view, belowSubview: selectionView)
            } else {
                addImageView(for: image)
            }
        }
    }

    /// Area in cui posizionare una nuova immagine: la parte visibile (della pagina corrente).
    private func insertionArea() -> CGRect {
        var target = visibleDocumentRect()
        if !layout.isInfinite, layout.pageRects.indices.contains(currentPageIndex) {
            let page = layout.pageRects[currentPageIndex]
            let clipped = target.intersection(page)
            target = clipped.isNull || clipped.isEmpty ? page : clipped
        }
        return target
    }

    func insertImage(data: Data, pixelSize: CGSize) {
        let target = insertionArea()
        let maxSide = min(target.width, target.height) * 0.6
        let aspect = max(0.05, pixelSize.width / max(1, pixelSize.height))
        let size = aspect >= 1
            ? CGSize(width: maxSide, height: maxSide / aspect)
            : CGSize(width: maxSide * aspect, height: maxSide)
        let frame = CGRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2, width: size.width, height: size.height)
        addNewImage(CanvasImage(id: UUID(), frame: frame, data: data))
    }

    private func addNewImage(_ image: CanvasImage) {
        images.append(image)
        addImageView(for: image)
        expandInfiniteCanvasIfNeeded()
        commit()
        setEditingImages(true)
        selectImage(image.id)
    }

    func setEditingImages(_ editing: Bool) {
        guard editing != isEditingImages else { return }
        inkEngine.cancel()
        isEditingImages = editing
        imageLayerView.isUserInteractionEnabled = editing
        if editing {
            canvas.bringSubviewToFront(imageLayerView)
        } else {
            canvas.insertSubview(imageLayerView, aboveSubview: paperLayerView)
            selectImage(nil)
        }
        updateInputMode()
        controller?.imageEditingDidChange(editing)
    }

    func selectImage(_ id: UUID?) {
        selectedImageID = id
        updateSelectionView()
        controller?.imageSelectionDidChange(selectedImage)
    }

    func updateSelectionView() {
        selectionView.update(image: isEditingImages ? selectedImage : nil, zoom: canvas.zoomScale)
    }

    private func replaceSelected(_ transform: (inout CanvasImage) -> Void, commitChange: Bool = true) {
        guard let id = selectedImageID, let index = images.firstIndex(where: { $0.id == id }) else { return }
        transform(&images[index])
        imageViews[id]?.apply(images[index])
        updateSelectionView()
        if commitChange {
            commit()
            controller?.imageSelectionDidChange(images[index])
        }
    }

    // MARK: Azioni

    func deleteSelectedImage() {
        guard let id = selectedImageID else { return }
        images.removeAll { $0.id == id }
        decodedImages[id] = nil
        syncImageViews()
        selectImage(nil)
        commit()
    }

    func duplicateSelectedImage() {
        guard let image = selectedImage else { return }
        let offset = 28 / canvas.zoomScale
        var copy = CanvasImage(id: UUID(), frame: image.frame.offsetBy(dx: offset, dy: offset), data: image.data)
        copy.rotation = image.rotation
        copy.rounded = image.rounded
        copy.shadow = image.shadow
        addNewImage(copy)
    }

    func copySelectedImage() {
        guard let image = selectedImage, let ui = uiImage(for: image) else { return }
        UIPasteboard.general.image = ui
        ImageClipboard.item = image
        ImageClipboard.changeCount = UIPasteboard.general.changeCount
    }

    func cutSelectedImage() {
        copySelectedImage()
        deleteSelectedImage()
    }

    /// Incolla l'immagine copiata in BetterNotes (con il suo aspetto). Restituisce falso se negli appunti
    /// c'è un'immagine esterna, che il controller inserisce come nuova immagine.
    func pasteOwnImage() -> Bool {
        guard ImageClipboard.hasOwnItem, let item = ImageClipboard.item else { return false }
        let area = insertionArea()
        let offset = 28 / canvas.zoomScale
        var position = CGPoint(x: item.center.x + offset, y: item.center.y + offset)
        if !area.contains(position) { position = CGPoint(x: area.midX, y: area.midY) }
        var copy = CanvasImage(id: UUID(), frame: item.frame, data: item.data)
        copy.rotation = item.rotation
        copy.rounded = item.rounded
        copy.shadow = item.shadow
        addNewImage(copy.withCenter(position))
        return true
    }

    func rotateSelectedImage(by angle: CGFloat) {
        replaceSelected { $0.rotation = Self.normalizedAngle($0.rotation + angle) }
    }

    func setSelectedImage(rounded: Bool) {
        replaceSelected { $0.rounded = rounded }
    }

    func setSelectedImage(shadow: Bool) {
        replaceSelected { $0.shadow = shadow }
    }

    func bringSelectedImageToFront() {
        guard let id = selectedImageID, let index = images.firstIndex(where: { $0.id == id }) else { return }
        let image = images.remove(at: index)
        images.append(image)
        syncImageViews()
        commit()
    }

    private static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }

    /// Aggancio a 0°, 90°, 180°, 270° quando ci si avvicina.
    private static func snappedAngle(_ angle: CGFloat) -> CGFloat {
        let step = CGFloat.pi / 2
        let nearest = (angle / step).rounded() * step
        return abs(angle - nearest) < .pi / 60 ? nearest : angle
    }

    // MARK: Gesti

    private func imageIndex(at point: CGPoint) -> Int? {
        images.lastIndex { $0.contains(point) }
    }

    private func corner(at point: CGPoint) -> CGPoint? {
        guard let image = selectedImage else { return nil }
        let local = image.localPoint(point)
        let radius = 30 / canvas.zoomScale
        let w = image.frame.width / 2, h = image.frame.height / 2
        let signs = [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1)]
        return signs.first { hypot(local.x - $0.x * w, local.y - $0.y * h) <= radius }
    }

    private func isOnRotationHandle(_ point: CGPoint) -> Bool {
        guard let image = selectedImage else { return false }
        let local = image.localPoint(point)
        let knobY = -image.frame.height / 2 - ImageSelectionView.rotationHandleDistance(zoom: canvas.zoomScale)
        return hypot(local.x, local.y - knobY) <= 30 / canvas.zoomScale
    }

    func imageGestureShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if gesture === imagePan {
            let point = gesture.location(in: imageLayerView)
            return isOnRotationHandle(point) || corner(at: point) != nil || imageIndex(at: point) != nil
        }
        if gesture === imagePinch || gesture === imageRotation {
            guard let image = selectedImage else { return false }
            return image.contains(gesture.location(in: imageLayerView), slack: 60 / canvas.zoomScale)
        }
        if gesture === lassoImageTap {
            return imageIndex(at: gesture.location(in: imageLayerView)) != nil
        }
        return true
    }

    @objc private func handleLassoImageTap(_ gesture: UITapGestureRecognizer) {
        guard let index = imageIndex(at: gesture.location(in: imageLayerView)) else { return }
        let id = images[index].id
        setEditingImages(true)
        selectImage(id)
        // Il lazo di PencilKit reagisce allo stesso tocco mostrando il suo menu ("Seleziona tutto"…): lo chiudiamo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.dismissEditMenus() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.dismissEditMenus() }
    }

    private func dismissEditMenus() {
        func visit(_ view: UIView) {
            for case let menu as UIEditMenuInteraction in view.interactions { menu.dismissMenu() }
            view.subviews.forEach(visit)
        }
        visit(canvas)
    }

    @objc private func handleImageTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: imageLayerView)
        if isOnRotationHandle(point) { return }
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
            if isOnRotationHandle(point) {
                imageDragMode = .rotate
            } else if let corner = corner(at: point) {
                imageDragMode = .resize(corner)
            } else if let index = imageIndex(at: point) {
                selectImage(images[index].id)
                imageDragMode = .move
            } else {
                imageDragMode = .none
            }
            imageDragStart = selectedImage
            if let start = imageDragStart {
                imageDragStartAngle = atan2(point.y - start.center.y, point.x - start.center.x)
            }
        case .changed:
            guard let start = imageDragStart else { return }
            let t = gesture.translation(in: imageLayerView)
            switch imageDragMode {
            case .move:
                replaceSelected({ $0.frame = start.frame.offsetBy(dx: t.x, dy: t.y) }, commitChange: false)
            case .resize(let corner):
                let resizedImage = resized(start, corner: corner, translation: t)
                replaceSelected({ $0.frame = resizedImage.frame }, commitChange: false)
            case .rotate:
                let angle = atan2(point.y - start.center.y, point.x - start.center.x)
                let rotation = Self.snappedAngle(Self.normalizedAngle(start.rotation + angle - imageDragStartAngle))
                replaceSelected({ $0.rotation = rotation }, commitChange: false)
            case .none:
                break
            }
        case .ended, .cancelled:
            if case .none = imageDragMode { return }
            imageDragMode = .none
            expandInfiniteCanvasIfNeeded()
            commit()
            controller?.imageSelectionDidChange(selectedImage)
        default:
            break
        }
    }

    /// Ridimensiona dall'angolo trascinato tenendo fermo quello opposto (anche se l'immagine è ruotata).
    private func resized(_ start: CanvasImage, corner sign: CGPoint, translation t: CGPoint) -> CanvasImage {
        let size = start.frame.size
        let anchorLocal = CGPoint(x: -sign.x * size.width / 2, y: -sign.y * size.height / 2)
        let cornerLocal = CGPoint(x: sign.x * size.width / 2, y: sign.y * size.height / 2)
        let c = cos(-start.rotation), s = sin(-start.rotation)
        let localT = CGPoint(x: t.x * c - t.y * s, y: t.x * s + t.y * c)
        let moving = CGPoint(x: cornerLocal.x + localT.x, y: cornerLocal.y + localT.y)
        let scaleX = abs(moving.x - anchorLocal.x) / max(size.width, 1)
        let scaleY = abs(moving.y - anchorLocal.y) / max(size.height, 1)
        let minScale = 40 / max(min(size.width, size.height), 1)
        let scale = max(minScale, max(scaleX, scaleY))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let centerLocal = CGPoint(x: anchorLocal.x + sign.x * newSize.width / 2, y: anchorLocal.y + sign.y * newSize.height / 2)
        let newCenter = start.documentPoint(centerLocal)
        var result = start
        result.frame = CGRect(x: newCenter.x - newSize.width / 2, y: newCenter.y - newSize.height / 2, width: newSize.width, height: newSize.height)
        return result
    }

    @objc private func handleImagePinch(_ gesture: UIPinchGestureRecognizer) {
        handleTwoFingerImageGesture(gesture) { start in
            let scale = max(0.1, gesture.scale)
            let minScale = 40 / max(min(start.frame.width, start.frame.height), 1)
            let factor = max(minScale, scale)
            let size = CGSize(width: start.frame.width * factor, height: start.frame.height * factor)
            return { $0.frame = CGRect(x: start.center.x - size.width / 2, y: start.center.y - size.height / 2, width: size.width, height: size.height) }
        }
    }

    @objc private func handleImageRotation(_ gesture: UIRotationGestureRecognizer) {
        handleTwoFingerImageGesture(gesture) { start in
            let rotation = Self.snappedAngle(Self.normalizedAngle(start.rotation + gesture.rotation))
            return { $0.rotation = rotation }
        }
    }

    /// Pizzico e rotazione a due dita possono avvenire insieme: si salva una sola voce di cronologia alla fine.
    private func handleTwoFingerImageGesture(_ gesture: UIGestureRecognizer, change: (CanvasImage) -> (inout CanvasImage) -> Void) {
        switch gesture.state {
        case .began:
            activeImageGestures += 1
            if activeImageGestures == 1 { imageDragStart = selectedImage }
        case .changed:
            guard let start = imageDragStart, let current = selectedImage else { return }
            // Ogni gesto modifica solo la propria proprietà, partendo dallo stato attuale dell'altra.
            var base = current
            base.frame = CGRect(x: current.center.x - start.frame.width / 2, y: current.center.y - start.frame.height / 2,
                                width: start.frame.width, height: start.frame.height)
            base.rotation = start.rotation
            let apply = change(base)
            replaceSelected({ image in
                var updated = image
                if gesture is UIPinchGestureRecognizer { apply(&updated); image.frame = updated.frame }
                else { apply(&updated); image.rotation = updated.rotation }
            }, commitChange: false)
        case .ended, .cancelled, .failed:
            activeImageGestures = max(0, activeImageGestures - 1)
            if activeImageGestures == 0 {
                imageDragStart = nil
                expandInfiniteCanvasIfNeeded()
                commit()
                controller?.imageSelectionDidChange(selectedImage)
            }
        default:
            break
        }
    }
}
