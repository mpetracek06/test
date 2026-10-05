import CoreGraphics
import XCTest
@testable import StudySprintCore

final class MessageAccumulatorTests: XCTestCase {
    private func feed(_ events: [JSON], into acc: MessageAccumulator) throws -> [StreamUpdate] {
        try events.flatMap { try acc.handle($0) }
    }

    func testRebuildsTextSearchAndThinkingBlocks() throws {
        let acc = MessageAccumulator()
        let updates = try feed([
            ["type": "message_start", "message": ["model": "claude-opus-5-5", "usage": ["input_tokens": 10]]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": "", "signature": ""]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "thinking_delta", "thinking": "Looking for videos."]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "sig123"]],
            ["type": "content_block_stop", "index": 0],
            ["type": "content_block_start", "index": 1, "content_block": ["type": "server_tool_use", "id": "srv_1", "name": "web_search", "input": [:] as JSON]],
            ["type": "content_block_delta", "index": 1, "delta": ["type": "input_json_delta", "partial_json": "{\"query\": \"krebs"]],
            ["type": "content_block_delta", "index": 1, "delta": ["type": "input_json_delta", "partial_json": " cycle\"}"]],
            ["type": "content_block_stop", "index": 1],
            ["type": "content_block_start", "index": 2, "content_block": [
                "type": "web_search_tool_result", "tool_use_id": "srv_1",
                "content": [["type": "web_search_result", "url": "https://www.youtube.com/watch?v=abc123", "title": "Krebs"]],
            ] as JSON],
            ["type": "content_block_stop", "index": 2],
            ["type": "content_block_start", "index": 3, "content_block": ["type": "text", "text": ""]],
            ["type": "content_block_delta", "index": 3, "delta": ["type": "text_delta", "text": "Hello "]],
            ["type": "content_block_delta", "index": 3, "delta": ["type": "citations_delta", "citation": ["url": "x"]]],
            ["type": "content_block_delta", "index": 3, "delta": ["type": "text_delta", "text": "world"]],
            ["type": "content_block_stop", "index": 3],
            ["type": "message_delta", "delta": ["stop_reason": "end_turn"], "usage": ["output_tokens": 42]],
            ["type": "message_stop"],
        ], into: acc)

        XCTAssertTrue(acc.finished)
        let message = acc.message
        XCTAssertEqual(message.stopReason, "end_turn")
        XCTAssertEqual(message.text, "Hello world")
        XCTAssertEqual(message.content.count, 4)
        XCTAssertEqual(message.content[0]["signature"] as? String, "sig123")
        XCTAssertEqual((message.content[1]["input"] as? JSON)?["query"] as? String, "krebs cycle")
        XCTAssertEqual((message.content[3]["citations"] as? [Any])?.count, 1)
        XCTAssertEqual(message.searchHits.map(\.url), ["https://www.youtube.com/watch?v=abc123"])
        XCTAssertEqual(message.usage?["output_tokens"] as? Int, 42)
        XCTAssertEqual(message.usage?["input_tokens"] as? Int, 10)

        XCTAssertTrue(updates.contains(.started(model: "claude-opus-5-5")))
        XCTAssertTrue(updates.contains(.progressNote("Looking for videos.")))
        XCTAssertTrue(updates.contains(.searchQuery("krebs cycle")))
        XCTAssertTrue(updates.contains(.text("world")))
    }

    func testErrorEventThrows() {
        let acc = MessageAccumulator()
        XCTAssertThrowsError(try acc.handle(["type": "error", "error": ["type": "overloaded_error", "message": "busy"]])) { error in
            XCTAssertEqual(error as? APIError, .http(529, "busy"))
        }
    }

    func testEchoDropsDeclinedBlocksBeforeFallback() {
        let message = AssembledMessage(content: [
            ["type": "thinking", "thinking": "x", "signature": "s"],
            ["type": "server_tool_use", "id": "a", "name": "web_search"],
            ["type": "server_tool_use", "id": "b", "name": "web_search"],
            ["type": "web_search_tool_result", "tool_use_id": "b", "content": [] as [Any]],
            ["type": "text", "text": "partial"],
            ["type": "fallback", "from": ["model": "m1"], "to": ["model": "m2"]],
            ["type": "thinking", "thinking": "", "signature": "t"],
            ["type": "text", "text": "rest"],
        ])
        let types = message.contentForEcho.map { $0["type"] as? String ?? "" }
        XCTAssertEqual(types, ["server_tool_use", "web_search_tool_result", "text", "fallback", "thinking", "text"])
        XCTAssertEqual(message.contentForEcho[0]["id"] as? String, "b")
    }
}

final class GuideParsingTests: XCTestCase {
    let sample = """
    Here is your plan.
    <guide_json>
    {"topic": "Cell respiration", "emoji": "🧬", "tldr": "Cells burn glucose.",
     "paretoConcepts": ["ATP is energy currency"],
     "steps": [
       {"title": "Glycolysis", "minutes": 10, "why": "first", "explanation": "e", "analogy": "a",
        "keyPoints": ["k"], "activeRecall": ["q"],
        "videos": [
          {"title": "Real", "url": "https://youtu.be/abc123", "channel": "C", "duration": "5:00",
           "watchTip": "t", "startSeconds": 30, "endSeconds": 10, "playbackSpeed": 3},
          {"title": "Made up", "url": "https://www.youtube.com/watch?v=zzz999", "channel": "D", "duration": "1:00", "watchTip": ""}
        ],
        "testOut": {"question": "tq", "answer": "ta"}, "prerequisites": [5]},
       {"title": "Krebs", "minutes": 12.5, "why": "w", "explanation": "e", "prerequisites": [1, 1, 2]}
     ],
     "flashcards": [{"front": "f", "back": "b"}]}
    </guide_json>
    """

