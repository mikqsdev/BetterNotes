import PencilKit
import UIKit
import UniformTypeIdentifiers

// MARK: - Tratti dentro la pagina (righello e strumenti PencilKit)

extension NoteCanvasView {
    /// Nei fogli impaginati i tratti disegnati da PencilKit (es. con il righello) restano dentro la pagina
    /// in cui iniziano; quelli iniziati fuori da ogni pagina vengono scartati.
    func clipNewPencilKitStrokesToPages() {
        guard !layout.isInfinite, tool.kind.isInk else { return }
        let previous = lastState.drawing.strokes.count
        var strokes = canvas.drawing.strokes
        guard strokes.count > previous else { return }
        var changed = false
        var index = previous
        while index < strokes.count {
            let stroke = strokes[index]
            guard stroke.mask == nil, let first = stroke.path.first else { index += 1; continue }
            let start = first.location.applying(stroke.transform)
            guard let page = pageRect(containing: start) else {
                strokes.remove(at: index)
                changed = true
                continue
            }
            if !page.contains(stroke.renderBounds) {
                // La maschera è nello spazio del tratto (prima della sua trasformazione).
                let mask = UIBezierPath(rect: page)
                mask.apply(stroke.transform.inverted())
                strokes[index] = PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: mask)
                changed = true
            }
            index += 1
        }
        guard changed else { return }
        isApplyingState = true
        canvas.drawing = PKDrawing(strokes: strokes)
        isApplyingState = false
    }
}

// MARK: - Immagini trascinate da altre app

extension NoteCanvasView: UIDropInteractionDelegate {
    func setupImageDrop() {
        addInteraction(UIDropInteraction(delegate: self))
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.canLoadObjects(ofClass: UIImage.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        // Le immagini trascinate dentro BetterNotes stesso (es. dalla tela) non vanno duplicate.
        UIDropProposal(operation: session.localDragSession == nil ? .copy : .cancel)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        let zoom = max(canvas.zoomScale, 0.01)
        let location = session.location(in: canvas)
        let center = CGPoint(x: location.x / zoom, y: location.y / zoom)
        session.loadObjects(ofClass: UIImage.self) { [weak self] objects in
            let images = objects.compactMap { $0 as? UIImage }
            Task { @MainActor in
                guard let self else { return }
                for (offset, image) in images.enumerated() {
                    let shift = CGFloat(offset) * 32
                    self.controller?.insertImage(image, at: CGPoint(x: center.x + shift, y: center.y + shift))
                }
            }
        }
    }
}
