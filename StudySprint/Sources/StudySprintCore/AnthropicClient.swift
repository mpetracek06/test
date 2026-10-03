import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias JSON = [String: Any]

public enum ClaudeModel: String, CaseIterable, Identifiable, Sendable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case fable = "claude-fable-5-1"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .opus: return "Claude Opus 5.5 — best balance (recommended)"
        case .sonnet: return "Claude Sonnet 5.5 — faster & cheaper"
        case .fable: return "Claude Fable 5.1 — most capable, slowest, priciest"
        }
    }
}

public enum APIError: LocalizedError, Equatable {
    case missingKey
    case http(Int, String)
    case refusal(String?)
    case badResponse
    case unparseable

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add your Anthropic API key in Settings (⌘,) first."
        case .http(let code, let message):
            switch code {
            case 401: return "Your API key was rejected. Check it in Settings (⌘,)."
            case 429: return "Rate limited by the Claude API. Wait a moment and try again."
            case 529: return "Claude is overloaded right now. Try again in a minute."
            default: return "Claude API error \(code): \(message)"
            }
        case .refusal(let explanation):
            return "Claude declined this request." + (explanation.map { " \($0)" } ?? "")
        case .badResponse:
            return "Got an unexpected response from the Claude API."
        case .unparseable:
            return "Claude's answer couldn't be turned into a study guide. Try again."
        }
    }
}

/// Live events surfaced while a response streams in.
public enum StreamUpdate: Sendable, Equatable {
    case started(model: String)
    case text(String)
    case progressNote(String)
    case searchQuery(String)
    case searchResults([SearchHit])
    case fallback(toModel: String)
}

/// Thin HTTP client for the Claude Messages API (Swift has no official SDK).
public struct AnthropicClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    public static let progressUpdatesBeta = "thinking-display-updates-2026-08-18"

    public var apiKey: String
    public var model: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600   // idle gap allowed between bytes
        config.timeoutIntervalForResource = 1800 // whole request
        return URLSession(configuration: config)
    }()

    public init(apiKey: String, model: String = ClaudeModel.opus.rawValue) {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: Non-streaming

    public func send(_ body: JSON, betas: [String] = []) async throws -> AssembledMessage {
        var full = body
        full["model"] = model
        let request = try makeRequest(full, betas: betas)
        let data = try await withRetries { () -> Data in
            let (data, response) = try await Self.session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 { throw Self.httpError(code: code, body: data) }
            return data
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { throw APIError.badResponse }
        return AssembledMessage(json: json)
    }

    // MARK: Streaming

    public func stream(
        _ body: JSON,
        betas: [String] = [],
        onUpdate: @escaping @MainActor (StreamUpdate) -> Void
    ) async throws -> AssembledMessage {
        var full = body
        full["model"] = model
        full["stream"] = true
        let request = try makeRequest(full, betas: betas)

        let bytes = try await withRetries { () -> URLSession.AsyncBytes in
            let (bytes, response) = try await Self.session.bytes(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                var data = Data()
                for try await byte in bytes { data.append(byte) }
                throw Self.httpError(code: code, body: data)
            }
            return bytes
        }

        let accumulator = MessageAccumulator()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { continue }
            for update in try accumulator.handle(event) {
                await onUpdate(update)
            }
            if accumulator.finished { break }
        }
        return accumulator.message
    }

    // MARK: Helpers

    private func makeRequest(_ body: JSON, betas: [String]) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw APIError.missingKey }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if !betas.isEmpty {
            request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func withRetries<T>(_ operation: () async throws -> T) async throws -> T {
        var delay: UInt64 = 2_000_000_000
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch APIError.http(let code, _) where (code == 429 || code == 529 || code >= 500) && attempt < 2 {
                attempt += 1
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }
    }

    static func httpError(code: Int, body: Data) -> APIError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? JSON
        let message = (json?["error"] as? JSON)?["message"] as? String
            ?? String(data: body, encoding: .utf8) ?? "Unknown error"
        return .http(code, message)
    }
}

/// A complete (or reassembled) Messages API response.
public struct AssembledMessage {
    public var content: [JSON]
    public var stopReason: String?
    public var stopDetails: JSON?
    public var model: String?
    public var usage: JSON?

    public init(content: [JSON] = [], stopReason: String? = nil, stopDetails: JSON? = nil,
                model: String? = nil, usage: JSON? = nil) {
        self.content = content
        self.stopReason = stopReason
        self.stopDetails = stopDetails
        self.model = model
        self.usage = usage
    }

    init(json: JSON) {
        self.init(content: json["content"] as? [JSON] ?? [],
                  stopReason: json["stop_reason"] as? String,
                  stopDetails: json["stop_details"] as? JSON,
                  model: json["model"] as? String,
                  usage: json["usage"] as? JSON)
    }

    /// All text, concatenated. Citations split one answer into many text blocks, so join without separators.
    public var text: String {
        content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
    }

    /// Every URL returned by web search in this message.
    public var searchHits: [SearchHit] {
        content.flatMap(MessageAccumulator.hits(in:))
    }

    public func throwIfRefused() throws {
        if stopReason == "refusal" {
            throw APIError.refusal(stopDetails?["explanation"] as? String)
        }
    }

