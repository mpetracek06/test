import Foundation

// MARK: - Request options

public enum TimeBudget: Int, CaseIterable, Identifiable, Codable, Sendable {
    case fifteenMin = 15, thirtyMin = 30, oneHour = 60, twoHours = 120, fourHours = 240, oneDay = 480

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .fifteenMin: return "15 min"
        case .thirtyMin: return "30 min"
        case .oneHour: return "1 hr"
        case .twoHours: return "2 hr"
        case .fourHours: return "4 hr"
        case .oneDay: return "1 day"
        }
    }
}

public enum StartingLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case newToIt = "Totally new"
    case someBackground = "Some background"
    case reviewing = "Reviewing / cramming"
    public var id: String { rawValue }
}

public enum LearningGoal: String, CaseIterable, Identifiable, Codable, Sendable {
    case passExam = "Pass an exam"
    case understand = "Actually understand it"
    case apply = "Use it in practice"
    public var id: String { rawValue }
}

/// How hard Claude works on research. Faster = fewer searches and less thinking.
public enum ResearchDepth: String, CaseIterable, Identifiable, Codable, Sendable {
    case quick = "Quick"
    case balanced = "Balanced"
    case deep = "Deep"
    public var id: String { rawValue }

    public var effort: String {
        switch self {
        case .quick: return "low"
        case .balanced: return "medium"
        case .deep: return "high"
        }
    }

    public var maxSearches: Int {
        switch self {
        case .quick: return 5
        case .balanced: return 10
        case .deep: return 18
        }
    }

    public var blurb: String {
        switch self {
        case .quick: return "~1 min · fewer searches"
        case .balanced: return "~2 min · best default"
        case .deep: return "~4 min · most thorough"
        }
    }
}

/// A photo of handwritten notes or a scanned PDF, sent to Claude as-is (Claude reads images and PDFs).
public struct NoteAttachment: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case image, pdf }
    /// A figure is a picture from the notes that the guide shows and explains.
    /// A page is a photo or scan of the notes themselves, which is read but not shown.
    public enum Role: String, Sendable { case figure, page }
    public var id = UUID()
    public var kind: Kind
    public var role: Role
    public var name: String
    public var mediaType: String
    public var data: Data

    public init(kind: Kind, role: Role = .figure, name: String, mediaType: String, data: Data) {
        self.kind = kind
        self.role = kind == .pdf ? .page : role
        self.name = name
        self.mediaType = mediaType
        self.data = data
    }

    public var isFigure: Bool { kind == .image && role == .figure }

    /// The Messages API content block for this attachment.
    public var contentBlock: JSON {
        let source: JSON = ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]
        return ["type": kind == .image ? "image" : "document", "source": source]
    }
}

public struct GuideRequest: Sendable {
    public var notes: String
    public var attachments: [NoteAttachment] = []
    public var topicHint: String
    public var budget: TimeBudget
    public var level: StartingLevel
    public var goal: LearningGoal
    public var depth: ResearchDepth

    public init(notes: String, topicHint: String = "", budget: TimeBudget = .oneHour,
                level: StartingLevel = .newToIt, goal: LearningGoal = .passExam, depth: ResearchDepth = .balanced) {
        self.notes = notes
        self.topicHint = topicHint
        self.budget = budget
        self.level = level
        self.goal = goal
        self.depth = depth
    }

    public var isEmpty: Bool {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}

// MARK: - Guide

public struct VideoResource: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var url: String
    public var channel: String
    public var duration: String
    /// Human-readable advice, e.g. "Skip the intro; the key idea is at 3:10".
    public var watchTip: String
    public var startSeconds: Int
    /// 0 means "to the end".
    public var endSeconds: Int
    public var playbackSpeed: Double
    /// True when the URL appeared in Claude's live web-search results.
    public var verified: Bool

    public init(title: String, url: String, channel: String, duration: String, watchTip: String,
                startSeconds: Int = 0, endSeconds: Int = 0, playbackSpeed: Double = 1.0, verified: Bool) {
        self.title = title
        self.url = url
        self.channel = channel
        self.duration = duration
        self.watchTip = watchTip
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.playbackSpeed = playbackSpeed
        self.verified = verified
    }

    public var youTubeID: String? { verified ? YouTube.videoID(from: url) : nil }
}

public enum StepStatus: String, Codable, Sendable {
    case notStarted, done, testedOut

    public var isComplete: Bool { self != .notStarted }
}

public struct TestOut: Codable, Hashable, Sendable {
    public var question: String
    public var answer: String
    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

public struct StudyStep: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var minutes: Int
    public var why: String
    public var explanation: String
    public var analogy: String
    public var keyPoints: [String]
    public var videos: [VideoResource]
    public var activeRecall: [String]
    public var testOut: TestOut?
    /// 1-based numbers of earlier steps this one builds on.
    public var prerequisites: [Int]
    public var status: StepStatus = .notStarted

