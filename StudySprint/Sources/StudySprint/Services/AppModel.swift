import AppKit
import SwiftUI
import StudySprintCore

enum SidebarItem: Hashable {
    case newGuide
    case review
    case guide(UUID)
}

enum GuideTab: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case map = "Map"
    case tutor = "Tutor"
    case quiz = "Quiz"
    case feynman = "Explain It"
    case cards = "Cards"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .plan: return "list.bullet.rectangle"
        case .map: return "point.3.connected.trianglepath.dotted"
        case .tutor: return "bubble.left.and.text.bubble.right"
        case .quiz: return "checkmark.circle"
        case .feynman: return "person.wave.2"
        case .cards: return "rectangle.on.rectangle.angled"
        }
    }
}

enum SettingsKey {
    static let model = "model"
    static let depth = "defaultDepth"
    static let engine = "engine"
}

/// Which AI does the work.
enum EngineKind: String, CaseIterable, Identifiable {
    case free
    case plan
    case claude

    var id: String { rawValue }
    var title: String {
        switch self {
        case .free: return "Free — runs on your Mac"
        case .plan: return "Your Claude plan — uses plan usage, no API credit"
        case .claude: return "Claude API — pay per use"
        }
    }
    var shortTitle: String {
        switch self {
        case .free: return "Free (on your Mac)"
        case .plan: return "My Claude plan"
        case .claude: return "API key"
        }
    }
}

/// App-wide state: saved guides, study log, navigation, and the in-flight guide build.
final class AppModel: ObservableObject {
    @Published var guides: [StudyGuide] = []
    @Published var log = StudyLog()
    @Published var selection: SidebarItem? = .newGuide
    @Published var tab: GuideTab = .plan
    /// Set by other screens (e.g. the quiz) to start a tutor conversation.
    @Published var pendingTutorPrompt: String?
    @Published var hasAPIKey = KeychainStore.loadAPIKey()?.isEmpty == false
    @Published var engineKind: EngineKind {
        didSet { UserDefaults.standard.set(engineKind.rawValue, forKey: SettingsKey.engine) }
    }

    let generation = GenerationController()
    let ollama = OllamaManager()
    let claudeCode = ClaudeCodeManager()