    /// Content safe to send back as an assistant turn. After a mid-response fallback, blocks
    /// from the declined attempt that the fallback model can't accept are dropped.
    public var contentForEcho: [JSON] {
        guard let boundary = content.lastIndex(where: { $0["type"] as? String == "fallback" }) else {
            return content
        }
        let resultIDs = Set(content.compactMap { block -> String? in
            guard (block["type"] as? String)?.hasSuffix("_tool_result") == true else { return nil }
            return block["tool_use_id"] as? String
        })
        let dropTypes: Set<String> = ["thinking", "redacted_thinking", "tool_use"]
        let known: Set<String> = ["text", "server_tool_use", "web_search_tool_result", "web_fetch_tool_result", "fallback"]
        return content.enumerated().compactMap { (index, block) -> JSON? in
            guard index < boundary else { return block }
            let type = block["type"] as? String ?? ""
            if dropTypes.contains(type) { return nil }
            if type == "server_tool_use" {
                return resultIDs.contains(block["id"] as? String ?? "") ? block : nil
            }
            return known.contains(type) || type.hasSuffix("_tool_result") ? block : nil
        }
    }

    /// JSON data for persisting an assistant turn.
    public var echoData: Data? {
        try? JSONSerialization.data(withJSONObject: contentForEcho)
    }
}

/// Rebuilds a full message from server-sent events, and reports interesting moments as they happen.
public final class MessageAccumulator {
    public private(set) var blocks: [JSON] = []
    public private(set) var stopReason: String?
    public private(set) var stopDetails: JSON?
    public private(set) var model: String?
    public private(set) var usage: JSON?
    public private(set) var finished = false

    private var positions: [Int: Int] = [:]  // stream index -> position in `blocks`
    private var partialJSON: [Int: String] = [:]

    public init() {}

    public var message: AssembledMessage {
        AssembledMessage(content: blocks, stopReason: stopReason, stopDetails: stopDetails, model: model, usage: usage)
    }

    public func handle(_ event: JSON) throws -> [StreamUpdate] {
        switch event["type"] as? String {
        case "message_start":
            let message = event["message"] as? JSON
            model = message?["model"] as? String ?? model
            if let u = message?["usage"] as? JSON { usage = u }
            if let model { return [StreamUpdate.started(model: model)] }
            return []

        case "content_block_start":
            guard let index = event["index"] as? Int, var block = event["content_block"] as? JSON else { return [] }
            let type = block["type"] as? String ?? ""
            switch type {
            case "text": if block["text"] == nil { block["text"] = "" }
            case "thinking": if block["thinking"] == nil { block["thinking"] = "" }
            case "tool_use", "server_tool_use": partialJSON[index] = ""
            default: break
            }
            positions[index] = blocks.count
            blocks.append(block)
            var updates: [StreamUpdate] = []
            if type == "text", let t = block["text"] as? String, !t.isEmpty { updates.append(.text(t)) }
            if type == "web_search_tool_result" {
                let hits = Self.hits(in: block)
                if !hits.isEmpty { updates.append(.searchResults(hits)) }
            }
            if type == "fallback" {
                let to = (block["to"] as? JSON)?["model"] as? String ?? "another model"
                updates.append(.fallback(toModel: to))
            }
            return updates

        case "content_block_delta":
            guard let index = event["index"] as? Int, let pos = positions[index],
                  let delta = event["delta"] as? JSON else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                let t = delta["text"] as? String ?? ""
                blocks[pos]["text"] = (blocks[pos]["text"] as? String ?? "") + t
                return t.isEmpty ? [] : [.text(t)]
            case "thinking_delta":
                blocks[pos]["thinking"] = (blocks[pos]["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta":
                blocks[pos]["signature"] = delta["signature"]
            case "input_json_delta":
                partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
            case "citations_delta":
                if let citation = delta["citation"] {
                    var list = blocks[pos]["citations"] as? [Any] ?? []
                    list.append(citation)
                    blocks[pos]["citations"] = list
                }
            default:
                break
            }
            return []

        case "content_block_stop":
            guard let index = event["index"] as? Int, let pos = positions[index] else { return [] }
            var updates: [StreamUpdate] = []
            if let raw = partialJSON.removeValue(forKey: index) {
                let input = raw.isEmpty ? JSON() : ((try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? JSON ?? JSON())
                blocks[pos]["input"] = input
                if blocks[pos]["type"] as? String == "server_tool_use",
                   blocks[pos]["name"] as? String == "web_search",
                   let query = input["query"] as? String {
                    updates.append(.searchQuery(query))
                }
            }
            if blocks[pos]["type"] as? String == "thinking",
               let note = (blocks[pos]["thinking"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !note.isEmpty {
                updates.append(.progressNote(note))
            }
            return updates

        case "message_delta":
            if let delta = event["delta"] as? JSON {
                if let reason = delta["stop_reason"] as? String { stopReason = reason }
                if let details = delta["stop_details"] as? JSON { stopDetails = details }
            }
            if let u = event["usage"] as? JSON {
                var merged = usage ?? JSON()
                for (k, v) in u { merged[k] = v }
                usage = merged
            }
            return []

        case "message_stop":
            finished = true
            return []

        case "error":
            let error = event["error"] as? JSON
            let type = error?["type"] as? String ?? ""
            let message = error?["message"] as? String ?? "Stream error"
            throw APIError.http(type == "overloaded_error" ? 529 : 500, message)

        default: // ping and anything new
            return []
        }
    }

    static func hits(in block: JSON) -> [SearchHit] {
        guard block["type"] as? String == "web_search_tool_result",
              let results = block["content"] as? [JSON] else { return [] } // an error result is an object, not a list
        return results.compactMap { r in
            guard let url = r["url"] as? String else { return nil }
            return SearchHit(title: r["title"] as? String ?? url, url: url)
        }
    }
}
