import Foundation

/// Whatever does the thinking: Claude (paid, best) or a free model running on this Mac.
/// Engines provide guide generation, tutor chat and one structured-JSON call;
/// quizzes and grading are built on top of that once, below.
public protocol StudyEngine {
    /// True when using the engine costs nothing.
    var isFree: Bool { get }
    /// True when the tutor can search the web.
    var canSearchWeb: Bool { get }

    func generateGuide(
        _ request: GuideRequest,
        onEvent: @escaping @MainActor (ResearchEvent) -> Void
    ) async throws -> StudyGuide

    /// Streams a tutor reply. `history` must end with the learner's newest message.
    func tutorReply(
        system: String,
        history: [ChatTurn],
        onText: @escaping @MainActor (String) -> Void,
        onStatus: @escaping @MainActor (String) -> Void
    ) async throws -> ChatTurn

    /// One request whose answer must match `schema`; returns the parsed JSON object.
    func structured(system: String, prompt: String, schema: JSON, effort: String) async throws -> JSON
}

public struct TestOutVerdict: Sendable, Equatable {
    public var passed: Bool
    public var feedback: String
    public init(passed: Bool, feedback: String) {
        self.passed = passed
        self.feedback = feedback
    }
}

extension StudyEngine {
    public func tutorSystem(for guide: StudyGuide) -> String {
        Prompts.tutorSystem(guideMarkdown: MarkdownExporter.markdown(for: guide, includeProgress: false),
                            canSearch: canSearchWeb)
    }

    // MARK: Quiz

    public func makeQuiz(for guide: StudyGuide, count: Int = 8, focusSteps: [Int] = []) async throws -> [QuizQuestion] {
        let json = try await structured(system: Prompts.quizSystem,
                                        prompt: LearningTasks.quizPrompt(guide: guide, count: count, focusSteps: focusSteps),
                                        schema: LearningTasks.quizSchema, effort: "medium")
        let questions = LearningTasks.parseQuiz(json)
        if questions.isEmpty { throw APIError.unparseable }
        return questions
    }

    // MARK: Feynman

    public func gradeFeynman(concept: String, explanation: String, guide: StudyGuide) async throws -> FeynmanResult {
        let json = try await structured(system: Prompts.feynmanSystem,
                                        prompt: LearningTasks.feynmanPrompt(concept: concept, explanation: explanation, guide: guide),
                                        schema: LearningTasks.feynmanSchema, effort: "medium")
        return LearningTasks.parseFeynman(json, concept: concept, explanation: explanation)
    }

    // MARK: Test out

    public func gradeTestOut(stepTitle: String, testOut: TestOut, answer: String) async throws -> TestOutVerdict {
        let json = try await structured(system: Prompts.testOutSystem,
                                        prompt: LearningTasks.testOutPrompt(stepTitle: stepTitle, testOut: testOut, answer: answer),
                                        schema: LearningTasks.testOutSchema, effort: "low")
        return TestOutVerdict(passed: json["passed"] as? Bool ?? false, feedback: json["feedback"] as? String ?? "")
    }
}

/// Prompts, schemas and parsing for the learning tools, shared by every engine.
enum LearningTasks {
    static func quizPrompt(guide: StudyGuide, count: Int, focusSteps: [Int]) -> String {
        let focus = focusSteps.isEmpty ? "" :
            "\nWeight about half the questions toward these steps the learner struggled with: \(focusSteps.map(String.init).joined(separator: ", "))."
        return """
        Write \(count) multiple-choice questions covering this study guide, mostly on the core concepts. \
        Each question has exactly 4 choices. correctIndex is the 0-based index of the right choice. \
        Set stepNumber to the 1-based step each question tests.\(focus)

        <study_guide>
        \(MarkdownExporter.markdown(for: guide, includeProgress: false, includeFlashcards: false))
        </study_guide>
        """
    }

    static let quizSchema: JSON = object([
        "questions": ["type": "array", "items": object([
            "question": string, "choices": strings, "correctIndex": integer,
            "explanation": string, "stepNumber": integer,
        ])] as JSON,
    ])

    static func parseQuiz(_ json: JSON) -> [QuizQuestion] {
        let raw = json["questions"] as? [JSON] ?? []
        return raw.compactMap { q -> QuizQuestion? in
            guard let question = q["question"] as? String,
                  let choices = q["choices"] as? [String], choices.count >= 2,
                  let correct = q["correctIndex"] as? Int, choices.indices.contains(correct) else { return nil }
            return QuizQuestion(question: question, choices: choices, correctIndex: correct,
                                explanation: q["explanation"] as? String ?? "",
                                stepNumber: q["stepNumber"] as? Int ?? 0)
        }
    }

    static func feynmanPrompt(concept: String, explanation: String, guide: StudyGuide) -> String {
        """
        Concept: \(concept)

        <learner_explanation>
        \(explanation)
        </learner_explanation>

        Reference material (for your grading only):
        <study_guide>
        \(MarkdownExporter.markdown(for: guide, includeProgress: false, includeFlashcards: false))
        </study_guide>
        """
    }

    static let feynmanSchema: JSON = object([
        "score": integer, "verdict": string, "nailed": strings, "gaps": strings,
        "misconceptions": strings, "improvedExplanation": string, "followUpQuestion": string,
    ])

    static func parseFeynman(_ j: JSON, concept: String, explanation: String) -> FeynmanResult {
        FeynmanResult(
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

    static func testOutPrompt(stepTitle: String, testOut: TestOut, answer: String) -> String {
        """
        Step: \(stepTitle)
        Question: \(testOut.question)
        Key points a correct answer contains: \(testOut.answer)

        <learner_answer>
        \(answer)
        </learner_answer>
        """
    }

    static let testOutSchema: JSON = object(["passed": ["type": "boolean"] as JSON, "feedback": string])

    static let string: JSON = ["type": "string"]
    static let integer: JSON = ["type": "integer"]
    static let strings: JSON = ["type": "array", "items": ["type": "string"]]

    static func object(_ props: [String: Any]) -> JSON {
        ["type": "object", "properties": props, "required": Array(props.keys).sorted(), "additionalProperties": false]
    }
}
