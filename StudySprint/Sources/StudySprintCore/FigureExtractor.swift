import Foundation
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Pulls the pictures (diagrams, charts, photos) out of imported notes so the guide can show
/// and explain them. Works on Word (.docx), PowerPoint (.pptx) and PDF files.
public enum FigureExtractor {
    /// Images smaller than this on either side are icons, bullets or logos: skipped.
    static let minSide = 120
    /// Long edge sent to Claude (the size it actually uses).
    static let maxSide: CGFloat = 1568
    public static let maxFigures = 15

    // MARK: Office files (.docx, .pptx, .xlsx are zip archives with a media folder)

    public static func officeImages(at url: URL, limit: Int = maxFigures) -> [NoteAttachment] {
        guard let dir = unzip(url) else { return [] }
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        let mediaDirs = ["word/media", "ppt/media", "xl/media"].map { dir.appendingPathComponent($0) }
        let files = mediaDirs.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .sorted { naturalOrder($0.lastPathComponent, $1.lastPathComponent) }

        var out: [NoteAttachment] = []
        var seen = Set<String>()
        for file in files where out.count < limit {
            guard let data = try? Data(contentsOf: file), seen.insert(digest(data)).inserted,
                  let image = cgImage(from: data), let jpeg = jpegData(image) else { continue }
            out.append(NoteAttachment(kind: .image, role: .figure,
                                      name: "\(url.lastPathComponent) · picture \(out.count + 1)",
                                      mediaType: "image/jpeg", data: jpeg))
        }
        return out
    }

    /// Slide text from a .pptx, in slide order.
    public static func pptxText(at url: URL) -> String {
        guard let dir = unzip(url) else { return "" }
        defer { try? FileManager.default.removeItem(at: dir) }
        let slidesDir = dir.appendingPathComponent("ppt/slides")
        let slides = ((try? FileManager.default.contentsOfDirectory(at: slidesDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "xml" }
            .sorted { naturalOrder($0.lastPathComponent, $1.lastPathComponent) }
        return slides.enumerated().compactMap { i, file -> String? in
            guard let xml = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let runs = xmlText(xml, tag: "a:t")
            return runs.isEmpty ? nil : "Slide \(i + 1): " + runs.joined(separator: " ")
        }.joined(separator: "\n")
    }

    // MARK: PDF (raster images embedded in the pages)

    public static func pdfImages(_ data: Data, name: String, limit: Int = maxFigures) -> [NoteAttachment] {
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider) else { return [] }
        var out: [NoteAttachment] = []
        var seen = Set<String>()
        for pageNumber in 1...max(doc.numberOfPages, 1) where out.count < limit {
            guard let page = doc.page(at: pageNumber), let pageDict = page.dictionary else { continue }
            var resources: CGPDFDictionaryRef?
            var xobjects: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources), let resources,
                  CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { continue }

            var streams: [CGPDFStreamRef] = []
            CGPDFDictionaryApplyBlock(xobjects, { _, object, _ in
                var stream: CGPDFStreamRef?
                if CGPDFObjectGetValue(object, .stream, &stream), let stream { streams.append(stream) }
                return true
            }, nil)

            for stream in streams where out.count < limit {
                guard let image = image(from: stream), let jpeg = jpegData(image) else { continue }
                guard seen.insert(digest(jpeg)).inserted else { continue }
                out.append(NoteAttachment(kind: .image, role: .figure,
                                          name: "\(name) · page \(pageNumber) picture",
                                          mediaType: "image/jpeg", data: jpeg))
            }
        }
        return out
    }

    private static func image(from stream: CGPDFStreamRef) -> CGImage? {
        guard let dict = CGPDFStreamGetDictionary(stream) else { return nil }
        var subtype: UnsafePointer<Int8>?
        guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image" else { return nil }
        var width: CGPDFInteger = 0, height: CGPDFInteger = 0, bpc: CGPDFInteger = 8
        CGPDFDictionaryGetInteger(dict, "Width", &width)
        CGPDFDictionaryGetInteger(dict, "Height", &height)
        CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bpc)
        guard width >= minSide, height >= minSide else { return nil }

        var format = CGPDFDataFormat.raw
        guard let cfData = CGPDFStreamCopyData(stream, &format) else { return nil }
        let data = cfData as Data
        switch format {
        case .jpegEncoded, .JPEG2000:
            return cgImage(from: data)
        case .raw:
            // Uncompressed pixels: only plain 8-bit RGB or grayscale is rebuilt.
            var colorSpaceName: UnsafePointer<Int8>?
            CGPDFDictionaryGetName(dict, "ColorSpace", &colorSpaceName)
            let name = colorSpaceName.map { String(cString: $0) } ?? ""
            let components = name == "DeviceGray" ? 1 : name == "DeviceRGB" ? 3 : 0
            guard bpc == 8, components > 0, data.count >= width * height * components,
                  let provider = CGDataProvider(data: data as CFData) else { return nil }
            let space = components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * components,
                           bytesPerRow: width * components, space: space, bitmapInfo: CGBitmapInfo(rawValue: 0),
                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        @unknown default:
            return nil
        }
    }

    // MARK: Image helpers

    /// Full-content fingerprint, to skip the same picture used twice.
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width >= minSide, image.height >= minSide else { return nil }
        return image
    }

    /// Downscales to Claude's working size and encodes as JPEG on a white background.
    public static func jpegData(_ image: CGImage, quality: CGFloat = 0.85) -> Data? {
        let scale = min(1, maxSide / CGFloat(max(image.width, image.height)))
        let w = max(1, Int(CGFloat(image.width) * scale)), h = max(1, Int(CGFloat(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    // MARK: Zip / XML helpers

    static func unzip(_ url: URL) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studysprint-unzip-\(UUID().uuidString)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", dir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// "image2.png" sorts before "image10.png".
    static func naturalOrder(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }

    static func xmlText(_ xml: String, tag: String) -> [String] {
        var out: [String] = []
        var rest = xml[...]
        while let open = rest.range(of: "<\(tag)>") ?? rest.range(of: "<\(tag) ") {
            guard let close = rest.range(of: "</\(tag)>", range: open.upperBound..<rest.endIndex) else { break }
            var inner = rest[open.upperBound..<close.lowerBound]
            if open.upperBound > open.lowerBound, rest[open].hasSuffix(" "), let gt = inner.firstIndex(of: ">") {
                inner = inner[inner.index(after: gt)...]
            }
            let text = String(inner)
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
            if !text.isEmpty { out.append(text) }
            rest = rest[close.upperBound...]
        }
        return out
    }
}
#endif
