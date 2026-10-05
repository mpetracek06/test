import Foundation

// Runs StudySprint on the person's own Claude plan (Pro/Max) by driving the Claude Code CLI
// (`claude -p`) installed on their Mac. Usage counts toward their plan's limits; no API credit
// is used. If Claude Code reports that it would bill an API key instead, the run is stopped.

public enum ClaudeCodeError: LocalizedError, Equatable {
    case notInstalled
    /// Carries what Claude Code said, so the person (and we) can see the real reason.
    case notLoggedIn(String)
    case wouldBill(String)
    case usageLimit(String)
    case failed(String)

    public var needsLogin: Bool {
        if case .notLoggedIn = self { return true }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Claude Code isn't installed. Follow the setup steps in Settings → AI engine."
        case .notLoggedIn(let message):
            return "Claude Code couldn't use your Claude account, so you need to log in again (this happens when a login expires). Click “Log in” and choose your Claude account in the browser, then build again. Claude Code said: \(message)"
        case .wouldBill(let source):
            return "Stopped: Claude Code is set up to bill an API key (\(source)) instead of your Claude plan. Log in with your Claude account (Settings → AI engine) and remove ANTHROPIC_API_KEY from your shell."
        case .usageLimit(let message):
            return "You've hit your Claude plan's usage limit: \(message). It resets soon; free mode works in the meantime."
        case .failed(let message):
            return "Claude Code reported an error: \(message)"
        }
    }
}

/// What a `claude -p --output-format stream-json` run reports as it goes.
public enum ClaudeCodeEvent: Equatable {
    case initialized(apiKeySource: String, model: String)
    case text(String)
    case note(String)
    case searchQuery(String)
    case searchResults([SearchHit])
    /// Fraction (0–1) of the plan's 5-hour usage window used so far.
    case usage(Double)
}

/// Turns Claude Code's stream-json lines into events and a final result. Pure, so it's unit-tested
/// against output captured from the real CLI.
public final class ClaudeCodeStreamParser {
    public private(set) var resultText: String?
    public private(set) var structured: Any?
    public private(set) var isError = false
    public private(set) var errorMessage: String?
    public private(set) var hits: [SearchHit] = []
    public private(set) var finished = false

    public init() {}

