import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Cache delle miniature decodificate (evita di decodificare JPEG a ogni ridisegno della griglia).
@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(for note: Note) -> UIImage? {
        guard let data = note.thumbnailData else { return nil }
        let key = "\(note.id.uuidString)-\(data.count)-\(note.updatedAt.timeIntervalSinceReferenceDate)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
