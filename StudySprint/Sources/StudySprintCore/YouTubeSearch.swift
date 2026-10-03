import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct YouTubeVideo: Hashable, Sendable {
    public var id: String
    public var title: String
    public var channel: String
    public var duration: String
    public var seconds: Int

    public var url: String { "https://www.youtube.com/watch?v=\(id)" }
}

/// Finds videos for a search query.
public protocol VideoFinder {
    func search(_ query: String, limit: Int) async throws -> [YouTubeVideo]
}

/// Free YouTube search: reads the public results page. No API key, no cost.
public struct YouTubeSearch: VideoFinder {
    public init() {}

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    public func search(_ query: String, limit: Int = 8) async throws -> [YouTubeVideo] {
        var comps = URLComponents(string: "https://www.youtube.com/results")!
        // sp=EgIQAQ== limits results to videos (no channels/playlists).
        comps.queryItems = [URLQueryItem(name: "search_query", value: query), URLQueryItem(name: "sp", value: "EgIQAQ==")]
        var request = URLRequest(url: comps.url!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // Skips the EU cookie-consent interstitial.
        request.setValue("SOCS=CAI; CONSENT=YES+1", forHTTPHeaderField: "Cookie")
        let (data, _) = try await Self.session.data(for: request)
        return Array(Self.parse(html: String(decoding: data, as: UTF8.self)).prefix(limit))
    }

    /// Picks the best video for studying: relevant (YouTube's order), short, not a stream.
    public static func pickBest(_ videos: [YouTubeVideo], count: Int = 1) -> [YouTubeVideo] {
        let ideal = videos.filter { $0.seconds >= 90 && $0.seconds <= 20 * 60 }
        let okay = videos.filter { $0.seconds > 0 && $0.seconds <= 45 * 60 }
        return Array((ideal.isEmpty ? okay : ideal).prefix(count))
    }

    // MARK: Parsing

    static func parse(html: String) -> [YouTubeVideo] {
        guard let json = extractInitialData(html) else { return [] }
        var found: [YouTubeVideo] = []
        var seen = Set<String>()
        collect(json, into: &found, seen: &seen)
        return found
    }

    /// Pulls the `ytInitialData = {...};` object out of the page by matching braces.
    static func extractInitialData(_ html: String) -> Any? {
        guard let marker = html.range(of: "ytInitialData = ") ?? html.range(of: "ytInitialData=") else { return nil }
        let u = html.utf8
        guard let start = u[marker.upperBound...].firstIndex(of: UInt8(ascii: "{")) else { return nil }
        let open = UInt8(ascii: "{"), close = UInt8(ascii: "}"), quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        var depth = 0, inString = false, escaped = false
        var i = start
        while i < u.endIndex {
            let c = u[i]
            if inString {
                if escaped { escaped = false }
                else if c == backslash { escaped = true }
                else if c == quote { inString = false }
            } else if c == quote {
                inString = true
            } else if c == open {
                depth += 1
            } else if c == close {
                depth -= 1
                if depth == 0 {
                    return try? JSONSerialization.jsonObject(with: Data(u[start...i]))
                }
            }
            i = u.index(after: i)
        }
        return nil
    }

    private static func collect(_ node: Any, into out: inout [YouTubeVideo], seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if let r = dict["videoRenderer"] as? [String: Any], let video = video(from: r), seen.insert(video.id).inserted {
                out.append(video)
            }
            for (key, value) in dict where key != "videoRenderer" { collect(value, into: &out, seen: &seen) }
        } else if let array = node as? [Any] {
            for value in array { collect(value, into: &out, seen: &seen) }
        }
    }

    private static func text(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        if let s = dict["simpleText"] as? String { return s }
        if let runs = dict["runs"] as? [[String: Any]] { return runs.compactMap { $0["text"] as? String }.joined() }
        return nil
    }

    private static func video(from r: [String: Any]) -> YouTubeVideo? {
        guard let id = r["videoId"] as? String, let title = text(r["title"]) else { return nil }
        let channel = text(r["ownerText"]) ?? text(r["longBylineText"]) ?? ""
        let duration = text(r["lengthText"]) ?? ""
        return YouTubeVideo(id: id, title: title, channel: channel, duration: duration, seconds: seconds(duration))
    }

    /// "1:02:03" → 3723, "12:34" → 754, "" (live) → 0
    static func seconds(_ duration: String) -> Int {
        let parts = duration.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count == duration.split(separator: ":").count else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
