import PencilKit
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Un campione di input (in coordinate documento).
struct InkSample {
    var location: CGPoint
    var time: TimeInterval
    var force: CGFloat
    var azimuth: CGFloat
    var altitude: CGFloat
    var isPencil: Bool
}

/// Riceve i tocchi di Apple Pencil (e del dito, se consentito) e li passa al motore d'inchiostro.
/// - Con la Pencil gli altri tocchi (il palmo) vengono ignorati.
/// - Con il dito, un secondo dito annulla il tratto: la tela scorre o zooma, e il tap a due dita fa undo.
final class InkInputGesture: UIGestureRecognizer {
    weak var engine: LiveInkEngine?
    var acceptsFinger = false
    private var trackedTouch: UITouch?

    private func accepts(_ touch: UITouch) -> Bool {
        touch.type == .pencil || (acceptsFinger && touch.type == .direct)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let tracked = trackedTouch {
            let newFingers = touches.filter { $0 !== tracked && $0.type == .direct }
            if tracked.type == .direct, !newFingers.isEmpty {
                MainActor.assumeIsolated { engine?.cancel() }
                state = .cancelled
                return
            }
            touches.filter { $0 !== tracked }.forEach { ignore($0, for: event) }
            return
        }
        guard touches.count == 1, let touch = touches.first, accepts(touch), let view else {
            touches.forEach { ignore($0, for: event) }
            return
        }
        trackedTouch = touch
        MainActor.assumeIsolated { engine?.begin(touch: touch, event: event, in: view) }
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked = trackedTouch, touches.contains(tracked), let view else { return }
        MainActor.assumeIsolated { engine?.move(touch: tracked, event: event, in: view) }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked = trackedTouch, touches.contains(tracked), let view else { return }
        MainActor.assumeIsolated { engine?.end(touch: tracked, event: event, in: view) }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked = trackedTouch, touches.contains(tracked) else { return }
        MainActor.assumeIsolated { engine?.cancel() }
        state = .cancelled
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }
}

/// Motore d'inchiostro: stabilizza il tratto *mentre* si scrive e lo mostra subito con un'anteprima
/// vettoriale; a fine tratto lo consegna a PencilKit, che lo disegna con il suo inchiostro.
@MainActor
final class LiveInkEngine {
    unowned let host: NoteCanvasView
    let previewContainer = CALayer()
    private let activeLayer = CAShapeLayer()
    private var pendingLayers: [(layer: CAShapeLayer, created: CFTimeInterval)] = []

    private var samples: [InkSample] = []
    private var lazyPoint = CGPoint.zero
    private var smoothPoint = CGPoint.zero
    private var lastRaw: InkSample?
    private var startTime: TimeInterval = 0
    private var startDate = Date()
    private var zoom: CGFloat = 1
    private var tool = ToolState()
    private(set) var isActive = false

    init(host: NoteCanvasView) {
        self.host = host
        previewContainer.masksToBounds = false
        configure(activeLayer)
        previewContainer.addSublayer(activeLayer)
    }

    private func configure(_ layer: CAShapeLayer) {
        layer.fillRule = .nonZero
        layer.lineWidth = 0
        layer.actions = ["path": NSNull(), "fillColor": NSNull(), "opacity": NSNull()]
    }

    // MARK: - Input

    private func sample(from touch: UITouch, in view: UIView) -> InkSample {
        let zoom = max(host.canvas.zoomScale, 0.01)
        let point = touch.preciseLocation(in: view)
        return InkSample(
            location: CGPoint(x: point.x / zoom, y: point.y / zoom),
            time: touch.timestamp,
            force: touch.type == .pencil ? touch.force : 0,
            azimuth: touch.azimuthAngle(in: view),
            altitude: touch.altitudeAngle,
            isPencil: touch.type == .pencil
        )
    }

    func begin(touch: UITouch, event: UIEvent, in view: UIView) {
        cancel()
        tool = host.tool
        zoom = max(host.canvas.zoomScale, 0.01)
        let first = sample(from: touch, in: view)
        samples = [first]
        lazyPoint = first.location
        smoothPoint = first.location
        lastRaw = first
        startTime = first.time
        startDate = Date()
        isActive = true
        host.liveInkDidBegin()
        updatePreview(predicted: [])
    }

    func move(touch: UITouch, event: UIEvent, in view: UIView) {
        guard isActive else { return }
        let coalesced = event.coalescedTouches(for: touch) ?? [touch]
        for t in coalesced { process(sample(from: t, in: view)) }
        let predicted = (event.predictedTouches(for: touch) ?? []).map { sample(from: $0, in: view) }
        updatePreview(predicted: simulate(predicted))
    }