    func testDecodesAndSanitizes() throws {
        let payload = try XCTUnwrap(GuidePayload.decode(from: sample))
        let hits = [SearchHit(title: "Real", url: "https://www.youtube.com/watch?v=abc123")]
        let guide = payload.toGuide(request: GuideRequest(notes: "n"), searchHits: hits)

        XCTAssertEqual(guide.topic, "Cell respiration")
        XCTAssertEqual(guide.emoji, "🧬")
        XCTAssertEqual(guide.steps.count, 2)
        XCTAssertEqual(guide.steps[1].minutes, 12)

        let real = guide.steps[0].videos[0]
        XCTAssertTrue(real.verified)
        XCTAssertEqual(real.youTubeID, "abc123")
        XCTAssertEqual(real.startSeconds, 30)
        XCTAssertEqual(real.endSeconds, 0, "end before start means play to the end")
        XCTAssertEqual(real.playbackSpeed, 2.0)

        let fake = guide.steps[0].videos[1]
        XCTAssertFalse(fake.verified)
        XCTAssertTrue(fake.url.hasPrefix("https://www.youtube.com/results"))

        XCTAssertEqual(guide.steps[0].prerequisites, [], "prerequisites must point at earlier steps")
        XCTAssertEqual(guide.steps[1].prerequisites, [1])
        XCTAssertEqual(guide.steps[0].testOut?.question, "tq")
        XCTAssertEqual(guide.flashcards.count, 1)
    }

    func testDecodesUntaggedFencedJSON() {
        let text = "```json\n{\"steps\": [{\"title\": \"Only\"}]}\n```"
        XCTAssertEqual(GuidePayload.decode(from: text)?.steps.first?.title, "Only")
    }

    func testRejectsTextWithoutSteps() {
        XCTAssertNil(GuidePayload.decode(from: "{\"topic\": \"x\"}"))
        XCTAssertNil(GuidePayload.decode(from: "no json here"))
    }

    func testSchemaIsStrict() {
        let schema = GuidePayload.schema
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual((schema["required"] as? [String])?.contains("steps"), true)
    }

    func testYouTubeIDs() {
        XCTAssertEqual(YouTube.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTube.videoID(from: "https://youtu.be/dQw4w9WgXcQ?si=x"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTube.videoID(from: "https://m.youtube.com/shorts/abc"), "abc")
        XCTAssertEqual(YouTube.videoID(from: "https://www.youtube.com/embed/xyz"), "xyz")
        XCTAssertNil(YouTube.videoID(from: "https://www.youtube.com/results?search_query=x"))
        XCTAssertNil(YouTube.videoID(from: "https://notyoutube.com/watch?v=abc"))
        XCTAssertEqual(YouTube.timestamp(65), "1:05")
        XCTAssertEqual(YouTube.timestamp(3725), "1:02:05")
    }
}

final class SchedulingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNewCardProgression() {
        var s = ReviewState()
        XCTAssertTrue(s.isNew)
        s = Scheduler.schedule(s, grade: .good, now: now)
        XCTAssertEqual(s.intervalDays, 1)
        s = Scheduler.schedule(s, grade: .good, now: now)
        XCTAssertEqual(s.intervalDays, 3)
        s = Scheduler.schedule(s, grade: .good, now: now)
        XCTAssertEqual(s.intervalDays, 7.5, accuracy: 0.001)
        XCTAssertEqual(s.due, now.addingTimeInterval(7.5 * 86_400))
    }

    func testAgainResetsAndLowersEase() {
        var s = Scheduler.schedule(ReviewState(), grade: .good, now: now)
        s = Scheduler.schedule(s, grade: .again, now: now)
        XCTAssertEqual(s.reps, 0)
        XCTAssertEqual(s.lapses, 1)
        XCTAssertEqual(s.ease, 2.3, accuracy: 0.001)
        XCTAssertEqual(s.due.timeIntervalSince(now), 600, accuracy: 1)
    }

