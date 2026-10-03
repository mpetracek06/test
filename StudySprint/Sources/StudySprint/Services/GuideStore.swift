import Foundation

/// Persists generated guides (and your progress through them) to
/// ~/Library/Application Support/StudySprint/guides.json.
final class GuideStore: ObservableObject {
    @Published var guides: [StudyGuide] = []

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("StudySprint", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("guides.json")
    }()

    init() { load() }

    func add(_ guide: StudyGuide) {
        guides.insert(guide, at: 0)
        save()
    }

    func update(_ guide: StudyGuide) {
        guard let i = guides.firstIndex(where: { $0.id == guide.id }) else { return }
        guides[i] = guide
        save()
    }

    func delete(id: StudyGuide.ID) {
        guides.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guides = (try? decoder.decode([StudyGuide].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(guides) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
