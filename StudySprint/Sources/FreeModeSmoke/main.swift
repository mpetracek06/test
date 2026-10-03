import Foundation
import StudySprintCore

// Builds a real guide with a local model and free YouTube search, then runs a quiz.
// Usage: swift run free-mode-smoke <model>
let model = CommandLine.arguments.dropFirst().first ?? "gemma3:1b"
let notes = """
Photosynthesis: plants turn light, water and CO2 into glucose and O2.
Light-dependent reactions in the thylakoids make ATP and NADPH and split water (O2 released).
Calvin cycle in the stroma uses ATP/NADPH to fix CO2 into sugar (RuBisCO enzyme).
"""

@MainActor
func run() async throws {
    let client = OllamaClient(model: model, contextTokens: 8192)
    print("Ollama", try await client.version(), "· model", model)

    // 1. YouTube search on its own
    let videos = try await YouTubeSearch().search("photosynthesis explained", limit: 5)
    print("YouTube search returned \(videos.count) videos")
    for v in videos { print("  -", v.id, v.duration, v.title) }

    // 2. Full guide
    let engine = LocalEngine(backend: client)
    let start = Date()
    let guide = try await engine.generateGuide(GuideRequest(notes: notes, budget: .thirtyMin)) { event in
        switch event {
        case .phase(let p): print("[phase]", p)
        case .searching(let q): print("[search]", q)
        case .found(let hits): print("[found]", hits.count)
        default: break
        }
    }
    print(String(format: "Guide built in %.0fs: %@ %@", Date().timeIntervalSince(start), guide.emoji, guide.topic))
    print("Steps: \(guide.steps.count), flashcards: \(guide.flashcards.count), cost: \(guide.buildCost ?? -1)")
    for (i, s) in guide.steps.enumerated() {
        print("  \(i + 1). \(s.title) (\(s.minutes) min) videos: \(s.videos.map { "\($0.title) [\($0.duration)]" })")
    }
    guard !guide.steps.isEmpty else { throw APIError.unparseable }
    let videoCount = guide.steps.reduce(0) { $0 + $1.videos.count }
    print("Videos attached: \(videoCount)")

    // 3. Quiz + test-out grading
    let quiz = try await engine.makeQuiz(for: guide, count: 4)
    print("Quiz questions: \(quiz.count)")
    if let first = guide.steps.first, let testOut = first.testOut {
        let verdict = try await engine.gradeTestOut(stepTitle: first.title, testOut: testOut, answer: testOut.answer)
        print("Test-out verdict: passed=\(verdict.passed) — \(verdict.feedback)")
    }

    // 4. Tutor
    var reply = ""
    _ = try await engine.tutorReply(system: engine.tutorSystem(for: guide),
                                    history: [ChatTurn(role: .user, text: "In one sentence, what does the Calvin cycle do?")],
                                    onText: { reply += $0 }, onStatus: { _ in })
    print("Tutor:", reply.prefix(300))
    print("FREE MODE OK")
}

do {
    try await run()
} catch {
    print("FAILED:", error.localizedDescription, error)
    exit(1)
}