    func testEaseNeverDropsBelowFloor() {
        var s = ReviewState()
        for _ in 0..<20 { s = Scheduler.schedule(s, grade: .again, now: now) }
        XCTAssertEqual(s.ease, 1.3, accuracy: 0.001)
    }

    func testIntervalLabels() {
        XCTAssertEqual(Scheduler.formatInterval(600), "10m")
        XCTAssertEqual(Scheduler.formatInterval(86_400), "1d")
        XCTAssertEqual(Scheduler.formatInterval(86_400 * 21), "3w")
    }

    func testStreak() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var log = StudyLog()
        let today = now
        log.record(review: today, calendar: cal)
        log.record(review: today.addingTimeInterval(-86_400), calendar: cal)
        log.record(review: today.addingTimeInterval(-2 * 86_400), calendar: cal)
        log.record(review: today.addingTimeInterval(-4 * 86_400), calendar: cal)
        XCTAssertEqual(log.streak(asOf: today, calendar: cal), 3)
        XCTAssertEqual(log.streak(asOf: today.addingTimeInterval(86_400), calendar: cal), 3, "yesterday still counts")
        XCTAssertEqual(log.streak(asOf: today.addingTimeInterval(2 * 86_400), calendar: cal), 0)
        XCTAssertEqual(log.reviews(on: today, calendar: cal), 1)
    }
}