    public func handle(_ line: String) -> [ClaudeCodeEvent] {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? JSON else { return [] }
        switch obj["type"] as? String {
        case "system" where obj["subtype"] as? String == "init":
            return [.initialized(apiKeySource: obj["apiKeySource"] as? String ?? "unknown",
                                 model: obj["model"] as? String ?? "")]

        case "stream_event":
            let event = obj["event"] as? JSON
            guard event?["type"] as? String == "content_block_delta",
                  let delta = event?["delta"] as? JSON, delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String, !text.isEmpty else { return [] }
            return [.text(text)]

        case "assistant":
            let blocks = (obj["message"] as? JSON)?["content"] as? [JSON] ?? []
            var events: [ClaudeCodeEvent] = []
            let usesTool = blocks.contains { $0["type"] as? String == "tool_use" }
            for b in blocks {
                switch b["type"] as? String {
                case "tool_use" where b["name"] as? String == "WebSearch":
                    if let q = (b["input"] as? JSON)?["query"] as? String { events.append(.searchQuery(q)) }
                case "text" where usesTool:
                    // A short note written before a tool call: show it as progress.
                    if let t = (b["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                        events.append(.note(t))
                    }
                default: break
                }
            }
            return events

        case "user":
            let blocks = (obj["message"] as? JSON)?["content"] as? [JSON] ?? []
            var found: [SearchHit] = []
            for b in blocks where b["type"] as? String == "tool_result" {
                found += Self.links(in: Self.text(of: b["content"]))
            }
            guard !found.isEmpty else { return [] }
            hits += found
            return [.searchResults(found)]

        case "rate_limit_event":
            let windows = (obj["rate_limit_info"] as? JSON)?["unifiedWindows"] as? JSON
            if let u = (windows?["five_hour"] as? JSON)?["utilization"] as? Double { return [.usage(u)] }
            return []

        case "result":
            finished = true
            isError = obj["is_error"] as? Bool ?? (obj["subtype"] as? String != "success")
            resultText = obj["result"] as? String
            structured = obj["structured_output"]
            if isError {
                let errors = (obj["errors"] as? [String])?.joined(separator: "; ")
                errorMessage = resultText ?? errors ?? (obj["subtype"] as? String)
            }
            return []

        default:
            return []
        }
    }

    static func text(of content: Any?) -> String {
        if let s = content as? String { return s }
        if let blocks = content as? [JSON] { return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        return ""
    }

    /// Web search results arrive as text containing `Links: [{"title":…,"url":…}, …]`.
    static func links(in text: String) -> [SearchHit] {
        guard let start = text.range(of: "Links: [") else { return [] }
        let tail = text[text.index(before: start.upperBound)...]
        var depth = 0, inString = false, escaped = false
        var end: String.Index?
        for i in tail.indices {
            let c = tail[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == "[" { depth += 1 }
            else if c == "]" { depth -= 1; if depth == 0 { end = i; break } }
        }
        guard let end, let array = (try? JSONSerialization.jsonObject(with: Data(String(tail[...end]).utf8))) as? [JSON] else {
            return []
        }
        return array.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            return SearchHit(title: item["title"] as? String ?? url, url: url)
        }
    }
}

/// Launches the Claude Code CLI.
public struct ClaudeCodeRunner {
    public enum Model: String, CaseIterable, Identifiable, Sendable {
        case sonnet, opus
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .sonnet: return "Sonnet — fast, uses less of your limits"
            case .opus: return "Opus — best quality, uses more of your limits"
            }
        }
    }

    public var executable: URL
    public var searchPath: String
    public var model: Model

    public init(executable: URL, searchPath: String, model: Model = .sonnet) {
        self.executable = executable
        self.searchPath = searchPath
        self.model = model
    }

    public struct Output {
        public var text: String
        public var structured: Any?
        public var hits: [SearchHit]
    }

