import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import WebKit

enum ImportError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Impossibile leggere “\(name)”."
        case .unsupported(let name): "Il formato di “\(name)” non è supportato."
        case .conversionFailed(let name): "Impossibile convertire “\(name)” in pagine annotabili."
        }
    }
}

/// Importa PDF e documenti Word (.docx / .doc) come note annotabili con la Pencil.
@MainActor
enum DocumentImporter {
    static let docx = UTType("org.openxmlformats.wordprocessingml.document") ?? UTType(filenameExtension: "docx") ?? .data
    static let doc = UTType("com.microsoft.word.doc") ?? UTType(filenameExtension: "doc") ?? .data
    static let supportedTypes: [UTType] = [.pdf, docx, doc]

    struct Imported {
        let title: String
        let fileName: String
        let pdfData: Data
        let pageCount: Int
    }

    static func importFile(at url: URL) async throws -> Imported {
        let fileName = url.lastPathComponent
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Copia locale: il processo di WebKit non può leggere file con accesso "security scoped".
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let localURL = tempDir.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: url, to: localURL)
        } catch {
            throw ImportError.unreadable(fileName)
        }

        let ext = localURL.pathExtension.lowercased()
        let title = localURL.deletingPathExtension().lastPathComponent
        let pdfData: Data
        switch ext {
        case "pdf":
            guard let data = try? Data(contentsOf: localURL) else { throw ImportError.unreadable(fileName) }
            pdfData = data
        case "docx", "doc":
            pdfData = try await WordConverter.convert(fileURL: localURL, name: fileName)
        default:
            throw ImportError.unsupported(fileName)
        }

        guard let document = PDFDocument(data: pdfData), document.pageCount > 0 else {
            throw ImportError.conversionFailed(fileName)
        }
        return Imported(title: title, fileName: fileName, pdfData: pdfData, pageCount: document.pageCount)
    }
}

/// Converte un documento Word in PDF impaginato A4 usando il motore di rendering di WebKit.
@MainActor
final class WordConverter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    static func convert(fileURL: URL, name: String) async throws -> Data {
        let converter = WordConverter()
        return try await converter.run(fileURL: fileURL, name: name)
    }

    private func run(fileURL: URL, name: String) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123), configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false

        // Il rendering è più affidabile se la web view è in una finestra (fuori schermo).
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        if let window {
            webView.frame.origin = CGPoint(x: -20_000, y: 0)
            window.addSubview(webView)
        }
        defer { webView.removeFromSuperview() }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuation = cont
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        }
        // Lascia a WebKit il tempo di completare l'impaginazione.
        try? await Task.sleep(for: .milliseconds(700))

        if let paginated = paginate(webView), paginated.count > 1_000 {
            return paginated
        }
        do {
            return try await webView.pdf(configuration: WKPDFConfiguration())
        } catch {
            throw ImportError.conversionFailed(name)
        }
    }

    private func paginate(_ webView: WKWebView) -> Data? {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 36, dy: 42)), forKey: "printableRect")
        let pages = renderer.numberOfPages
        guard pages > 0 else { return nil }
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        let bounds = UIGraphicsGetPDFContextBounds()
        for index in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: bounds)
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
