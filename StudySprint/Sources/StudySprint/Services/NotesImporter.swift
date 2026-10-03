import AppKit
import PDFKit
import UniformTypeIdentifiers
import StudySprintCore

/// Pulls notes out of files: text where possible; photos and scanned PDFs are attached for Claude to read.
enum NotesImporter {
    enum Imported {
        case text(String)
        case attachment(NoteAttachment)
    }

    static let supportedTypes: [UTType] = [
        .plainText, .text, .pdf, .rtf, .rtfd, .html, .image, .jpeg, .png, .heic,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "docx") ?? .data,
    ]

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "webp", "bmp"]
    private static let maxPDFBytes = 20 * 1024 * 1024

    static func load(from url: URL) throws -> Imported {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            guard let image = NSImage(contentsOf: url), let attachment = attachment(from: image, name: url.lastPathComponent) else {
                throw ImportError.unreadable(url.lastPathComponent)
            }
            return .attachment(attachment)
        }
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw ImportError.unreadable(url.lastPathComponent) }
            let text = doc.string ?? ""
            let perPage = text.count / max(doc.pageCount, 1)
            // Little or no selectable text means a scan or handwriting: let Claude read the pages directly.
            if perPage < 150, let data = try? Data(contentsOf: url), data.count <= maxPDFBytes {
                return .attachment(NoteAttachment(kind: .pdf, name: url.lastPathComponent,
                                                  mediaType: "application/pdf", data: data))
            }
            return .text(text)
        }
        if ["rtf", "rtfd", "docx", "doc", "html", "htm", "odt"].contains(ext) {
            return .text(try NSAttributedString(url: url, options: [:], documentAttributes: nil).string)
        }
        return .text(try String(contentsOf: url, encoding: .utf8))
    }

    /// Renders the first pages of a PDF as JPEG images (for models that read images but not PDFs).
    static func pageImages(fromPDF data: Data, name: String, maxPages: Int = 8) -> [NoteAttachment] {
        guard let doc = PDFDocument(data: data) else { return [] }
        return (0..<min(doc.pageCount, maxPages)).compactMap { i in
            guard let page = doc.page(at: i) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 1400 / max(bounds.width, bounds.height)
            let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            return attachment(from: image, name: "\(name) p\(i + 1)")
        }
    }

    /// Downscales to the size Claude actually uses (long edge 1568px) and re-encodes as JPEG.
    static func attachment(from image: NSImage, name: String) -> NoteAttachment? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let longEdge = CGFloat(max(cg.width, cg.height))
        let scale = min(1, 1568 / longEdge)
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }
        return NoteAttachment(kind: .image, name: name, mediaType: "image/jpeg", data: data)
    }

    enum ImportError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Couldn't read \(name)."
            }
        }
    }
}
