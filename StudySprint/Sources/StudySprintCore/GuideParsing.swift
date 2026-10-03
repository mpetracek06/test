import Foundation

/// The JSON shape Claude returns for a guide. Every field is optional on the way in, so a
/// slightly-off answer still produces a usable guide instead of an error.
struct GuidePayload: Decodable {
    struct Video: Decodable {
        var title, url, channel, duration, watchTip: String
        var startSeconds, endSeconds: Int
        var playbackSpeed: Double

        enum CodingKeys: String, CodingKey { case title, url, channel, duration, watchTip, startSeconds, endSeconds, playbackSpeed }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = c.value(.title, "Video")
            url = c.value(.url, "")
            channel = c.value(.channel, "")
            duration = c.value(.duration, "")
            watchTip = c.value(.watchTip, "")
            startSeconds = c.value(.startSeconds, 0)
            endSeconds = c.value(.endSeconds, 0)
            playbackSpeed = c.value(.playbackSpeed, 1.0)
        }
    }

    struct Step: Decodable {
        var title, why, explanation, analogy: String
        var minutes: Int
        var keyPoints, activeRecall: [String]
        var videos: [Video]
        var testOut: TestOut?
        var prerequisites: [Int]
        /// Free mode: what to search YouTube for (the app finds the video itself).
        var videoQuery: String

        enum CodingKeys: String, CodingKey {
            case title, minutes, why, explanation, analogy, keyPoints, videos, activeRecall, testOut, prerequisites, videoQuery
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = c.value(.title, "Step")
            minutes = c.value(.minutes, Int(c.value(.minutes, 10.0)))
            why = c.value(.why, "")
            explanation = c.value(.explanation, "")
            analogy = c.value(.analogy, "")
            keyPoints = c.value(.keyPoints, [])
            videos = c.value(.videos, [])
            activeRecall = c.value(.activeRecall, [])
            testOut = c.value(.testOut, nil)
            prerequisites = c.value(.prerequisites, [])
            videoQuery = c.value(.videoQuery, "")
        }
    }

    struct Card: Decodable { var front, back: String }

    var topic, emoji, tldr: String
    var paretoConcepts, commonMistakes, skipList, mnemonics, selfTest: [String]
    var steps: [Step]
    var flashcards: [Card]

    enum CodingKeys: String, CodingKey {
        case topic, emoji, tldr, paretoConcepts, steps, flashcards, commonMistakes, skipList, mnemonics, selfTest
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = try c.decode([Step].self, forKey: .steps) // the one field we can't do without
        topic = c.value(.topic, "Study guide")
        emoji = c.value(.emoji, "📘")
        tldr = c.value(.tldr, "")
        paretoConcepts = c.value(.paretoConcepts, [])
        flashcards = c.value(.flashcards, [])
        commonMistakes = c.value(.commonMistakes, [])
        skipList = c.value(.skipList, [])
        mnemonics = c.value(.mnemonics, [])
        selfTest = c.value(.selfTest, [])
    }

    func toGuide(request: GuideRequest, searchHits: [SearchHit]) -> StudyGuide {
        let knownIDs = Set(searchHits.compactMap { YouTube.videoID(from: $0.url) })
        let knownURLs = Set(searchHits.map { YouTube.normalize($0.url) })

        func resource(_ v: Video) -> VideoResource {
            let idMatch = YouTube.videoID(from: v.url).map { knownIDs.contains($0) } ?? false
            let verified = idMatch || knownURLs.contains(YouTube.normalize(v.url))
            // An unverified link might be made up, so send the learner to a search instead.
            let url = verified ? v.url : YouTube.searchURL(for: "\(v.title) \(v.channel)")
            let start = max(0, v.startSeconds)
            let end = v.endSeconds > start ? v.endSeconds : 0
            return VideoResource(title: v.title, url: url, channel: v.channel, duration: v.duration,
                                 watchTip: v.watchTip, startSeconds: start, endSeconds: end,
                                 playbackSpeed: min(2.0, max(0.75, v.playbackSpeed)), verified: verified)
        }

        let builtSteps = steps.enumerated().map { index, s in
            StudyStep(title: s.title, minutes: max(1, s.minutes), why: s.why, explanation: s.explanation,
                      analogy: s.analogy, keyPoints: s.keyPoints, videos: s.videos.map(resource),
                      activeRecall: s.activeRecall, testOut: s.testOut,
                      prerequisites: Array(Set(s.prerequisites.filter { $0 >= 1 && $0 <= index })).sorted())
        }

        var seen = Set<String>()
        let uniqueHits = searchHits.filter { seen.insert($0.url).inserted }

        return StudyGuide(
            topic: topic,
            emoji: emoji.isEmpty ? "📘" : String(emoji.prefix(1)),
            timeBudgetMinutes: request.budget.rawValue,
            tldr: tldr,
            paretoConcepts: paretoConcepts,
            steps: builtSteps,
            flashcards: flashcards.map { Flashcard(front: $0.front, back: $0.back) },
            commonMistakes: commonMistakes,
            skipList: skipList,
            mnemonics: mnemonics,
            selfTest: selfTest,
            sourceNotes: request.attachments.isEmpty ? request.notes
                : request.notes + "\n\n[\(request.attachments.count) attached: \(request.attachments.map(\.name).joined(separator: ", "))]",
            sources: uniqueHits
        )
    }

    /// Finds the guide JSON in Claude's answer: between <guide_json> tags if present,
    /// otherwise the outermost {...}. Strips Markdown code fences.
    static func decode(from text: String) -> GuidePayload? {
        var candidate = text
        if let start = text.range(of: "<guide_json>") {
            let rest = text[start.upperBound...]
            candidate = String(rest.range(of: "</guide_json>").map { rest[..<$0.lowerBound] } ?? rest)
        }
        guard let first = candidate.firstIndex(of: "{"), let last = candidate.lastIndex(of: "}"),
              first < last else { return nil }
        let json = String(candidate[first...last])
        return try? JSONDecoder().decode(GuidePayload.self, from: Data(json.utf8))
    }

    static let schema: JSON = makeSchema(local: false)
    /// Free mode: no video URLs from the model, just a search query per step.
    static let localSchema: JSON = makeSchema(local: true)

    static func makeSchema(local: Bool) -> JSON {
        func obj(_ props: [String: Any]) -> JSON {
            ["type": "object", "properties": props, "required": Array(props.keys).sorted(), "additionalProperties": false]
        }
        let str: JSON = ["type": "string"]
        let int: JSON = ["type": "integer"]
        let strs: JSON = ["type": "array", "items": str]
        let video = obj([
            "title": str, "url": str, "channel": str, "duration": str, "watchTip": str,
            "startSeconds": int, "endSeconds": int, "playbackSpeed": ["type": "number"] as JSON,
        ])
        var stepProps: [String: Any] = [
            "title": str, "minutes": int, "why": str, "explanation": str, "analogy": str,
            "keyPoints": strs, "activeRecall": strs,
            "testOut": obj(["question": str, "answer": str]),
            "prerequisites": ["type": "array", "items": int] as JSON,
        ]
        if local {
            stepProps["videoQuery"] = str
        } else {
            stepProps["videos"] = ["type": "array", "items": video] as JSON
        }
        let step = obj(stepProps)
        return obj([
            "topic": str, "emoji": str, "tldr": str, "paretoConcepts": strs,
            "steps": ["type": "array", "items": step] as JSON,
            "flashcards": ["type": "array", "items": obj(["front": str, "back": str])] as JSON,
            "commonMistakes": strs, "skipList": strs, "mnemonics": strs, "selfTest": strs,
        ])
    }
}

public enum YouTube {
    public static func videoID(from string: String) -> String? {
        guard let comps = URLComponents(string: string), let host = comps.host?.lowercased() else { return nil }
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return comps.path.split(separator: "/").first.map(String.init)
        }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") || host.hasSuffix("youtube-nocookie.com") else { return nil }
        if comps.path == "/watch", let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        let parts = comps.path.split(separator: "/").map(String.init)
        if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) { return parts[1] }
        return nil
    }

    public static func normalize(_ string: String) -> String {
        var s = string.lowercased()
        for prefix in ["https://", "http://", "www.", "m."] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    public static func searchURL(for query: String) -> String {
        var comps = URLComponents(string: "https://www.youtube.com/results")!
        comps.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return comps.url?.absoluteString ?? "https://www.youtube.com"
    }

    /// "m:ss" or "h:mm:ss" for a number of seconds.
    public static func timestamp(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
