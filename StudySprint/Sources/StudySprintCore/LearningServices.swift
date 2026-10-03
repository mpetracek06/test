import Foundation

/// Tutor chat, quizzes, Feynman grading and "test out" checks.
public struct LearningServices {
    public var client: AnthropicClient

    public init(client: AnthropicClient) {
        self.client = client
    }

    // MARK: - Tutor

    public static func tutorSystem(for guide: StudyGuide) -> String {
        Prompts.tutorSystem(guideMarkdown: MarkdownExporter.markdown(for: guide, includeProgress: false))
    }

    /// Streams a tutor reply. `history` must end with the learner's newest message.
    /// Assistant turns are replayed with their exact original content blocks so the
    /// conversation stays append-only (required for thinking blocks, and good for caching).
    public func tutorReply(
        system: String,
        history: [ChatTurn],
        onText: @escaping @MainActor (String) -> Void,
        onStatus: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> ChatTurn {
        let messages = Self.tutorMessages(history)

        let body: JSON = [
            "max_tokens": 8000,
            "system": [[
                "type": "text",
                "text": system,
                "cache_control": ["type": "ephemeral"],
            ] as JSON],
            "output_config": ["effort": "low"],
            "fallbacks": "default",
            "tools": [["type": "web_search_20260209", "name": "web_search", "max_uses": 3] as JSON],
            "messages": messages,
        ]

        let message = try await client.stream(body, betas: [AnthropicClient.fallbackBeta]) { update in
            switch update {
            case .text(let t): onText(t)
            case .searchQuery(let q): onStatus("Searching: \(q)")
            case .fallback: onStatus("Switched to a fallback model")
            default: break
            }
        }
        try message.throwIfRefused()
        return ChatTurn(role: .assistant, text: message.text, rawContent: message.echoData)
    }

    /// Converts saved turns to API messages, replaying assistant turns with their exact original blocks.
    static func tutorMessages(_ history: [ChatTurn]) -> [JSON] {
        history.map { turn -> JSON in
            switch turn.role {
            case .user:
                return ["role": "user", "content": turn.text]
            case .assistant:
                if let raw = turn.rawContent,
                   let blocks = (try? JSONSerialization.jsonObject(with: raw)) as? [JSON], !blocks.isEmpty {
                    return ["role": "assistant", "content": blocks]
                }
                return ["role": "assistant", "content": turn.text.isEmpty ? "…" : turn.text]
            }
        }
    }

    // MARK: - Quiz

    public func makeQuiz(for guide: StudyGuide, count: Int = 8, focusSteps: [Int] = []) async throws -> [QuizQuestion] {
        let focus = focusSteps.isEmpty ? "" :
            "\nWeight about half the questions toward these steps the learner struggled with: \(focusSteps.map(String.init).joined(separator: ", "))."
        let prompt = """
        Write \(count) multiple-choice questions covering this study guide, mostly on the core concepts. \
        Set stepNumber to the 1-based step each question tests.\(focus)

        <study_guide>
        \(MarkdownExporter.markdown(for: guide, includeProgress: false))
        </study_guide>
        """
        let schema = Self.object([
            "questions": ["type": "array", "items": Self.object([
                "question": Self.string, "choices": Self.strings, "correctIndex": Self.integer,
                "explanation": Self.string, "stepNumber": Self.integer,
            ])] as JSON,
        ])
        let json = try await structured(system: Prompts.quizSystem, prompt: prompt, schema: schema)
        let raw = json["questions"] as? [JSON] ?? []
        let questions = raw.compactMap { q -> QuizQuestion? in
            guard let question = q["question"] as? String,
                  let choices = q["choices"] as? [String], choices.count >= 2,
                  let correct = q["correctIndex"] as? Int, choices.indices.contains(correct) else { return nil }
            return QuizQuestion(question: question, choices: choices, correctIndex: correct,
                                explanation: q["explanation"] as? String ?? "",
                                stepNumber: q["stepNumber"] as? Int ?? 0)
        }
        if questions.isEmpty { throw APIError.unparseable }
        return questions
    }

    // MARK: - Feynman

    public func gradeFeynman(concept: String, explanation: String, guide: StudyGuide) async throws -> FeynmanResult {
        let prompt = """
        Concept: \(concept)

        <learner_explanation>
        \(explanation)
        </learner_explanation>

        Reference material (for your grading only):
        <study_guide>
        \(MarkdownExporter.markdown(for: guide, includeProgress: false))
        </study_guide>
        """
        let schema = Self.object([
            "score": Self.integer, "verdict": Self.string, "nailed": Self.strings, "gaps": Self.strings,
            "misconceptions": Self.strings, "improvedExplanation": Self.string, "followUpQuestion": Self.string,
        ])
        let j = try await structured(system: Prompts.feynmanSystem, prompt: prompt, schema: schema)
        return FeynmanResult(
            concept: concept, explanation: explanation,
            score: min(100, max(0, j["score"] as? Int ?? 0)),
            verdict: j["verdict"] as? String ?? "",
            nailed: j["nailed"] as? [String] ?? [],
            gaps: j["gaps"] as? [String] ?? [],
            misconceptions: j["misconceptions"] as? [String] ?? [],
            improvedExplanation: j["improvedExplanation"] as? String ?? "",
            followUpQuestion: j["followUpQuestion"] as? String ?? ""
        )
    }

    // MARK: - Test out

    public struct TestOutVerdict: Sendable, Equatable {
        public var passed: Bool
        public var feedback: String
        public init(passed: Bool, feedback: String) {
            self.passed = passed
            self.feedback = feedback
        }
    }

    public func gradeTestOut(stepTitle: String, testOut: TestOut, answer: String) async throws -> TestOutVerdict {
        let prompt = """
        Step: \(stepTitle)
        Question: \(testOut.question)
        Key points a correct answer contains: \(testOut.answer)

        <learner_answer>
        \(answer)
        </learner_answer>
        """
        let schema = Self.object(["passed": ["type": "boolean"] as JSON, "feedback": Self.string])
        let j = try await structured(system: Prompts.testOutSystem, prompt: prompt, schema: schema, effort: "low")
        return TestOutVerdict(passed: j["passed"] as? Bool ?? false, feedback: j["feedback"] as? String ?? "")
    }

    // MARK: - Helpers

    private func structured(system: String, prompt: String, schema: JSON, effort: String = "medium") async throws -> JSON {
        let body: JSON = [
            "max_tokens": 16000,
            "system": system,
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema] as JSON,
            ] as JSON,
            "messages": [["role": "user", "content": prompt]],
        ]
        let message = try await client.stream(body) { _ in }
        try message.throwIfRefused()
        guard let json = (try? JSONSerialization.jsonObject(with: Data(message.text.utf8))) as? JSON else {
            throw APIError.unparseable
        }
        return json
    }

    static let string: JSON = ["type": "string"]
    static let integer: JSON = ["type": "integer"]
    static let strings: JSON = ["type": "array", "items": ["type": "string"]]

    static func object(_ props: [String: Any]) -> JSON {
        ["type": "object", "properties": props, "required": Array(props.keys).sorted(), "additionalProperties": false]
    }
}
