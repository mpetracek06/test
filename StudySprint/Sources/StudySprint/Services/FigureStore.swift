import AppKit
import StudySprintCore

/// Saves the pictures from people's notes as files next to their guides.
enum FigureStore {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("StudySprint/figures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let cache = NSCache<NSString, NSImage>()

    static func url(for figure: GuideFigure) -> URL {
        directory.appendingPathComponent(figure.fileName)
    }

    /// Writes each figure's picture, taken from the attachments the guide was built from.
    static func save(_ guide: StudyGuide, from attachments: [NoteAttachment]) {
        let pictures = attachments.filter(\.isFigure)
        for figure in guide.figures where pictures.indices.contains(figure.sourceIndex) {
            try? pictures[figure.sourceIndex].data.write(to: url(for: figure), options: .atomic)
        }
    }

    static func save(_ data: Data, for figure: GuideFigure) {
        try? data.write(to: url(for: figure), options: .atomic)
    }

    static func image(for figure: GuideFigure) -> NSImage? {
        let key = figure.fileName as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url(for: figure)) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func delete(_ figures: [GuideFigure]) {
        for f in figures { try? FileManager.default.removeItem(at: url(for: f)) }
    }
}
