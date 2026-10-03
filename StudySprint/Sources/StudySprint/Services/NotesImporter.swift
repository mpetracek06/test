import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Pulls plain text out of the kinds of files people keep notes in.
enum NotesImporter {
    static let supportedTypes: [UTType] = [
        .plainText, .text, .pdf, .rtf, .rtfd, .html,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "docx") ?? .data,
    ]

    static func text(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw ImportError.unreadable(url.lastPathComponent) }
            return doc.string ?? ""
        }
        if ["rtf", "rtfd", "docx", "doc", "html", "htm", "odt"].contains(ext) {
            let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            return attributed.string
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    enum ImportError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Couldn't read text from \(name)."
            }
        }
    }
}