    public init(title: String, minutes: Int, why: String, explanation: String, analogy: String = "",
                keyPoints: [String] = [], videos: [VideoResource] = [], activeRecall: [String] = [],
                testOut: TestOut? = nil, prerequisites: [Int] = [], status: StepStatus = .notStarted) {
        self.title = title
        self.minutes = minutes
        self.why = why
        self.explanation = explanation
        self.analogy = analogy
        self.keyPoints = keyPoints
        self.videos = videos
        self.activeRecall = activeRecall
        self.testOut = testOut
        self.prerequisites = prerequisites
        self.status = status
    }
}

public struct Flashcard: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var front: String
    public var back: String
    public var review = ReviewState()

    public init(front: String, back: String, review: ReviewState = ReviewState()) {
        self.front = front
        self.back = back
        self.review = review
    }
}

public struct ChatTurn: Codable, Hashable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var id = UUID()
    public var role: Role
    /// What the app shows.
    public var text: String
    /// The assistant's exact content blocks (JSON), sent back unchanged on the next turn.
    public var rawContent: Data?
    public var date = Date()

    public init(role: Role, text: String, rawContent: Data? = nil) {
        self.role = role
        self.text = text
        self.rawContent = rawContent
    }
}

public struct QuizQuestion: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var question: String
    public var choices: [String]
    public var correctIndex: Int
    public var explanation: String
    public var stepNumber: Int

    public init(question: String, choices: [String], correctIndex: Int, explanation: String, stepNumber: Int) {
        self.question = question
        self.choices = choices
        self.correctIndex = correctIndex
        self.explanation = explanation
        self.stepNumber = stepNumber
    }
}

public struct QuizAttempt: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var score: Int
    public var total: Int
    public var missedSteps: [Int]

    public init(score: Int, total: Int, missedSteps: [Int]) {
        self.score = score
        self.total = total
        self.missedSteps = missedSteps
    }
}

public struct FeynmanResult: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var concept: String
    public var explanation: String
    public var score: Int
    public var verdict: String
    public var nailed: [String]
    public var gaps: [String]
    public var misconceptions: [String]
    public var improvedExplanation: String
    public var followUpQuestion: String

    public init(concept: String, explanation: String, score: Int, verdict: String, nailed: [String],
                gaps: [String], misconceptions: [String], improvedExplanation: String, followUpQuestion: String) {
        self.concept = concept
        self.explanation = explanation
        self.score = score
        self.verdict = verdict
        self.nailed = nailed
        self.gaps = gaps
        self.misconceptions = misconceptions
        self.improvedExplanation = improvedExplanation
        self.followUpQuestion = followUpQuestion
    }
}

/// A picture from the learner's notes, shown in the guide with an explanation.
/// The image itself is stored by the app as a file named `fileName`.
public struct GuideFigure: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var fileName: String
    public var title: String
    public var explanation: String
    public var notice: [String]
    /// 1-based step it belongs to; 0 = the whole topic.
    public var stepNumber: Int
    /// Index among the request's figure attachments (used once, to save the image).
    public var sourceIndex: Int

    public init(title: String, explanation: String, notice: [String], stepNumber: Int, sourceIndex: Int) {
        self.title = title
        self.explanation = explanation
        self.notice = notice
        self.stepNumber = stepNumber
        self.sourceIndex = sourceIndex
        let newID = UUID()
        self.id = newID
        self.fileName = "\(newID.uuidString).jpg"
    }
}

public struct StudyGuide: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var createdAt = Date()
    public var topic: String
    public var emoji: String
    public var timeBudgetMinutes: Int
    public var tldr: String
    public var paretoConcepts: [String]
    public var steps: [StudyStep]
    public var flashcards: [Flashcard]
    public var commonMistakes: [String]
    public var skipList: [String]
    public var mnemonics: [String]
    public var selfTest: [String]
    public var sourceNotes: String
    public var sources: [SearchHit]
    public var figures: [GuideFigure] = []

    // Learning history
    public var tutorTurns: [ChatTurn] = []
    /// Frozen tutor system prompt so the conversation's prefix never changes.
    public var tutorSystem: String?
    public var quizAttempts: [QuizAttempt] = []
    public var feynmanResults: [FeynmanResult] = []
    public var minutesStudied: Double = 0
    /// Approximate API cost of building this guide, in US dollars.
    public var buildCost: Double?

    public init(topic: String, emoji: String = "📘", timeBudgetMinutes: Int, tldr: String,
                paretoConcepts: [String], steps: [StudyStep], flashcards: [Flashcard],
                commonMistakes: [String], skipList: [String], mnemonics: [String] = [],
                selfTest: [String], sourceNotes: String, sources: [SearchHit] = []) {
        self.topic = topic
        self.emoji = emoji
        self.timeBudgetMinutes = timeBudgetMinutes
        self.tldr = tldr
        self.paretoConcepts = paretoConcepts
        self.steps = steps
        self.flashcards = flashcards
        self.commonMistakes = commonMistakes
        self.skipList = skipList
        self.mnemonics = mnemonics
        self.selfTest = selfTest
        self.sourceNotes = sourceNotes
        self.sources = sources
    }

    public var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }
    public var completedSteps: Int { steps.filter { $0.status.isComplete }.count }
    public var progress: Double {
        steps.isEmpty ? 0 : Double(completedSteps) / Double(steps.count)
    }
    public var nextStepIndex: Int? { steps.firstIndex { !$0.status.isComplete } }
    public var remainingMinutes: Int {
        steps.filter { !$0.status.isComplete }.reduce(0) { $0 + $1.minutes }
    }
    /// Figures for a 1-based step number (0 = general).
    public func figures(forStep number: Int) -> [GuideFigure] {
        figures.filter { $0.stepNumber == number }
    }

    public func dueCards(at date: Date = Date()) -> [Flashcard] {
        flashcards.filter { $0.review.due <= date }
    }
}