    private let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("StudySprint", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var guidesURL: URL { directory.appendingPathComponent("guides.json") }
    private var logURL: URL { directory.appendingPathComponent("study-log.json") }
    private var pendingSave: DispatchWorkItem?

    /// CI sets this to launch straight into a screen with demo data, for screenshots.
    static let screenshotScreen = ProcessInfo.processInfo.environment["STUDYSPRINT_SCREEN"]
    /// When true nothing is written to disk.
    private var isEphemeral = false

    init() {
        // Free unless the person has chosen Claude (or already set up a Claude key).
        let saved = UserDefaults.standard.string(forKey: SettingsKey.engine).flatMap(EngineKind.init(rawValue:))
        engineKind = saved ?? (KeychainStore.loadAPIKey()?.isEmpty == false ? .claude : .free)
        generation.app = self
        // First launch: if Claude Code is already set up with a Claude plan, use that.
        if saved == nil && Self.screenshotScreen == nil {
            Task { @MainActor [weak self] in
                guard let self, await self.claudeCode.refresh(), self.engineKind == .free,
                      UserDefaults.standard.string(forKey: SettingsKey.engine) == nil else { return }
                self.engineKind = .plan
            }
        }
        if let screen = Self.screenshotScreen {
            setUpScreenshot(screen)
        } else {
            load()
        }
    }

    /// Adds the built-in sample sprint so people can explore without an API key.
    func loadDemo() {
        let demo = DemoContent.guide()
        add(demo)
        open(demo.id)
    }

    // MARK: Clients

    var modelID: String {
        UserDefaults.standard.string(forKey: SettingsKey.model) ?? ClaudeModel.opus.rawValue
    }

    var client: AnthropicClient {
        AnthropicClient(apiKey: KeychainStore.loadAPIKey() ?? "", model: modelID)
    }

    /// The engine everything uses: Claude, or the free local model.
    var engine: StudyEngine {
        switch engineKind {
        case .claude: return LearningServices(client: client)
        case .plan: return ClaudeCodeEngine(runner: claudeCode.runner)
        case .free: return LocalEngine(backend: ollama.client)
        }
    }

    var services: StudyEngine { engine }

    /// Ready to build guides with the current engine.
    var engineReady: Bool {
        switch engineKind {
        case .claude: return hasAPIKey
        case .plan: return claudeCode.isReady
        case .free: return ollama.isReady
        }
    }

    var engineLabel: String {
        switch engineKind {
        case .claude: return ClaudeModel(rawValue: modelID)?.label.components(separatedBy: " — ").first ?? modelID
        case .plan: return "Claude \(claudeCode.model.rawValue.capitalized) · your Claude plan"
        case .free: return "Free · \(ollama.selectedModel) on your Mac"
        }
    }

    func saveAPIKey(_ key: String) -> Bool {
        let ok = KeychainStore.saveAPIKey(key)
        hasAPIKey = KeychainStore.loadAPIKey()?.isEmpty == false
        return ok
    }

    // MARK: Guides

    func guide(_ id: UUID) -> StudyGuide? { guides.first { $0.id == id } }

    func binding(for id: UUID) -> Binding<StudyGuide>? {
        guard let current = guide(id) else { return nil }
        return Binding(
            get: { [weak self] in self?.guide(id) ?? current },
            set: { [weak self] in self?.update($0) }
        )
    }

    func add(_ guide: StudyGuide) {
        guides.insert(guide, at: 0)
        scheduleSave()
    }

    func update(_ guide: StudyGuide) {
        guard let i = guides.firstIndex(where: { $0.id == guide.id }) else { return }
        guides[i] = guide
        scheduleSave()
    }

    func delete(_ id: UUID) {
        if selection == .guide(id) { selection = .newGuide }
        guides.removeAll { $0.id == id }
        scheduleSave()
    }

    func open(_ id: UUID, tab: GuideTab = .plan) {
        self.tab = tab
        selection = .guide(id)
    }

    // MARK: Spaced repetition

    struct DueCard: Identifiable, Hashable {
        var guideID: UUID
        var card: Flashcard
        var id: UUID { card.id }
    }

    func dueCards(in guideID: UUID? = nil, at date: Date = Date()) -> [DueCard] {
        guides
            .filter { guideID == nil || $0.id == guideID }
            .flatMap { g in g.dueCards(at: date).map { DueCard(guideID: g.id, card: $0) } }
            .sorted { $0.card.review.due < $1.card.review.due }
    }

    var dueCount: Int { dueCards().count }

    func card(_ guideID: UUID, _ cardID: UUID) -> Flashcard? {
        guide(guideID)?.flashcards.first { $0.id == cardID }
    }

    func grade(guideID: UUID, cardID: UUID, grade: ReviewGrade) {
        guard var g = guide(guideID), let i = g.flashcards.firstIndex(where: { $0.id == cardID }) else { return }
        g.flashcards[i].review = Scheduler.schedule(g.flashcards[i].review, grade: grade)
        update(g)
        log.record()
        scheduleSave()
    }

    var nextDueDate: Date? {
        guides.flatMap(\.flashcards).map(\.review.due).filter { $0 > Date() }.min()
    }

    func recordStudy(guideID: UUID, minutes: Double) {
        guard minutes > 0.2, var g = guide(guideID) else { return }
        g.minutesStudied += minutes
        update(g)
        log.recordStudy()
        scheduleSave()
    }

    // MARK: Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: guidesURL) {
            guides = (try? decoder.decode([StudyGuide].self, from: data)) ?? []
        } else if let legacy = try? Data(contentsOf: directory.appendingPathComponent("guides.json.v1")) {
            guides = (try? decoder.decode([StudyGuide].self, from: legacy)) ?? []
        }
        if let data = try? Data(contentsOf: logURL) {
            log = (try? decoder.decode(StudyLog.self, from: data)) ?? StudyLog()
        }
    }

    private func scheduleSave() {
        guard !isEphemeral else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        guard !isEphemeral else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(guides) { try? data.write(to: guidesURL, options: .atomic) }
        if let data = try? encoder.encode(log) { try? data.write(to: logURL, options: .atomic) }
    }

    private func setUpScreenshot(_ screen: String) {
        isEphemeral = true
        hasAPIKey = true
        engineKind = screen == "setup" ? .free : screen == "plansetup" ? .plan : .claude
        var g = DemoContent.guide()
        g.steps[0].status = .done
        g.steps[1].status = .testedOut
        g.minutesStudied = 23
        g.tutorTurns = [
            ChatTurn(role: .user, text: "Why does oxygen matter so much? Glycolysis doesn't even use it."),
            ChatTurn(role: .assistant, text: "Great question — oxygen matters because it's the **last stop** for electrons.\n\nThe electron transport chain is like a bucket brigade: each protein passes electrons down the line, and that flow pumps the H⁺ that drives ATP synthase. Oxygen is the person at the end who takes the bucket. **No oxygen → nobody takes the last bucket → the whole line stops**, and ~90% of your ATP production stops with it.\n\nGlycolysis can keep going without O₂ (via fermentation), but it only makes **2 ATP** per glucose instead of ~30.\n\n**Quick check:** if the chain stops, what happens to the NADH made in glycolysis?"),
        ]
        g.quizAttempts = [QuizAttempt(score: 5, total: 8, missedSteps: [3, 4]),
                          QuizAttempt(score: 7, total: 8, missedSteps: [4]),
                          QuizAttempt(score: 8, total: 8, missedSteps: [])]
        g.feynmanResults = [FeynmanResult(
            concept: "Electron transport chain & chemiosmosis",
            explanation: "Electrons from NADH go down a chain of proteins in the mitochondria and that makes energy. Oxygen is at the end and makes water. The energy is used to make ATP.",
            score: 72,
            verdict: "You've got the flow of electrons and oxygen's role, but you skipped the **proton gradient** — the actual mechanism that makes ATP.",
            nailed: ["Electrons come from NADH", "Oxygen is the final acceptor and forms water"],
            gaps: ["How electron flow pumps H⁺ across the inner membrane", "ATP synthase is driven by H⁺ flowing back"],
            misconceptions: ["The chain doesn't 'make energy' — it converts it into a proton gradient"],
            improvedExplanation: "NADH hands its electrons to a chain of proteins in the inner mitochondrial membrane. As electrons pass along, the proteins pump H⁺ to one side, like pumping water up behind a dam. The H⁺ rushes back through ATP synthase — a tiny turbine — which makes ATP. Oxygen catches the used electrons at the end, forming water.",
            followUpQuestion: "What would happen to ATP production if the inner membrane became leaky to H⁺?")]
        for i in g.flashcards.indices where i % 3 == 0 {
            g.flashcards[i].review = Scheduler.schedule(ReviewState(), grade: .good, now: Date().addingTimeInterval(-86_400 * 2))
        }
        var second = DemoContent.guide()
        second.topic = "Big-O Notation"
        second.emoji = "📈"
        for i in second.steps.indices { second.steps[i].status = .done }
        guides = [g, second]
        for d in 0..<6 { log.record(review: Date().addingTimeInterval(-86_400 * Double(d))) }

        switch screen {
        case "new", "setup", "plansetup": selection = .newGuide
        case "research":
            selection = .newGuide
            generation.simulateForScreenshot()
        case "review": selection = .review
        default:
            selection = .guide(g.id)
            tab = screen == "quizq" ? .quiz
                : GuideTab.allCases.first { $0.rawValue.lowercased().hasPrefix(screen) } ?? (screen == "feynman" ? .feynman : .plan)
        }
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([guidesURL])
    }
}

