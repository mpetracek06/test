import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One chat message for a local model.
public struct LocalMessage: Sendable {
    public var role: String
    public var content: String
    public var images: [Data]

    public init(role: String, content: String, images: [Data] = []) {
        self.role = role
        self.content = content
        self.images = images
    }
}

/// Anything that can run a chat completion: the real Ollama client, or a fake in tests.
public protocol ChatBackend {
    var modelName: String { get }
    /// Returns the full reply. When `schema` is set the reply is constrained to that JSON schema.
    func chat(system: String, messages: [LocalMessage], schema: JSON?,
              onText: (@MainActor (String) -> Void)?) async throws -> String
}

public enum LocalModelError: LocalizedError, Equatable {
    case notRunning
    case modelMissing(String)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Ollama isn't running. Open the Ollama app (it lives in your menu bar), then try again."
        case .modelMissing(let model):
            return "The free model “\(model)” isn't downloaded yet. Download it in Settings → AI engine."
        case .server(let message):
            return "The local model reported an error: \(message)"
        }
    }
}

/// Talks to Ollama (https://ollama.com), a free app that runs open models on your Mac.
public struct OllamaClient: ChatBackend {
    public static let defaultURL = URL(string: "http://127.0.0.1:11434")!

    public var baseURL: URL
    public var model: String
    /// Context window to request; long notes need more.
    public var contextTokens: Int

    public var modelName: String { model }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900   // a cold model can take a while to load
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }()

    public init(model: String, baseURL: URL = OllamaClient.defaultURL, contextTokens: Int = 16_384) {
        self.model = model
        self.baseURL = baseURL
        self.contextTokens = contextTokens
    }

    // MARK: Chat

    public func chat(system: String, messages: [LocalMessage], schema: JSON?,
                     onText: (@MainActor (String) -> Void)?) async throws -> String {
        var all: [JSON] = [["role": "system", "content": system]]
        for m in messages {
            var msg: JSON = ["role": m.role, "content": m.content]
            if !m.images.isEmpty { msg["images"] = m.images.map { $0.base64EncodedString() } }
            all.append(msg)
        }
        // Size the context to the prompt: ~4 characters per token, plus room for the answer.
        let promptChars = system.count + messages.reduce(0) { $0 + $1.content.count }
        let ctx = min(65_536, max(contextTokens, promptChars / 3 + 8_192))

        var body: JSON = [
            "model": model,
            "messages": all,
            "stream": true,
            "keep_alive": "15m",
            "options": ["num_ctx": ctx, "temperature": schema == nil ? 0.6 : 0.3] as JSON,
        ]
        if let schema { body["format"] = schema }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await perform(request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code != 200 {
            var data = Data()
            for try await b in bytes { data.append(b) }
            throw Self.error(code: code, body: data, model: model)
        }

        var reply = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let chunk = Self.parseChunk(line) else { continue }
            if let error = chunk.error { throw LocalModelError.server(error) }
            if !chunk.text.isEmpty {
                reply += chunk.text
                if let onText { await onText(chunk.text) }
            }
            if chunk.done { break }
        }
        return Self.stripThinking(reply)
    }

    struct Chunk: Equatable {
        var text: String
        var done: Bool
        var error: String?
    }

    /// One line of Ollama's streaming NDJSON.
    static func parseChunk(_ line: String) -> Chunk? {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? JSON else { return nil }
        if let error = obj["error"] as? String { return Chunk(text: "", done: true, error: error) }
        let text = (obj["message"] as? JSON)?["content"] as? String ?? obj["response"] as? String ?? ""
        return Chunk(text: text, done: obj["done"] as? Bool ?? false, error: nil)
    }

    /// Reasoning models may prefix their answer with <think>…</think>; drop it.
    static func stripThinking(_ s: String) -> String {
        guard let end = s.range(of: "</think>") else { return s }
        return String(s[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Model management

    public struct InstalledModel: Hashable, Sendable {
        public var name: String
        public var sizeBytes: Int64
    }

    public func version() async throws -> String {
        let json = try await getJSON("api/version")
        return json["version"] as? String ?? "?"
    }

    public func installedModels() async throws -> [InstalledModel] {
        let json = try await getJSON("api/tags")
        let models = json["models"] as? [JSON] ?? []
        return models.compactMap { m in
            guard let name = m["name"] as? String else { return nil }
            return InstalledModel(name: name, sizeBytes: (m["size"] as? NSNumber)?.int64Value ?? 0)
        }
    }

    public struct PullProgress: Sendable, Equatable {
        public var status: String
        public var completed: Int64
        public var total: Int64
        public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    /// Downloads a model, reporting progress. Safe to call again to resume.
    public func pull(_ name: String, onProgress: @escaping @MainActor (PullProgress) -> Void) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": name, "stream": true])
        let (bytes, response) = try await perform(request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code != 200 {
            var data = Data()
            for try await b in bytes { data.append(b) }
            throw Self.error(code: code, body: data, model: name)
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? JSON else { continue }
            if let error = obj["error"] as? String { throw LocalModelError.server(error) }
            let progress = PullProgress(status: obj["status"] as? String ?? "",
                                        completed: (obj["completed"] as? NSNumber)?.int64Value ?? 0,
                                        total: (obj["total"] as? NSNumber)?.int64Value ?? 0)
            await onProgress(progress)
            if progress.status == "success" { break }
        }
    }

    // MARK: Helpers

    private func getJSON(_ path: String) async throws -> JSON {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 5
        do {
            let (data, _) = try await Self.session.data(for: request)
            return (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
        } catch let e as URLError where Self.isConnectionFailure(e) {
            throw LocalModelError.notRunning
        }
    }

    private func perform(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await Self.session.bytes(for: request)
        } catch let e as URLError where Self.isConnectionFailure(e) {
            throw LocalModelError.notRunning
        }
    }

    static func isConnectionFailure(_ e: URLError) -> Bool {
        [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut].contains(e.code)
    }

    static func error(code: Int, body: Data, model: String) -> LocalModelError {
        let message = ((try? JSONSerialization.jsonObject(with: body)) as? JSON)?["error"] as? String
            ?? String(data: body, encoding: .utf8) ?? "HTTP \(code)"
        if code == 404 || message.contains("not found") { return .modelMissing(model) }
        return .server(message)
    }
}