final class ModelTests: XCTestCase {
    func testLegacyGuideDecodes() throws {
        let legacy = """
        {"id": "\(UUID().uuidString)", "createdAt": "2026-10-01T10:00:00Z", "topic": "Old",
         "timeBudgetMinutes": 60, "tldr": "t", "paretoConcepts": [],
         "steps": [{"title": "S", "minutes": 5, "why": "w", "explanation": "e", "keyPoints": [],
                    "videos": [{"title": "v", "url": "u", "channel": "c", "duration": "d", "watchTip": "w", "verified": true}],
                    "activeRecall": [], "done": true}],
         "flashcards": [{"front": "f", "back": "b"}], "commonMistakes": [], "skipList": [], "selfTest": [], "sourceNotes": ""}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let guide = try decoder.decode(StudyGuide.self, from: Data(legacy.utf8))
        XCTAssertEqual(guide.steps.first?.status, .done)
        XCTAssertEqual(guide.steps.first?.videos.first?.playbackSpeed, 1.0)
        XCTAssertTrue(guide.flashcards[0].review.isNew)
        XCTAssertEqual(guide.progress, 1)

        // Round-trips through the current format.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let again = try decoder.decode(StudyGuide.self, from: encoder.encode(guide))
        XCTAssertEqual(again, guide)
    }

    func testKnowledgeMapDepths() {
        func step(_ p: [Int]) -> StudyStep { StudyStep(title: "", minutes: 1, why: "", explanation: "", prerequisites: p) }
        XCTAssertEqual(KnowledgeMapLayout.depths(for: [step([]), step([1]), step([]), step([2, 3])]), [0, 1, 0, 2])
        XCTAssertEqual(KnowledgeMapLayout.depths(for: [step([]), step([]), step([])]), [0, 1, 2])
    }

    func testMarkdownIncludesVideoSegment() {
        let video = VideoResource(title: "V", url: "https://youtu.be/x", channel: "C", duration: "9:00",
                                  watchTip: "Focus on the diagram.", startSeconds: 90, endSeconds: 465,
                                  playbackSpeed: 1.5, verified: true)
        let guide = StudyGuide(topic: "T", timeBudgetMinutes: 30, tldr: "", paretoConcepts: [],
                               steps: [StudyStep(title: "S", minutes: 5, why: "", explanation: "", videos: [video])],
                               flashcards: [], commonMistakes: [], skipList: [], selfTest: [], sourceNotes: "")
        let md = MarkdownExporter.markdown(for: guide)
        XCTAssertTrue(md.contains("Watch 1:30–7:45 at 1.5x."), md)
    }
}

final class RequestAndCostTests: XCTestCase {
    func testAttachmentsComeBeforeText() {
        var r = GuideRequest(notes: "")
        r.attachments = [NoteAttachment(kind: .image, name: "page1.jpg", mediaType: "image/jpeg", data: Data([1, 2, 3])),
                         NoteAttachment(kind: .pdf, name: "scan.pdf", mediaType: "application/pdf", data: Data([4]))]
        let blocks = Prompts.guideUserContent(r)
        // Each attachment is introduced by a label, and the instructions come last.
        XCTAssertEqual(blocks.map { $0["type"] as? String }, ["text", "image", "text", "document", "text"])
        XCTAssertEqual((blocks[1]["source"] as? JSON)?["data"] as? String, "AQID")
        XCTAssertEqual(blocks[2]["text"] as? String, "A page of my notes (scan.pdf):")
        XCTAssertTrue((blocks[4]["text"] as? String)?.contains("(see attached images)") == true)
        XCTAssertFalse(r.isEmpty)
        XCTAssertTrue(GuideRequest(notes: "  \n").isEmpty)
    }

    func testCostEstimate() {
        let usage: JSON = ["input_tokens": 100_000, "output_tokens": 10_000, "cache_read_input_tokens": 0,
                           "server_tool_use": ["web_search_requests": 5]]
        // 0.1M * $4 + 0.01M * $20 + 5 * $0.01 = 0.40 + 0.20 + 0.05
        XCTAssertEqual(CostEstimator.dollars(model: "claude-opus-5-5", usage: usage), 0.65, accuracy: 0.0001)
        XCTAssertEqual(CostEstimator.format(0.651), "$0.65")
        XCTAssertEqual(CostEstimator.format(0.001), "<$0.01")
    }
}

final class TutorTests: XCTestCase {
    func testAssistantTurnsReplayExactBlocks() throws {
        let blocks: [JSON] = [["type": "thinking", "thinking": "", "signature": "sig"], ["type": "text", "text": "Hi"]]
        let raw = try JSONSerialization.data(withJSONObject: blocks)
        let history = [ChatTurn(role: .user, text: "Q1"),
                       ChatTurn(role: .assistant, text: "Hi", rawContent: raw),
                       ChatTurn(role: .user, text: "Q2")]
        let messages = LearningServices.tutorMessages(history)
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let replayed = try XCTUnwrap(messages[1]["content"] as? [JSON])
        XCTAssertEqual(replayed.first?["signature"] as? String, "sig")
        XCTAssertEqual(messages[2]["content"] as? String, "Q2")
    }

    func testAssistantTurnWithoutBlocksFallsBackToText() {
        let messages = LearningServices.tutorMessages([ChatTurn(role: .assistant, text: "")])
        XCTAssertEqual(messages[0]["content"] as? String, "…")
    }
}

// MARK: - Free mode

private struct FakeBackend: ChatBackend {
    var reply: String
    var modelName: String { "fake-model" }
    func chat(system: String, messages: [LocalMessage], schema: JSON?,
              onText: (@MainActor (String) -> Void)?) async throws -> String {
        if let onText { await onText(reply) }
        return reply
    }
}

/// Answers each free-mode pass according to the schema it was asked for.
private struct PassBackend: ChatBackend {
    var modelName: String { "fake-model" }
    func chat(system: String, messages: [LocalMessage], schema: JSON?,
              onText: (@MainActor (String) -> Void)?) async throws -> String {
        let props = schema?["properties"] as? JSON ?? [:]
        if props["steps"] != nil {
            return """
            {"topic": "Photosynthesis", "emoji": "🌱", "tldr": "Plants make sugar from light.",
             "paretoConcepts": ["Light reactions make ATP/NADPH", "Calvin cycle fixes CO2"],
             "steps": [
               {"title": "Light reactions", "minutes": 10, "why": "first", "videoQuery": "light dependent reactions explained", "prerequisites": []},
               {"title": "Calvin cycle", "minutes": 10, "why": "second", "videoQuery": "https://www.youtube.com/watch?v=fake", "prerequisites": [1]},
               {"title": "Big picture", "minutes": 5, "why": "wrap up", "videoQuery": "", "prerequisites": [1, 2]}
             ]}
            """
        }
        if props["whatToNotice"] != nil {
            XCTAssertEqual(messages.last?.images.count, 1, "each picture gets its own pass")
            return #"{"title": "Light reactions diagram", "explanation": "Shows the thylakoid.", "whatToNotice": ["arrows", "labels"], "stepNumber": 1}"#
        }
        if props["explanation"] != nil {
            let instruction = messages.last?.content.components(separatedBy: "\n").last ?? ""
            return """
            {"explanation": "Explains \(instruction)", "analogy": "a", "keyPoints": ["k1", "k2"],
             "activeRecall": ["q1", "q2"], "testOut": {"question": "tq", "answer": "ta"}}
            """
        }
        if props["flashcards"] != nil {
            return """
            {"flashcards": [{"front": "f", "back": "b"}], "commonMistakes": ["m"], "mnemonics": [],
             "skipList": ["s"], "selfTest": ["t"]}
            """
        }
        return "{}"
    }
}

private struct FakeVideos: VideoFinder {
    func search(_ query: String, limit: Int) async throws -> [YouTubeVideo] {
        [YouTubeVideo(id: "live1", title: "Live stream", channel: "X", duration: "", seconds: 0),
         YouTubeVideo(id: "abc123", title: "\(query) — explained", channel: "Teacher", duration: "8:30", seconds: 510),
         YouTubeVideo(id: "long1", title: "3 hour lecture", channel: "Uni", duration: "3:02:00", seconds: 10920)]
    }
}

final class FreeModeTests: XCTestCase {

    @MainActor
    func testLocalEngineBuildsGuideInPassesWithRealVideos() async throws {
        let engine = LocalEngine(backend: PassBackend(), videos: FakeVideos())
        var events: [ResearchEvent] = []
        let guide = try await engine.generateGuide(GuideRequest(notes: "photosynthesis notes")) { events.append($0) }

        XCTAssertEqual(guide.topic, "Photosynthesis")
        XCTAssertEqual(guide.buildCost, 0)
        XCTAssertEqual(guide.steps.count, 3)
        XCTAssertEqual(guide.steps[1].title, "Calvin cycle")
        XCTAssertEqual(guide.steps[1].explanation, "Explains Write step 2: Calvin cycle")
        XCTAssertEqual(guide.steps[1].prerequisites, [1])
        XCTAssertEqual(guide.steps[0].testOut?.question, "tq")
        XCTAssertEqual(guide.flashcards.count, 1)
        XCTAssertEqual(guide.selfTest, ["t"])

        let video = try XCTUnwrap(guide.steps[0].videos.first)
        XCTAssertEqual(video.youTubeID, "abc123", "skips live streams and very long videos")
        XCTAssertTrue(video.verified)
        XCTAssertTrue(events.contains(.searching("light dependent reactions explained")))
        // A URL or an empty query is replaced with a search built from the step title.
        XCTAssertTrue(events.contains(.searching("Calvin cycle Photosynthesis explained")))
        XCTAssertTrue(events.contains(.searching("Big picture Photosynthesis explained")))
        XCTAssertFalse(guide.steps[1].videos.isEmpty)
        XCTAssertFalse(guide.sources.isEmpty)
    }

    func testVideoQueryFallback() {
        XCTAssertEqual(LocalEngine.videoQuery("krebs cycle explained", step: "Krebs", topic: "Respiration"), "krebs cycle explained")
        XCTAssertEqual(LocalEngine.videoQuery("https://youtu.be/x", step: "Krebs", topic: "Respiration"), "Krebs Respiration explained")
        XCTAssertEqual(LocalEngine.videoQuery("", step: "Respiration basics", topic: "Respiration"), "Respiration basics explained")
    }

    func testLocalSchemasForceEnoughSteps() throws {
        let steps = try XCTUnwrap((LocalSchemas.outline["properties"] as? JSON)?["steps"] as? JSON)
        XCTAssertEqual(steps["minItems"] as? Int, 3)
        XCTAssertEqual(steps["maxItems"] as? Int, 8)
    }

    func testLocalEngineQuiz() async throws {
        let reply = """
        {"questions": [{"question": "Q?", "choices": ["a","b","c","d"], "correctIndex": 2, "explanation": "x", "stepNumber": 1},
                       {"question": "bad", "choices": ["a"], "correctIndex": 5, "explanation": "", "stepNumber": 1}]}
        """
        let engine = LocalEngine(backend: FakeBackend(reply: reply), videos: FakeVideos())
        let guide = StudyGuide(topic: "T", timeBudgetMinutes: 30, tldr: "", paretoConcepts: [], steps: [],
                               flashcards: [], commonMistakes: [], skipList: [], selfTest: [], sourceNotes: "")
        let quiz = try await engine.makeQuiz(for: guide)
        XCTAssertEqual(quiz.count, 1, "invalid questions are dropped")
        XCTAssertEqual(quiz[0].correctIndex, 2)
    }

    func testLocalSchemaAsksForQueriesNotURLs() throws {
        let steps = try XCTUnwrap((GuidePayload.localSchema["properties"] as? JSON)?["steps"] as? JSON)
        let props = try XCTUnwrap((steps["items"] as? JSON)?["properties"] as? JSON)
        XCTAssertNotNil(props["videoQuery"])
        XCTAssertNil(props["videos"])
    }

    func testTutorPromptMatchesEngine() {
        XCTAssertTrue(Prompts.tutorSystem(guideMarkdown: "g", canSearch: false).contains("can't browse"))
        XCTAssertTrue(Prompts.tutorSystem(guideMarkdown: "g", canSearch: true).contains("use web search"))
    }

    func testOllamaStreamParsing() {
        XCTAssertEqual(OllamaClient.parseChunk(#"{"message":{"role":"assistant","content":"Hi"},"done":false}"#),
                       OllamaClient.Chunk(text: "Hi", done: false, error: nil))
        XCTAssertEqual(OllamaClient.parseChunk(#"{"done":true}"#)?.done, true)
        XCTAssertEqual(OllamaClient.parseChunk(#"{"error":"model not found"}"#)?.error, "model not found")
        XCTAssertNil(OllamaClient.parseChunk("garbage"))
        XCTAssertEqual(OllamaClient.stripThinking("<think>hmm</think>\n{\"a\":1}"), "{\"a\":1}")
        XCTAssertEqual(OllamaClient.error(code: 404, body: Data(#"{"error":"model 'x' not found"}"#.utf8), model: "x"),
                       .modelMissing("x"))
    }

    func testYouTubeResultsParsing() {
        let html = #"""
        <html><script>var ytInitialData = {"contents":{"list":[
          {"videoRenderer":{"videoId":"vid1","title":{"runs":[{"text":"Krebs cycle "},{"text":"in 5 minutes"}]},
            "ownerText":{"runs":[{"text":"Bio Prof"}]},"lengthText":{"simpleText":"5:07"}}},
          {"channelRenderer":{"title":{"simpleText":"skip me"}}},
          {"videoRenderer":{"videoId":"vid2","title":{"simpleText":"Tricky \"quotes\" {braces}"},
            "longBylineText":{"runs":[{"text":"Chan"}]},"lengthText":{"simpleText":"1:02:03"}}},
          {"videoRenderer":{"videoId":"vid1","title":{"simpleText":"duplicate"}}}
        ]}};</script></html>
        """#
        let videos = YouTubeSearch.parse(html: html)
        XCTAssertEqual(videos.map(\.id), ["vid1", "vid2"])
        XCTAssertEqual(videos[0].title, "Krebs cycle in 5 minutes")
        XCTAssertEqual(videos[0].channel, "Bio Prof")
        XCTAssertEqual(videos[0].seconds, 307)
        XCTAssertEqual(videos[1].title, "Tricky \"quotes\" {braces}")
        XCTAssertEqual(videos[1].seconds, 3723)
        XCTAssertEqual(YouTubeSearch.parse(html: "<html>no data</html>"), [])
        XCTAssertEqual(YouTubeSearch.pickBest(videos).first?.id, "vid1")
    }
}

// MARK: - Claude plan mode (Claude Code CLI)

final class ClaudeCodeTests: XCTestCase {
    /// Output captured from the real `claude -p --output-format stream-json` (Claude Code 2.1).
    func testParsesRealStreamOutput() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "claude-code-stream", withExtension: "jsonl", subdirectory: "Fixtures"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        let parser = ClaudeCodeStreamParser()
        let events = lines.flatMap { parser.handle($0) }

        XCTAssertEqual(events.first, .initialized(apiKeySource: "none", model: "claude-sonnet-5-5"))
        XCTAssertTrue(events.contains(.searchQuery("YouTube short video explaining the Krebs cycle")))
        XCTAssertTrue(events.contains { if case .usage = $0 { return true } else { return false } })

        XCTAssertTrue(parser.finished)
        XCTAssertFalse(parser.isError)
        XCTAssertGreaterThan(parser.hits.count, 3)
        XCTAssertTrue(parser.hits.allSatisfy { $0.url.hasPrefix("https://") })
        let structured = try XCTUnwrap(parser.structured as? JSON)
        let url2 = try XCTUnwrap(structured["url"] as? String)
        XCTAssertNotNil(YouTube.videoID(from: url2))
    }

    func testLinksParsing() {
        let text = #"Web search results for query: "x"\n\nLinks: [{"title":"A [b]","url":"https://www.youtube.com/watch?v=1"},{"title":"C","url":"https://c.org"}]\n\nMore text ]"#
        XCTAssertEqual(ClaudeCodeStreamParser.links(in: text).map(\.url), ["https://www.youtube.com/watch?v=1", "https://c.org"])
        XCTAssertEqual(ClaudeCodeStreamParser.links(in: "no links"), [])
    }

    func testErrorResultAndAPIKeyDetection() {
        let parser = ClaudeCodeStreamParser()
        XCTAssertEqual(parser.handle(#"{"type":"system","subtype":"init","apiKeySource":"ANTHROPIC_API_KEY","model":"m"}"#),
                       [.initialized(apiKeySource: "ANTHROPIC_API_KEY", model: "m")])
        _ = parser.handle(#"{"type":"result","subtype":"success","is_error":true,"result":"Claude AI usage limit reached|1793865600"}"#)
        XCTAssertTrue(parser.isError)
        XCTAssertEqual(ClaudeCodeRunner.classify(parser.errorMessage ?? ""), .usageLimit("Claude AI usage limit reached|1793865600"))
        XCTAssertEqual(ClaudeCodeRunner.classify("Invalid API key · Please run /login"), .notLoggedIn)
    }

    func testEnvironmentNeverBillsAnAPIKey() {
        setenv("ANTHROPIC_API_KEY", "sk-test", 1)
        defer { unsetenv("ANTHROPIC_API_KEY") }
        let env = ClaudeCodeRunner.environment(searchPath: "/usr/bin")
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertNil(env["ANTHROPIC_AUTH_TOKEN"])
        XCTAssertEqual(env["PATH"], "/usr/bin")
    }

    func testAuthStatusParsing() {
        let sub = ClaudeCodeRunner.parseAuthStatus(#"{"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty"}"#)
        XCTAssertEqual(sub?.usesSubscription, true)
        let key = ClaudeCodeRunner.parseAuthStatus(#"{"loggedIn": true, "authMethod": "api_key"}"#)
        XCTAssertEqual(key?.usesSubscription, false)
        XCTAssertEqual(ClaudeCodeRunner.parseAuthStatus(#"{"loggedIn": false}"#)?.usesSubscription, false)
    }

    func testTutorTranscript() {
        XCTAssertEqual(ClaudeCodeEngine.transcript([ChatTurn(role: .user, text: "Hi")]), "Hi")
        let t = ClaudeCodeEngine.transcript([ChatTurn(role: .user, text: "Q1"), ChatTurn(role: .assistant, text: "A1"),
                                             ChatTurn(role: .user, text: "Q2")])
        XCTAssertTrue(t.contains("Learner: Q1"))
        XCTAssertTrue(t.contains("Tutor: A1"))
        XCTAssertTrue(t.hasSuffix("Q2"))
    }

    func testEngineWithoutClaudeCodeExplainsSetup() async {
        let engine = ClaudeCodeEngine(runner: nil)
        do {
            _ = try await engine.structured(system: "", prompt: "", schema: [:], effort: "low")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ClaudeCodeError, .notInstalled)
        }
    }
}


// MARK: - Pictures in notes

final class FigureTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let parts = name.split(separator: ".")
        return try XCTUnwrap(Bundle.module.url(forResource: String(parts[0]), withExtension: String(parts[1]), subdirectory: "Fixtures"))
    }

    func testExtractsPicturesFromWordInOrderAndSkipsIcons() throws {
        let figures = FigureExtractor.officeImages(at: try fixture("figures.docx"))
        XCTAssertEqual(figures.count, 2, "the 24px icon is skipped")
        XCTAssertTrue(figures.allSatisfy { $0.isFigure && $0.mediaType == "image/jpeg" })
        XCTAssertEqual(figures.first?.name, "figures.docx · picture 1")
        // image1 (320 wide) comes before image2 (240 wide) despite zip order.
        let first = try XCTUnwrap(FigureExtractor.cgImage(from: figures[0].data))
        XCTAssertEqual(first.width, 320)
    }

    func testExtractsPowerPointTextAndPictures() throws {
        let url = try fixture("slides.pptx")
        XCTAssertEqual(FigureExtractor.officeImages(at: url).count, 1)
        let text = FigureExtractor.pptxText(at: url)
        XCTAssertEqual(text, "Slide 1: Osmosis & water moves to high solute\nSlide 2: Second slide: diffusion\nSlide 3: Tenth")
    }

    /// Fraction of pixels that aren't (near) white: proves the render shows the picture.
    private func inkCoverage(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var ink = 0
        for i in stride(from: 0, to: buf.count, by: 4) where buf[i] < 200 || buf[i + 1] < 200 || buf[i + 2] < 200 { ink += 1 }
        return Double(ink) / Double(w * h)
    }

    private func pdfFigures(_ name: String) throws -> [(NoteAttachment, CGImage)] {
        let data = try Data(contentsOf: try fixture(name))
        return try FigureExtractor.pdfImages(data, name: name).map { ($0, try XCTUnwrap(FigureExtractor.cgImage(from: $0.data))) }
    }

    func testFindsPictureEmbeddedInPDF() throws {
        let figures = try pdfFigures("lecture.pdf")
        XCTAssertEqual(figures.count, 1)
        XCTAssertEqual(figures[0].0.name, "lecture.pdf · page 1 figure")
        // 200×150 pt picture plus padding, rendered at high resolution.
        XCTAssertEqual(Double(figures[0].1.width) / Double(figures[0].1.height), 216.0 / 166.0, accuracy: 0.03)
        XCTAssertGreaterThan(figures[0].1.width, 600)
        XCTAssertGreaterThan(inkCoverage(figures[0].1), 0.05)
    }

    func testFindsDiagramDrawnWithShapes() throws {
        // Page also has a full-page background, a title underline and a lone callout box: none are figures.
        let figures = try pdfFigures("vector.pdf")
        XCTAssertEqual(figures.count, 1)
        let image = figures[0].1
        XCTAssertEqual(Double(image.width) / Double(image.height), 376.0 / 176.0, accuracy: 0.05)
        XCTAssertGreaterThan(inkCoverage(image), 0.01)
    }

    func testFindsIndexedColorImageInsideGroup() throws {
        let figures = try pdfFigures("form-indexed.pdf")
        XCTAssertEqual(figures.count, 1)
        XCTAssertEqual(Double(figures[0].1.width) / Double(figures[0].1.height), 176.0 / 136.0, accuracy: 0.03)
        XCTAssertGreaterThan(inkCoverage(figures[0].1), 0.5, "the red/blue checkerboard is rendered")
    }

    func testRegionGrouping() {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let marks = [
            PDFFigureFinder.Mark(rect: page, isImage: false),                                     // background
            PDFFigureFinder.Mark(rect: CGRect(x: 72, y: 700, width: 300, height: 0.5), isImage: false), // rule
        ] + (0..<5).map { PDFFigureFinder.Mark(rect: CGRect(x: 100 + $0 * 40, y: 300, width: 30, height: 80), isImage: false) }
            + [PDFFigureFinder.Mark(rect: CGRect(x: 400, y: 100, width: 120, height: 90), isImage: true)]
        let regions = PDFFigureFinder.figureRegions(marks: marks, page: page)
        XCTAssertEqual(regions.count, 2, "the bar chart and the photo; not the background or the rule")
        XCTAssertEqual(regions[0].minX, 92, accuracy: 0.1)   // bars, top-most first
        XCTAssertEqual(regions[0].width, 190 + 16, accuracy: 0.1)
    }

    func testPromptLabelsFiguresAndAsksForExplanations() {
        var r = GuideRequest(notes: "n")
        r.attachments = [NoteAttachment(kind: .image, name: "a.docx · picture 1", mediaType: "image/jpeg", data: Data([1])),
                         NoteAttachment(kind: .image, role: .page, name: "page.jpg", mediaType: "image/jpeg", data: Data([2])),
                         NoteAttachment(kind: .image, name: "b.pdf · page 2 picture", mediaType: "image/jpeg", data: Data([3]))]
        let blocks = Prompts.guideUserContent(r)
        let labels = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        XCTAssertEqual(labels[0], "Figure 1 (from a.docx · picture 1):")
        XCTAssertEqual(labels[1], "A page of my notes (page.jpg):")
        XCTAssertEqual(labels[2], "Figure 2 (from b.pdf · page 2 picture):")
        XCTAssertTrue(labels[3].contains("labeled Figure 1–2"))
        XCTAssertEqual(blocks.filter { $0["type"] as? String == "image" }.count, 3)
    }

    func testGuideKeepsEveryFigureWithExplanations() throws {
        let json = #"""
        {"topic": "T", "steps": [{"title": "S1"}, {"title": "S2"}],
         "figures": [{"figureNumber": 2, "title": "Graph", "explanation": "Rises then falls.", "whatToNotice": ["peak"], "stepNumber": 2},
                     {"figureNumber": 9, "title": "Ghost", "explanation": "no such figure", "whatToNotice": [], "stepNumber": 1}]}
        """#
        var r = GuideRequest(notes: "n")
        r.attachments = [NoteAttachment(kind: .image, name: "p1", mediaType: "image/jpeg", data: Data([1])),
                         NoteAttachment(kind: .image, name: "p2", mediaType: "image/jpeg", data: Data([2]))]
        let guide = try XCTUnwrap(GuidePayload.decode(from: json)).toGuide(request: r, searchHits: [])
        XCTAssertEqual(guide.figures.count, 2, "one per picture, ignoring explanations for pictures that don't exist")
        XCTAssertEqual(guide.figures[0].title, "Figure 1", "unexplained pictures still show")
        XCTAssertEqual(guide.figures[0].stepNumber, 0)
        XCTAssertEqual(guide.figures[1].title, "Graph")
        XCTAssertEqual(guide.figures[1].sourceIndex, 1)
        XCTAssertEqual(guide.figures(forStep: 2).map(\.title), ["Graph"])
        XCTAssertTrue(guide.figures[1].fileName.hasSuffix(".jpg"))
        XCTAssertTrue(MarkdownExporter.markdown(for: guide).contains("**Figure — Graph**: Rises then falls."))

        // Survives saving and loading.
        let again = try JSONDecoder().decode(StudyGuide.self, from: JSONEncoder().encode(guide))
        XCTAssertEqual(again.figures, guide.figures)
    }

    func testSchemaAsksForFigures() {
        let props = GuidePayload.schema["properties"] as? JSON
        XCTAssertNotNil(props?["figures"])
    }

    @MainActor
    func testFreeModeExplainsEachPicture() async throws {
        var r = GuideRequest(notes: "photosynthesis")
        r.attachments = [NoteAttachment(kind: .image, name: "diagram", mediaType: "image/jpeg", data: Data([9]))]
        let guide = try await LocalEngine(backend: PassBackend(), videos: FakeVideos()).generateGuide(r) { _ in }
        XCTAssertEqual(guide.figures.count, 1)
        XCTAssertEqual(guide.figures[0].title, "Light reactions diagram")
        XCTAssertEqual(guide.figures[0].notice, ["arrows", "labels"])
        XCTAssertEqual(guide.figures[0].stepNumber, 1)
    }
}
