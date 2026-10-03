import Foundation

public enum MarkdownExporter {
    public static func markdown(for g: StudyGuide, includeProgress: Bool = true, includeFlashcards: Bool = true) -> String {
        var md = "# \(g.emoji) \(g.topic) — study sprint (\(g.totalMinutes) min)\n\n"
        md += "**TL;DR:** \(g.tldr)\n\n"
        md += "## The 20% that gets you 80%\n"
        g.paretoConcepts.forEach { md += "- \($0)\n" }
        md += "\n## Learning path\n"
        for (i, s) in g.steps.enumerated() {
            let mark = includeProgress ? (s.status == .done ? " ✅" : s.status == .testedOut ? " ⏭️ tested out" : "") : ""
            md += "\n### \(i + 1). \(s.title) (\(s.minutes) min)\(mark)\n"
            if !s.prerequisites.isEmpty {
                md += "_Builds on step \(s.prerequisites.map(String.init).joined(separator: ", "))._\n"
            }
            md += "_Why now:_ \(s.why)\n\n\(s.explanation)\n\n"
            if !s.analogy.isEmpty { md += "**Analogy:** \(s.analogy)\n\n" }
            s.keyPoints.forEach { md += "- \($0)\n" }
            if !s.videos.isEmpty {
                md += "\n**Videos**\n"
                for v in s.videos {
                    var segment = ""
                    if v.startSeconds > 0 || v.endSeconds > 0 {
                        segment = " Watch \(YouTube.timestamp(v.startSeconds))–\(v.endSeconds > 0 ? YouTube.timestamp(v.endSeconds) : "end")"
                    }
                    let speed = v.playbackSpeed != 1 ? String(format: " at %.2gx.", v.playbackSpeed) : (segment.isEmpty ? "" : ".")
                    md += "- [\(v.title)](\(v.url)) — \(v.channel), \(v.duration).\(segment)\(speed) \(v.watchTip)\n"
                }
            }
            if !s.activeRecall.isEmpty {
                md += "\n**Recall check**\n"
                s.activeRecall.forEach { md += "- \($0)\n" }
            }
        }
        if !g.mnemonics.isEmpty {
            md += "\n## Memory aids\n"
            g.mnemonics.forEach { md += "- \($0)\n" }
        }
        md += "\n## Common mistakes\n"
        g.commonMistakes.forEach { md += "- \($0)\n" }
        md += "\n## Safe to skip (for now)\n"
        g.skipList.forEach { md += "- \($0)\n" }
        md += "\n## Final self-test\n"
        g.selfTest.enumerated().forEach { md += "\($0.offset + 1). \($0.element)\n" }
        if includeFlashcards && !g.flashcards.isEmpty {
            md += "\n## Flashcards\n"
            g.flashcards.forEach { md += "- **Q:** \($0.front)  \n  **A:** \($0.back)\n" }
        }
        return md
    }
}

/// Lays steps out in columns by how deep their prerequisite chain goes.
public enum KnowledgeMapLayout {
    /// depth[i] for each step i (0-based). Steps with no prerequisites are depth 0.
    public static func depths(for steps: [StudyStep]) -> [Int] {
        // No dependency info at all: show the path as a simple chain.
        if steps.allSatisfy({ $0.prerequisites.isEmpty }) { return Array(steps.indices) }
        var depth = [Int](repeating: 0, count: steps.count)
        for (i, step) in steps.enumerated() {
            let parents = step.prerequisites.map { $0 - 1 }.filter { $0 >= 0 && $0 < i }
            depth[i] = parents.isEmpty ? 0 : (parents.map { depth[$0] }.max() ?? 0) + 1
        }
        return depth
    }
}