// MARK: - Guide building (lives outside any view so it survives navigation)

struct ResearchLogItem: Identifiable, Hashable {
    enum Kind { case phase, search, found, note, fallback }
    let id = UUID()
    var kind: Kind
    var text: String
    var hits: [SearchHit] = []
    var date = Date()
}

final class GenerationController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var phase = ""
    @Published private(set) var items: [ResearchLogItem] = []
    @Published private(set) var sources: [SearchHit] = []
    @Published private(set) var searches = 0
    @Published private(set) var characters = 0
    @Published private(set) var startedAt = Date()
    @Published var error: String?

    weak var app: AppModel?
    private var task: Task<Void, Never>?

    var videoCount: Int { sources.filter(\.isVideo).count }

    func start(_ request: GuideRequest) {
        guard !isRunning, let app else { return }
        isRunning = true
        error = nil
        items = []
        sources = []
        searches = 0
        characters = 0
        phase = "Starting…"
        startedAt = Date()
        let engine = app.engine
        var request = request
        if engine.isFree {
            // Local models read images, not PDFs: turn scanned pages into pictures.
            request.attachments = request.attachments.flatMap { a in
                a.kind == .pdf ? NotesImporter.pageImages(fromPDF: a.data, name: a.name) : [a]
            }
        }

        task = Task { @MainActor [weak self] in
            do {
                let guide = try await engine.generateGuide(request) { event in self?.apply(event) }
                guard let self, let app = self.app else { return }
                app.add(guide)
                app.open(guide.id)
                UserDefaults.standard.removeObject(forKey: "draftNotes")
                NSSound(named: "Glass")?.play()
            } catch is CancellationError {
                self?.error = nil
            } catch let urlError as URLError where urlError.code == .cancelled {
                self?.error = nil
            } catch {
                self?.error = error.localizedDescription
            }
            self?.isRunning = false
        }
    }

    /// Fills the live research screen with sample activity (screenshots only).
    func simulateForScreenshot() {
        isRunning = true
        startedAt = Date().addingTimeInterval(-74)
        phase = "Searching the web…"
        let found = [
            SearchHit(title: "Cellular Respiration Overview | Biology", url: "https://www.youtube.com/watch?v=sample1"),
            SearchHit(title: "Electron transport chain animation", url: "https://www.youtube.com/watch?v=sample2"),
            SearchHit(title: "Cellular respiration — Khan Academy", url: "https://www.khanacademy.org/science/biology"),
            SearchHit(title: "Krebs cycle summary — OpenStax Biology 2e", url: "https://openstax.org/books/biology-2e"),
        ]
        items = [
            ResearchLogItem(kind: .phase, text: "Reading your notes…"),
            ResearchLogItem(kind: .note, text: "Notes cover all four stages; the exam focus is locations, inputs/outputs, and oxygen's role."),
            ResearchLogItem(kind: .search, text: "cellular respiration explained visually"),
            ResearchLogItem(kind: .found, text: "10 results", hits: found),
            ResearchLogItem(kind: .search, text: "electron transport chain ATP synthase animation"),
            ResearchLogItem(kind: .found, text: "10 results", hits: Array(found.prefix(2))),
            ResearchLogItem(kind: .note, text: "Found a short animation for ATP synthase; looking for a tight Krebs cycle summary next."),
            ResearchLogItem(kind: .search, text: "krebs cycle summary short video"),
        ]
        sources = found + [SearchHit(title: "x", url: "https://example.com/1"), SearchHit(title: "y", url: "https://example.com/2")]
        searches = 3
        characters = 0
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    @MainActor
    private func apply(_ event: ResearchEvent) {
        switch event {
        case .phase(let p):
            phase = p
            items.append(ResearchLogItem(kind: .phase, text: p))
        case .searching(let q):
            searches += 1
            phase = "Searching the web…"
            items.append(ResearchLogItem(kind: .search, text: q))
        case .found(let hits):
            let new = hits.filter { h in !sources.contains { $0.url == h.url } }
            sources += new
            items.append(ResearchLogItem(kind: .found, text: "\(hits.count) results", hits: hits))
        case .note(let n):
            items.append(ResearchLogItem(kind: .note, text: n))
        case .fallback(let model):
            items.append(ResearchLogItem(kind: .fallback, text: "Continuing on \(model)"))
        case .writing(let count):
            characters = count
            phase = "Writing your study sprint…"
        }
    }
}
