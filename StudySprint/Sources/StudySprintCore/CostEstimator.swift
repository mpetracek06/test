import Foundation

/// Rough API cost from a response's `usage`, using list prices. Good enough to show "≈ $0.12".
public enum CostEstimator {
    struct Price { let input: Double; let output: Double } // USD per million tokens

    static func price(for model: String) -> Price {
        if model.hasPrefix("claude-fable") || model.hasPrefix("claude-mythos") { return Price(input: 10, output: 50) }
        if model.hasPrefix("claude-opus-5-5") { return Price(input: 4, output: 20) }
        if model.hasPrefix("claude-opus") { return Price(input: 5, output: 25) }
        if model.hasPrefix("claude-sonnet-4") { return Price(input: 3, output: 15) }
        if model.hasPrefix("claude-sonnet") { return Price(input: 2, output: 10) }
        if model.hasPrefix("claude-haiku") { return Price(input: 1, output: 5) }
        return Price(input: 4, output: 20)
    }

    static let webSearchPrice = 0.01 // per search

    public static func dollars(model: String, usage: JSON?) -> Double {
        guard let usage else { return 0 }
        func n(_ key: String) -> Double { Double(usage[key] as? Int ?? 0) }
        let p = price(for: model)
        let input = n("input_tokens") * p.input
            + n("cache_creation_input_tokens") * p.input * 1.25
            + n("cache_read_input_tokens") * p.input * 0.1
        let output = n("output_tokens") * p.output
        let searches = Double((usage["server_tool_use"] as? JSON)?["web_search_requests"] as? Int ?? 0)
        return (input + output) / 1_000_000 + searches * webSearchPrice
    }

    public struct Tally {
        public var model: String
        public private(set) var dollars: Double = 0

        public init(model: String) { self.model = model }

        public mutating func add(_ message: AssembledMessage) {
            dollars += CostEstimator.dollars(model: message.model ?? model, usage: message.usage)
        }
    }

    public static func format(_ dollars: Double) -> String {
        dollars < 0.01 ? "<$0.01" : String(format: "$%.2f", dollars)
    }
}