    /// One `claude -p` run. `content` is the user message (text, images, PDFs).
    public func run(
        system: String,
        content: [JSON],
        tools: [String],
        schema: JSON?,
        effort: String,
        maxTurns: Int = 30,
        onEvent: @escaping @MainActor (ClaudeCodeEvent) -> Void
    ) async throws -> Output {
        var args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--model", model.rawValue,
            "--effort", effort,
            "--system-prompt", system,
            "--tools", tools.joined(separator: ","),
            "--permission-mode", "dontAsk",
            "--no-session-persistence",
            // Only the (empty) working folder's settings: ignores any API-key helper in user settings.
            "--setting-sources", "project",
            "--strict-mcp-config",
            "--max-turns", String(maxTurns),
        ]
        if !tools.isEmpty { args += ["--allowedTools", tools.joined(separator: ",")] }
        if let schema {
            let data = try JSONSerialization.data(withJSONObject: schema)
            args += ["--json-schema", String(decoding: data, as: UTF8.self)]
        }
        let message: JSON = ["type": "user", "message": ["role": "user", "content": content] as JSON]
        let input = try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8)

        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = Self.environment(searchPath: searchPath)
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("studysprint-claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = workDir

        let stdin = Pipe(), stdout = Pipe()
        // stderr goes to a file so a chatty CLI can never block on a full pipe.
        let errURL = workDir.appendingPathComponent("stderr-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let errHandle = try FileHandle(forWritingTo: errURL)
        defer {
            try? errHandle.close()
            try? FileManager.default.removeItem(at: errURL)
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = errHandle

        let parser = ClaudeCodeStreamParser()

        try process.run()
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()

        let refusedSource: String? = try await withTaskCancellationHandler {
            for try await line in stdout.fileHandleForReading.bytes.lines {
                for event in parser.handle(line) {
                    if case .initialized(let source, _) = event, source != "none" {
                        // An API key would be billed: stop before any request is made with it.
                        process.terminate()
                        return source
                    }
                    await onEvent(event)
                }
                if parser.finished { break }
            }
            return nil
        } onCancel: {
            process.terminate()
        }
        try Task.checkCancellation()
        if let refusedSource { throw ClaudeCodeError.wouldBill(refusedSource) }

        if !parser.finished {
            process.waitUntilExit()
            let err = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
            throw Self.classify(err.isEmpty ? "Claude Code exited without an answer (code \(process.terminationStatus))." : err)
        }
        if parser.isError { throw Self.classify(parser.errorMessage ?? "Unknown error") }
        return Output(text: parser.resultText ?? "", structured: parser.structured, hits: parser.hits)
    }

    /// The person's environment, minus anything that would make Claude Code bill an API key.
    static func environment(searchPath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK",
                    "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"] {
            env.removeValue(forKey: key)
        }
        env["PATH"] = searchPath
        return env
    }

    static func classify(_ message: String) -> ClaudeCodeError {
        let m = message.lowercased()
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.contains("not logged in") || m.contains("/login") || m.contains("invalid api key")
            || m.contains("authentication_error") || m.contains("oauth token") || m.contains("api error: 401") {
            return .notLoggedIn(String(trimmed.prefix(300)))
        }
        if m.contains("usage limit") || m.contains("rate limit") || m.contains("limit reached") {
            return .usageLimit(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return .failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Finding and checking the CLI

    public struct Installation: Equatable, Sendable {
        public var executable: URL
        public var searchPath: String
        public var version: String
    }

    /// Looks for `claude` where the installers put it, then asks the login shell.
    public static func locate() -> Installation? {
        let home = NSHomeDirectory()
        let shellPath = loginShellOutput("printf %s \"$PATH\"") ?? ""
        let extra = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                     "\(home)/.npm-global/bin", "\(home)/.bun/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let searchPath = (shellPath.split(separator: ":").map(String.init) + extra)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ":")

        var candidates = extra.prefix(6).map { "\($0)/claude" }
        if let found = loginShellOutput("command -v claude"), found.hasPrefix("/") { candidates.insert(found, at: 0) }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let url = URL(fileURLWithPath: path)
        let version = (try? capture(url, ["--version"], searchPath: searchPath))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
        return Installation(executable: url, searchPath: searchPath, version: version)
    }

    public struct AuthStatus: Equatable, Sendable {
        public var loggedIn: Bool
        public var method: String
        /// Logged in with a Claude account (subscription), not an API key.
        public var usesSubscription: Bool { loggedIn && !method.lowercased().contains("api") }
    }

    public static func authStatus(_ install: Installation) -> AuthStatus {
        guard let out = try? capture(install.executable, ["auth", "status"], searchPath: install.searchPath),
              let json = parseAuthStatus(out) else { return AuthStatus(loggedIn: false, method: "") }
        return json
    }

    static func parseAuthStatus(_ out: String) -> AuthStatus? {
        guard let start = out.firstIndex(of: "{"), let end = out.lastIndex(of: "}"),
              let obj = (try? JSONSerialization.jsonObject(with: Data(String(out[start...end]).utf8))) as? JSON else { return nil }
        return AuthStatus(loggedIn: obj["loggedIn"] as? Bool ?? false, method: obj["authMethod"] as? String ?? "")
    }

    static func loginShellOutput(_ command: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let out = try? capture(URL(fileURLWithPath: shell), ["-l", "-c", command], searchPath: nil, timeout: 8) else { return nil }
        let line = out.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return line?.isEmpty == false ? line : nil
    }

    static func capture(_ url: URL, _ args: [String], searchPath: String?, timeout: TimeInterval = 20) throws -> String {
        let process = Process()
        process.executableURL = url
        process.arguments = args
        if let searchPath { process.environment = environment(searchPath: searchPath) }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

/// StudySprint on the person's Claude plan, through Claude Code.
public struct ClaudeCodeEngine: StudyEngine {
    /// nil when Claude Code isn't installed; every call then explains how to set it up.
    public var runner: ClaudeCodeRunner?

    public init(runner: ClaudeCodeRunner?) {
        self.runner = runner
    }

    private func requireRunner() throws -> ClaudeCodeRunner {
        guard let runner else { throw ClaudeCodeError.notInstalled }
        return runner
    }

    /// Uses plan usage, not money.
    public var isFree: Bool { false }
    public var canSearchWeb: Bool { true }

    private final class Counter { var characters = 0; var lastReported = 0 }

    public func generateGuide(
        _ request: GuideRequest,
        onEvent: @escaping @MainActor (ResearchEvent) -> Void
    ) async throws -> StudyGuide {
        await onEvent(.phase("Starting Claude on your plan…"))
        let content = Prompts.guideUserContent(request)
        let counter = Counter()
        let output = try await requireRunner().run(
            system: Prompts.guideSystemStructured, content: content,
            tools: ["WebSearch", "WebFetch"], schema: GuidePayload.schema,
            effort: request.depth.effort, maxTurns: 40
        ) { event in
            switch event {
            case .initialized: onEvent(.phase("Researching with your Claude plan…"))
            case .searchQuery(let q): onEvent(.searching(q))
            case .searchResults(let hits): onEvent(.found(hits))
            case .note(let n): onEvent(.note(n))
            case .usage(let u): onEvent(.note("Plan usage this 5-hour window: \(Int((u * 100).rounded()))%"))
            case .text(let t):
                counter.characters += t.count
                if counter.characters - counter.lastReported >= 120 {
                    counter.lastReported = counter.characters
                    onEvent(.writing(characters: counter.characters))
                }
            }
        }

        await onEvent(.phase("Assembling your sprint…"))
        var payload: GuidePayload?
        if let structured = output.structured, JSONSerialization.isValidJSONObject(structured),
           let data = try? JSONSerialization.data(withJSONObject: structured) {
            payload = try? JSONDecoder().decode(GuidePayload.self, from: data)
        }
        guard let payload = payload ?? GuidePayload.decode(from: output.text) else { throw APIError.unparseable }
        var guide = payload.toGuide(request: request, searchHits: output.hits)
        guide.buildCost = nil
        return guide
    }

    public func tutorReply(
        system: String,
        history: [ChatTurn],
        onText: @escaping @MainActor (String) -> Void,
        onStatus: @escaping @MainActor (String) -> Void
    ) async throws -> ChatTurn {
        let output = try await requireRunner().run(
            system: system,
            content: [["type": "text", "text": Self.transcript(history)]],
            tools: ["WebSearch"], schema: nil, effort: "low", maxTurns: 8
        ) { event in
            switch event {
            case .text(let t): onText(t)
            case .searchQuery(let q): onStatus("Searching: \(q)")
            default: break
            }
        }
        return ChatTurn(role: .assistant, text: output.text)
    }

    /// `claude -p` is one-shot, so earlier turns are passed as a transcript.
    static func transcript(_ history: [ChatTurn]) -> String {
        guard let last = history.last else { return "" }
        let earlier = history.dropLast()
        if earlier.isEmpty { return last.text }
        let lines = earlier.map { "\($0.role == .user ? "Learner" : "Tutor"): \($0.text)" }
        return """
        <conversation_so_far>
        \(lines.joined(separator: "\n\n"))
        </conversation_so_far>

        Learner's new message (reply to this as the tutor):
        \(last.text)
        """
    }

    public func structured(system: String, prompt: String, schema: JSON, effort: String) async throws -> JSON {
        let output = try await requireRunner().run(system: system, content: [["type": "text", "text": prompt]],
                                          tools: [], schema: schema, effort: effort, maxTurns: 4) { _ in }
        if let json = output.structured as? JSON { return json }
        guard let json = LocalEngine.parseJSONObject(output.text) else { throw APIError.unparseable }
        return json
    }
}
