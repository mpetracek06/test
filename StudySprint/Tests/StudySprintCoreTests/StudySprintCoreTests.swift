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
        XCTAssertEqual(blocks.map { $0["type"] as? String }, ["image", "document", "text"])
        XCTAssertEqual((blocks[0]["source"] as? JSON)?["data"] as? String, "AQID")
        XCTAssertTrue((blocks[2]["text"] as? String)?.contains("(see attached images)") == true)
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

private struct FakeVideos: VideoFinder {
    func search(_ query: String, limit: Int) async throws -> [YouTubeVideo] {
        [YouTubeVideo(id: "live1", title: "Live stream", channel: "X", duration: "", seconds: 0),
         YouTubeVideo(id: "abc123", title: "\(query) — explained", channel: "Teacher", duration: "8:30", seconds: 510),
         YouTubeVideo(id: "long1", title: "3 hour lecture", channel: "Uni", duration: "3:02:00", seconds: 10920)]
    }
}

final class FreeModeTests: XCTestCase {
    let localReply = """
    {"topic": "Photosynthesis", "emoji": "🌱", "tldr": "Plants make sugar from light.",
     "paretoConcepts": ["Light reactions make ATP/NADPH", "Calvin cycle fixes CO2"],
     "steps": [
       {"title": "Light reactions", "minutes": 10, "why": "w", "explanation": "e", "analogy": "a",
        "keyPoints": ["k"], "activeRecall": ["q"], "testOut": {"question": "tq", "answer": "ta"},
        "prerequisites": [], "videoQuery": "light dependent reactions explained"},
       {"title": "Calvin cycle", "minutes": 10, "why": "w", "explanation": "e", "analogy": "a",
        "keyPoints": ["k"], "activeRecall": ["q"], "testOut": {"question": "tq", "answer": "ta"},
        "prerequisites": [1], "videoQuery": ""}
     ],
     "flashcards": [{"front": "f", "back": "b"}], "commonMistakes": [], "skipList": [], "mnemonics": [], "selfTest": []}
    """

    @MainActor
    func testLocalEngineBuildsGuideWithRealVideos() async throws {
        let engine = LocalEngine(backend: FakeBackend(reply: localReply), videos: FakeVideos())
        var events: [ResearchEvent] = []
        let guide = try await engine.generateGuide(GuideRequest(notes: "photosynthesis notes")) { events.append($0) }

        XCTAssertEqual(guide.topic, "Photosynthesis")
        XCTAssertEqual(guide.buildCost, 0)
        XCTAssertEqual(guide.steps.count, 2)
        let video = try XCTUnwrap(guide.steps[0].videos.first)
        XCTAssertEqual(video.youTubeID, "abc123", "skips live streams and very long videos")
        XCTAssertTrue(video.verified)
        XCTAssertTrue(guide.steps[1].videos.isEmpty, "no query → no video")
        XCTAssertTrue(events.contains(.searching("light dependent reactions explained")))
        XCTAssertFalse(guide.sources.isEmpty)
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