    func end(touch: UITouch, event: UIEvent, in view: UIView) {
        guard isActive else { return }
        let coalesced = event.coalescedTouches(for: touch) ?? [touch]
        for t in coalesced { process(sample(from: t, in: view)) }
        catchUpToPenLift()
        isActive = false

        guard let stroke = makeStroke() else {
            activeLayer.path = nil
            host.liveInkDidCancel()
            return
        }
        // L'anteprima resta visibile finché PencilKit non ha disegnato il tratto: nessun "buco".
        let pending = CAShapeLayer()
        configure(pending)
        pending.path = activeLayer.path
        pending.fillColor = activeLayer.fillColor
        previewContainer.addSublayer(pending)
        pendingLayers.append((pending, CACurrentMediaTime()))
        activeLayer.path = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.removePending(olderThan: 0.35) }

        host.commitLiveStroke(stroke)
    }

    func cancel() {
        guard isActive else { return }
        isActive = false
        samples = []
        activeLayer.path = nil
        host.liveInkDidCancel()
    }

    func canvasDidFinishRendering() {
        removePending(olderThan: 0.03)
    }

    /// Se la tela scorre, un'anteprima rimasta ferma sullo schermo sarebbe fuori posto.
    func canvasDidScroll() {
        guard !pendingLayers.isEmpty else { return }
        removePending(olderThan: 0)
    }

    private func removePending(olderThan age: CFTimeInterval) {
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pendingLayers.removeAll { item in
            guard now - item.created >= age else { return false }
            item.layer.removeFromSuperlayer()
            return true
        }
        CATransaction.commit()
    }

    // MARK: - Stabilizzazione

    /// Raggio del "filo" (lazy brush) in punti schermo e forza del filtro esponenziale.
    private var lazyRadius: CGFloat { CGFloat(tool.stabilization) * 7 / zoom }
    private var smoothing: CGFloat { CGFloat(1 - 0.6 * tool.stabilization) }

    private func filtered(_ raw: CGPoint, lazy: inout CGPoint, smooth: inout CGPoint) -> CGPoint {
        let dx = raw.x - lazy.x, dy = raw.y - lazy.y
        let distance = hypot(dx, dy)
        let radius = lazyRadius
        if distance > radius, distance > 0 {
            let pull = (distance - radius) / distance
            lazy.x += dx * pull
            lazy.y += dy * pull
        }
        let k = smoothing
        smooth.x += (lazy.x - smooth.x) * k
        smooth.y += (lazy.y - smooth.y) * k
        return smooth
    }

    private func process(_ raw: InkSample) {
        lastRaw = raw
        var point = raw
        point.location = filtered(raw.location, lazy: &lazyPoint, smooth: &smoothPoint)
        if let last = samples.last, hypot(point.location.x - last.location.x, point.location.y - last.location.y) < 0.3 / zoom {
            return
        }
        samples.append(point)
    }

    /// Applica il filtro ai punti previsti senza modificarne lo stato (servono solo all'anteprima).
    private func simulate(_ predicted: [InkSample]) -> [InkSample] {
        var lazy = lazyPoint, smooth = smoothPoint
        return predicted.map { raw in
            var point = raw
            point.location = filtered(raw.location, lazy: &lazy, smooth: &smooth)
            return point
        }
    }

    /// A fine tratto il punto stabilizzato raggiunge quello dove si è sollevata la Pencil.
    private func catchUpToPenLift() {
        guard let raw = lastRaw, let last = samples.last else { return }
        let dx = raw.location.x - last.location.x, dy = raw.location.y - last.location.y
        let distance = hypot(dx, dy)
        guard distance > 0.4 / zoom else { return }
        let steps = min(6, max(2, Int(distance * zoom / 2)))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            var point = raw
            point.location = CGPoint(x: last.location.x + dx * t, y: last.location.y + dy * t)
            samples.append(point)
        }
    }

    // MARK: - Aspetto del tratto

    private func pressure(_ sample: InkSample) -> CGFloat {
        guard sample.isPencil else { return 1 }
        return 0.55 + 0.75 * min(1, max(0, sample.force) / 1.6)
    }

    private func width(for sample: InkSample) -> CGFloat {
        let base = tool.inkWidth
        switch tool.kind {
        case .pen, .fountain: return base * pressure(sample)
        case .pencil: return base * (0.85 + 0.25 * (pressure(sample) - 0.55) / 0.75)
        default: return base
        }
    }

    private func pointOpacity(for sample: InkSample) -> CGFloat {
        guard tool.kind == .pencil else { return 1 }
        return sample.isPencil ? 0.3 + 0.6 * min(1, max(0, sample.force) / 1.6) : 0.65
    }

    /// Dimensione del punto PencilKit che produce la larghezza visibile `width`.
    /// Misurata sul motore di PencilKit: per penna e fineliner la larghezza resa è ≈ 2·(dimensione − 2)
    /// (sotto ~2 il tratto scompare), lo stesso rapporto che PencilKit usa con i propri strumenti.
    private func pencilKitSize(forVisibleWidth width: CGFloat) -> CGFloat {
        switch tool.kind {
        case .pencil: return max(1, width / 1.9)
        case .fountain: return 2 * width + 2
        case .marker: return 2 * width
        default: return max(2.4, width / 2 + 2)
        }
    }

    private var secondaryScale: CGFloat {
        switch tool.kind {
        case .pen: 0.325
        case .pencil: 0.782
        case .fountain: 0.35
        default: 1
        }
    }

    private var inkColor: UIColor {
        tool.uiColor.withAlphaComponent(CGFloat(max(0.05, min(1, tool.opacity))))
    }

    private func makeStroke() -> PKStroke? {
        guard !samples.isEmpty else { return nil }
        var points = samples
        if points.count == 1 {
            // Un tocco singolo diventa un punto.
            var dot = points[0]
            dot.location.x += 0.2 / zoom
            dot.time += 0.001
            points.append(dot)
        }
        let controlPoints = points.map { sample in
            let w = pencilKitSize(forVisibleWidth: width(for: sample))
            return PKStrokePoint(
                location: sample.location,
                timeOffset: sample.time - startTime,
                size: CGSize(width: w, height: w),
                opacity: pointOpacity(for: sample),
                force: sample.force,
                azimuth: sample.azimuth,
                altitude: sample.altitude,
                secondaryScale: secondaryScale,
                threshold: 0
            )
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: startDate)
        return PKStroke(ink: PKInk(tool.kind.inkType, color: inkColor), path: path)
    }

    // MARK: - Anteprima

    private func updatePreview(predicted: [InkSample]) {
        let all = samples + predicted
        guard !all.isEmpty else { activeLayer.path = nil; return }
        let points = all.map { host.screenPoint(fromDocument: $0.location) }
        let radii = all.map { max(0.5, width(for: $0) * zoom / 2) }
        var alpha = CGFloat(max(0.05, min(1, tool.opacity)))
        if tool.kind == .marker { alpha *= 0.45 }
        if tool.kind == .pencil { alpha *= 0.8 }
        activeLayer.fillColor = tool.uiColor.withAlphaComponent(alpha).cgColor
        activeLayer.path = Self.ribbonPath(points: points, radii: radii, squareCaps: tool.kind == .marker)
    }

    /// Contorno di un tratto a larghezza variabile (nastro con estremità arrotondate).
    static func ribbonPath(points: [CGPoint], radii: [CGFloat], squareCaps: Bool) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        let count = points.count
        if count == 1 {
            let r = radii[0]
            path.addEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: 2 * r, height: 2 * r))
            return path
        }
        var left: [CGPoint] = [], right: [CGPoint] = [], normalAngles: [CGFloat] = []
        left.reserveCapacity(count)
        right.reserveCapacity(count)
        for i in 0..<count {
            let prev = points[max(0, i - 1)], next = points[min(count - 1, i + 1)]
            var tx = next.x - prev.x, ty = next.y - prev.y
            let length = hypot(tx, ty)
            if length < 0.0001 { tx = 1; ty = 0 } else { tx /= length; ty /= length }
            let nx = -ty, ny = tx
            let r = radii[i], p = points[i]
            left.append(CGPoint(x: p.x + nx * r, y: p.y + ny * r))
            right.append(CGPoint(x: p.x - nx * r, y: p.y - ny * r))
            normalAngles.append(atan2(ny, nx))
        }
        func cap(around center: CGPoint, radius: CGFloat, from angle: CGFloat) {
            if squareCaps {
                path.addLine(to: CGPoint(x: center.x + cos(angle - .pi) * radius, y: center.y + sin(angle - .pi) * radius))
                return
            }
            for step in 1...10 {
                let a = angle - .pi * CGFloat(step) / 10
                path.addLine(to: CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius))
            }
        }
        path.move(to: left[0])
        for i in 1..<count { path.addLine(to: left[i]) }
        cap(around: points[count - 1], radius: radii[count - 1], from: normalAngles[count - 1])
        for i in stride(from: count - 1, through: 0, by: -1) { path.addLine(to: right[i]) }
        cap(around: points[0], radius: radii[0], from: normalAngles[0] - .pi)
        path.closeSubpath()
        return path
    }
}