public struct SearchHit: Codable, Hashable, Identifiable, Sendable {
    public var id: String { url }
    public var title: String
    public var url: String
    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
    public var isVideo: Bool { YouTube.videoID(from: url) != nil }
}

// MARK: - Tolerant decoding
// Decoding fills in defaults for any missing field, so guides saved by older
// versions of the app keep loading as new fields are added.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }
}

extension VideoResource {
    enum CodingKeys: String, CodingKey {
        case id, title, url, channel, duration, watchTip, startSeconds, endSeconds, playbackSpeed, verified
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: c.value(.title, ""), url: c.value(.url, ""), channel: c.value(.channel, ""),
                  duration: c.value(.duration, ""), watchTip: c.value(.watchTip, ""),
                  startSeconds: c.value(.startSeconds, 0), endSeconds: c.value(.endSeconds, 0),
                  playbackSpeed: c.value(.playbackSpeed, 1.0), verified: c.value(.verified, false))
        id = c.value(.id, UUID())
    }
}

extension StudyStep {
    enum CodingKeys: String, CodingKey {
        case id, title, minutes, why, explanation, analogy, keyPoints, videos, activeRecall, testOut,
             prerequisites, status, done
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyDone: Bool = c.value(.done, false)
        self.init(title: c.value(.title, ""), minutes: c.value(.minutes, 10), why: c.value(.why, ""),
                  explanation: c.value(.explanation, ""), analogy: c.value(.analogy, ""),
                  keyPoints: c.value(.keyPoints, []), videos: c.value(.videos, []),
                  activeRecall: c.value(.activeRecall, []), testOut: c.value(.testOut, nil),
                  prerequisites: c.value(.prerequisites, []),
                  status: c.value(.status, legacyDone ? .done : .notStarted))
        id = c.value(.id, UUID())
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(why, forKey: .why)
        try c.encode(explanation, forKey: .explanation)
        try c.encode(analogy, forKey: .analogy)
        try c.encode(keyPoints, forKey: .keyPoints)
        try c.encode(videos, forKey: .videos)
        try c.encode(activeRecall, forKey: .activeRecall)
        try c.encodeIfPresent(testOut, forKey: .testOut)
        try c.encode(prerequisites, forKey: .prerequisites)
        try c.encode(status, forKey: .status)
    }
}

extension Flashcard {
    enum CodingKeys: String, CodingKey { case id, front, back, review }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(front: c.value(.front, ""), back: c.value(.back, ""), review: c.value(.review, ReviewState()))
        id = c.value(.id, UUID())
    }
}

extension StudyGuide {
    enum CodingKeys: String, CodingKey {
        case id, createdAt, topic, emoji, timeBudgetMinutes, tldr, paretoConcepts, steps, flashcards,
             commonMistakes, skipList, mnemonics, selfTest, sourceNotes, sources, tutorTurns, tutorSystem,
             quizAttempts, feynmanResults, minutesStudied, buildCost, figures
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(topic: c.value(.topic, "Untitled"), emoji: c.value(.emoji, "📘"),
                  timeBudgetMinutes: c.value(.timeBudgetMinutes, 60), tldr: c.value(.tldr, ""),
                  paretoConcepts: c.value(.paretoConcepts, []), steps: c.value(.steps, []),
                  flashcards: c.value(.flashcards, []), commonMistakes: c.value(.commonMistakes, []),
                  skipList: c.value(.skipList, []), mnemonics: c.value(.mnemonics, []),
                  selfTest: c.value(.selfTest, []), sourceNotes: c.value(.sourceNotes, ""),
                  sources: c.value(.sources, []))
        id = c.value(.id, UUID())
        createdAt = c.value(.createdAt, Date())
        tutorTurns = c.value(.tutorTurns, [])
        tutorSystem = c.value(.tutorSystem, nil)
        quizAttempts = c.value(.quizAttempts, [])
        feynmanResults = c.value(.feynmanResults, [])
        minutesStudied = c.value(.minutesStudied, 0)
        buildCost = c.value(.buildCost, nil)
        figures = c.value(.figures, [])
    }
}
