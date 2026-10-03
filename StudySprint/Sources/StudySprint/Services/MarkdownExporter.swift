import Foundation

enum MarkdownExporter {
    static func markdown(for g: StudyGuide) -> String {
        var md = "# \(g.topic) — study sprint (\(g.totalMinutes) min)\n\n"
        md += "**TL;DR:** \(g.tldr)\n\n"
        md += "## The 20% that gets you 80%\n"
        g.paretoConcepts.forEach { md += "- \($0)\n" }
        md += "\n## Learning path\n"
        for (i, s) in g.steps.enumerated() {
            md += "\n### \(i + 1). \(s.title) (\(s.minutes) min)\(s.done ? " ✅" : "")\n"
            md += "_Why:_ \(s.why)\n\n\(s.explanation)\n\n"
            s.keyPoints.forEach { md += "- \($0)\n" }
            if !s.videos.isEmpty {
                md += "\n**Videos**\n"
                s.videos.forEach { md += "- [\($0.title)](\($0.url)) — \($0.channel), \($0.duration). \($0.watchTip)\n" }
            }
            if !s.activeRecall.isEmpty {
                md += "\n**Recall check**\n"
                s.activeRecall.forEach { md += "- \($0)\n" }
            }
        }
        md += "\n## Common mistakes\n"
        g.commonMistakes.forEach { md += "- \($0)\n" }
        md += "\n## Safe to skip (for now)\n"
        g.skipList.forEach { md += "- \($0)\n" }
        md += "\n## Final self-test\n"
        g.selfTest.enumerated().forEach { md += "\($0.offset + 1). \($0.element)\n" }
        md += "\n## Flashcards\n"
        g.flashcards.forEach { md += "- **Q:** \($0.front)  \n  **A:** \($0.back)\n" }
        return md
    }
}
