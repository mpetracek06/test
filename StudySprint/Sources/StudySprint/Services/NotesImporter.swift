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
        UTType(filenameExtension: "pptx") ?? .data,
    ]

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "webp", "bmp"]
    private static let maxPDFBytes = 20 * 1024 * 1024

    /// Text plus any pictures in the file. Pictures become figures that the guide shows and explains.
    static func load(from url: URL) throws -> [Imported] {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent

        if imageExtensions.contains(ext) {
            guard let image = NSImage(contentsOf: url), let attachment = attachment(from: image, name: name) else {
                throw ImportError.unreadable(name)
            }
            return [.attachment(attachment)]
        }

        if ext == "pdf" {
            guard let data = try? Data(contentsOf: url), let doc = PDFDocument(data: data) else { throw ImportError.unreadable(name) }
            let text = doc.string ?? ""
            let perPage = text.count / max(doc.pageCount, 1)
            // Little or no selectable text means a scan or handwriting: let Claude read the pages directly.
            if perPage < 150, data.count <= maxPDFBytes {
                return [.attachment(NoteAttachment(kind: .pdf, name: name, mediaType: "application/pdf", data: data))]
            }
            return [.text(text)] + FigureExtractor.pdfImages(data, name: name).map(Imported.attachment)
        }

        if ext == "pptx" {
            return [.text(FigureExtractor.pptxText(at: url))] + FigureExtractor.officeImages(at: url).map(Imported.attachment)
        }

        if ext == "docx" {
            let text = try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
            return [.text(text)] + FigureExtractor.officeImages(at: url).map(Imported.attachment)
        }

        if ["rtf", "rtfd", "doc", "html", "htm", "odt"].contains(ext) {
            let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            return [.text(attributed.string)] + embeddedImages(in: attributed, name: name).map(Imported.attachment)
        }

        return [.text(try String(contentsOf: url, encoding: .utf8))]
    }

    /// Pictures on the clipboard: images copied on their own, pictures inside copied rich text
    /// (Word, Pages, Notes, TextEdit), and pictures or diagrams inside copied PDF content.
    static func pictures(from pb: NSPasteboard) -> [NoteAttachment] {
        var found: [NoteAttachment] = []
        if let data = pb.data(forType: .rtfd), let text = NSAttributedString(rtfd: data, documentAttributes: nil) {
            found += embeddedImages(in: text, name: "Pasted")
        } else if let data = pb.data(forType: .rtf), let text = NSAttributedString(rtf: data, documentAttributes: nil) {
            found += embeddedImages(in: text, name: "Pasted")
        }
        if found.isEmpty, let data = pb.data(forType: .pdf) {
            found += FigureExtractor.pdfImages(data, name: "Pasted PDF")
        }
        // A copied picture on its own (screenshot, Preview selection, Photos). When text came along,
        // any image on the clipboard is usually just a snapshot of that text, so it's ignored.
        if found.isEmpty, pb.string(forType: .string)?.isEmpty != false,
           NSImage.canInit(with: pb), let image = NSImage(pasteboard: pb),
           let attachment = attachment(from: image, name: "Pasted picture") {
            found.append(attachment)
        }
        return found
    }

    /// Pictures embedded in rich text (RTFD, HTML, Word 97).
    static func embeddedImages(in text: NSAttributedString, name: String) -> [NoteAttachment] {
        var out: [NoteAttachment] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            guard let attachment = value as? NSTextAttachment else { return }
            let image = attachment.image
                ?? attachment.fileWrapper?.regularFileContents.flatMap(NSImage.init(data:))
            guard let image, image.size.width >= 120, image.size.height >= 120,
                  let figure = Self.attachment(from: image, name: "\(name) · picture \(out.count + 1)") else { return }
            out.append(figure)
            if out.count >= FigureExtractor.maxFigures { stop.pointee = true }
        }
        return out
    }

    /// Renders the first pages of a PDF as JPEG images (for models that read images but not PDFs).
    static func pageImages(fromPDF data: Data, name: String, maxPages: Int = 8) -> [NoteAttachment] {
        guard let doc = PDFDocument(data: data) else { return [] }
        return (0..<min(doc.pageCount, maxPages)).compactMap { i in
            guard let page = doc.page(at: i) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 1400 / max(bounds.width, bounds.height)
            let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            return attachment(from: image, name: "\(name) p\(i + 1)", role: .page)
        }
    }

    /// Downscales to the size Claude actually uses (long edge 1568px) and re-encodes as JPEG.
    static func attachment(from image: NSImage, name: String, role: NoteAttachment.Role = .figure) -> NoteAttachment? {
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
        return NoteAttachment(kind: .image, role: role, name: name, mediaType: "image/jpeg", data: data)
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
