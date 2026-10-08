import UIKit

extension UIResponder {
    private nonisolated(unsafe) static weak var foundFirstResponder: UIResponder?

    /// Il first responder attuale (inviando un'azione a `nil` UIKit la recapita proprio a lui).
    @MainActor
    static func bnCurrentFirstResponder() -> UIResponder? {
        foundFirstResponder = nil
        UIApplication.shared.sendAction(#selector(bnCaptureFirstResponder(_:)), to: nil, from: nil, for: nil)
        return foundFirstResponder
    }

    @objc private func bnCaptureFirstResponder(_ sender: Any?) {
        UIResponder.foundFirstResponder = self
    }
}
