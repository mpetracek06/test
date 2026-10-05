import Foundation
#if canImport(CoreGraphics)
import CoreGraphics

/// Finds the pictures and drawn diagrams on PDF pages and renders each one exactly as it
/// appears. Reading the page's drawing instructions (rather than decoding image data) means
/// every kind of embedded image works, including images nested in groups, and diagrams
/// drawn from shapes are found too.
public enum PDFFigureFinder {
    struct Mark {
        var rect: CGRect
        var isImage: Bool
        /// Drawn only with horizontal/vertical lines and rectangles (table grids, boxes, rules).
        var boxy = false
    }

    struct Region {
        var rect: CGRect
        var images = 0
        var shapes = 0
        /// Shapes with curves or slanted lines: arrows, circles, plotted lines.
        var drawn = 0
    }

    /// Rendered figures from the PDF, top to bottom on each page.
    public static func figures(in data: Data, name: String, limit: Int = FigureExtractor.maxFigures,
                               perPage: Int = 4) -> [NoteAttachment] {
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider),
              doc.numberOfPages > 0 else { return [] }
        var out: [NoteAttachment] = []
        var seen = Set<String>()
        for number in 1...doc.numberOfPages where out.count < limit {
            guard let page = doc.page(at: number) else { continue }
            let box = page.getBoxRect(.mediaBox)
            let regions = figureRegions(marks: scan(page), page: box)
            for region in regions.prefix(perPage) where out.count < limit {
                guard let image = render(page, rect: region), let jpeg = FigureExtractor.jpegData(image),
                      seen.insert(FigureExtractor.digest(jpeg)).inserted else { continue }
                out.append(NoteAttachment(kind: .image, role: .figure,
                                          name: "\(name) · page \(number) figure",
                                          mediaType: "image/jpeg", data: jpeg))
            }
        }
        return out
    }

    // MARK: Finding regions

    /// Groups nearby drawing into figures and drops page furniture (backgrounds, rules, callout boxes).
    static func figureRegions(marks: [Mark], page: CGRect) -> [CGRect] {
        let pageArea = page.width * page.height
        let useful = marks.filter { m in
            let r = m.rect
            guard r.width > 0.5 || r.height > 0.5 else { return false }
            // Full-page backgrounds aren't figures (a full-page *image* still can be).
            if !m.isImage && r.width * r.height > 0.85 * pageArea { return false }
            return true
        }

        var regions = useful.map {
            Region(rect: $0.rect, images: $0.isImage ? 1 : 0, shapes: $0.isImage ? 0 : 1,
                   drawn: !$0.isImage && !$0.boxy ? 1 : 0)
        }
        // Merge anything within `gap` points of each other until nothing changes.
        let gap: CGFloat = 14
        var merged = true
        while merged {
            merged = false
            outer: for i in regions.indices {
                for j in regions.indices where j > i {
                    if regions[i].rect.insetBy(dx: -gap, dy: -gap).intersects(regions[j].rect) {
                        regions[i].rect = regions[i].rect.union(regions[j].rect)
                        regions[i].images += regions[j].images
                        regions[i].shapes += regions[j].shapes
                        regions[i].drawn += regions[j].drawn
                        regions.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }

        return regions
            .filter { r in
                let w = r.rect.width, h = r.rect.height
                if r.images > 0 { return w >= 50 && h >= 50 }
                // Drawn diagrams: several shapes including some curves or slanted lines (arrows),
                // a real size, not the whole page. Grids of straight lines are tables, whose text
                // is already in the notes.
                return r.shapes >= 4 && r.drawn >= 1 && w >= 100 && h >= 60 && w * h < 0.9 * pageArea
            }
            .map { $0.rect.insetBy(dx: -8, dy: -8).intersection(page) }
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
            .sorted { $0.maxY > $1.maxY } // PDF y grows upward: top of the page first
    }

    // MARK: Rendering

    static func render(_ page: CGPDFPage, rect: CGRect) -> CGImage? {
        let scale = min(4, max(1, 1400 / max(rect.width, rect.height)))
        let w = Int(rect.width * scale), h = Int(rect.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    // MARK: Scanning the page's drawing instructions

    final class ScanState {
        var ctm: [CGAffineTransform] = [.identity]
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        var marks: [Mark] = []
        var depth = 0
        var last: CGPoint?
        var slanted = false
        var table: CGPDFOperatorTableRef?

        var current: CGAffineTransform {
            get { ctm[ctm.count - 1] }
            set { ctm[ctm.count - 1] = newValue }
        }

        func move(_ x: CGFloat, _ y: CGFloat) {
            add(x, y)
            last = CGPoint(x: x, y: y).applying(current)
        }

        func line(_ x: CGFloat, _ y: CGFloat) {
            let p = CGPoint(x: x, y: y).applying(current)
            if let last, abs(p.x - last.x) > 0.5 && abs(p.y - last.y) > 0.5 { slanted = true }
            add(x, y)
            last = p
        }

        func curve(_ points: [CGFloat]) {
            slanted = true
            for i in stride(from: 0, to: points.count - 1, by: 2) { add(points[i], points[i + 1]) }
            last = CGPoint(x: points[points.count - 2], y: points[points.count - 1]).applying(current)
        }

        func add(_ x: CGFloat, _ y: CGFloat) {
            let p = CGPoint(x: x, y: y).applying(current)
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }

        func endPath(paint: Bool) {
            if paint && minX <= maxX {
                marks.append(Mark(rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                                  isImage: false, boxy: !slanted))
            }
            minX = .infinity; minY = .infinity; maxX = -.infinity; maxY = -.infinity
            slanted = false
            last = nil
        }

        func addImage() {
            let r = CGRect(x: 0, y: 0, width: 1, height: 1).applying(current)
            marks.append(Mark(rect: r, isImage: true))
        }
    }

    static func scan(_ page: CGPDFPage) -> [Mark] {
        let state = ScanState()
        guard let table = makeTable() else { return [] }
        state.table = table
        defer { CGPDFOperatorTableRelease(table) }
        let content = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(content) }
        let info = Unmanaged.passUnretained(state).toOpaque()
        let scanner = CGPDFScannerCreate(content, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        return state.marks
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> ScanState? {
        info.map { Unmanaged<ScanState>.fromOpaque($0).takeUnretainedValue() }
    }

    /// Pops `count` numbers; returned in the order they appear in the PDF.
    private static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var out: [CGFloat] = []
        for _ in 0..<count {
            var v: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &v) else { return nil }
            out.append(CGFloat(v))
        }
        return out.reversed()
    }

    private static func makeTable() -> CGPDFOperatorTableRef? {
        guard let table = CGPDFOperatorTableCreate() else { return nil }

        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let s = PDFFigureFinder.state(info) else { return }
            s.ctm.append(s.current)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let s = PDFFigureFinder.state(info), s.ctm.count > 1 else { return }
            s.ctm.removeLast()
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let s = PDFFigureFinder.state(info), let n = PDFFigureFinder.numbers(scanner, 6) else { return }
            s.current = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]).concatenating(s.current)
        }

        // Path construction
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            guard let s = PDFFigureFinder.state(info), let n = PDFFigureFinder.numbers(scanner, 2) else { return }
            s.move(n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            guard let s = PDFFigureFinder.state(info), let n = PDFFigureFinder.numbers(scanner, 2) else { return }
            s.line(n[0], n[1])
        }
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            guard let s = PDFFigureFinder.state(info), let n = PDFFigureFinder.numbers(scanner, 6) else { return }
            s.curve(n)
        }
        for op in ["v", "y"] {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                guard let s = PDFFigureFinder.state(info), let n = PDFFigureFinder.numbers(scanner, 4) else { return }
                s.curve(n)
            }
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let s = PDFFigureFinder.state(info), let n = PDFFigureFinder.numbers(scanner, 4) else { return }
            s.add(n[0], n[1]); s.add(n[0] + n[2], n[1] + n[3])
        }

        // Painting ends a path (and makes it visible); "n" ends it invisibly (clipping).
        for op in ["S", "s", "f", "F", "f*", "B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in PDFFigureFinder.state(info)?.endPath(paint: true) }
        }
        CGPDFOperatorTableSetCallback(table, "n") { _, info in PDFFigureFinder.state(info)?.endPath(paint: false) }

        // Inline images
        CGPDFOperatorTableSetCallback(table, "EI") { _, info in PDFFigureFinder.state(info)?.addImage() }

        // XObjects: images, and groups ("forms") that are scanned recursively.
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            guard let s = PDFFigureFinder.state(info) else { return }
            var namePtr: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(scanner, &namePtr), let namePtr else { return }
            let content = CGPDFScannerGetContentStream(scanner)
            guard let object = CGPDFContentStreamGetResource(content, "XObject", namePtr) else { return }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream) else { return }
            var subtypePtr: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &subtypePtr), let subtypePtr else { return }

            switch String(cString: subtypePtr) {
            case "Image":
                s.addImage()
            case "Form" where s.depth < 6:
                var matrix = CGAffineTransform.identity
                var array: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(dict, "Matrix", &array), let array, CGPDFArrayGetCount(array) == 6 {
                    var v = [CGPDFReal](repeating: 0, count: 6)
                    for i in 0..<6 { CGPDFArrayGetNumber(array, i, &v[i]) }
                    matrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
                }
                var resources: CGPDFDictionaryRef?
                CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
                guard let table = s.table else { return }
                s.ctm.append(matrix.concatenating(s.current))
                s.depth += 1
                let formContent = CGPDFContentStreamCreateWithStream(stream, resources ?? dict, content)
                let formScanner = CGPDFScannerCreate(formContent, table, info)
                CGPDFScannerScan(formScanner)
                CGPDFScannerRelease(formScanner)
                CGPDFContentStreamRelease(formContent)
                s.depth -= 1
                s.ctm.removeLast()
            default:
                break
            }
        }
        return table
    }
}
#endif
