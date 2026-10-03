import AppKit
import SwiftUI
import StudySprintCore

/// A dense, printable one-pager: everything you need to remember, nothing you don't.
struct CheatSheetView: View {
    let guide: StudyGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(guide.emoji) \(guide.topic)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Text("StudySprint cheat sheet").font(.system(size: 9)).foregroundColor(.gray)
            }
            Rectangle().fill(LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .leading, endPoint: .trailing))
                .frame(height: 3)

            Text(MarkdownText.attributed(guide.tldr)).font(.system(size: 11))

            section("Core ideas", items: guide.paretoConcepts, color: .pink)

            VStack(alignment: .leading, spacing: 8) {
                Text("KEY POINTS BY STEP").font(.system(size: 9, weight: .bold)).foregroundColor(.indigo)
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(i + 1). \(step.title)").font(.system(size: 11, weight: .semibold))
                        ForEach(Array(step.keyPoints.enumerated()), id: \.offset) { _, p in
                            Text("• ").font(.system(size: 10)) + Text(MarkdownText.attributed(p)).font(.system(size: 10))
                        }
                        if !step.analogy.isEmpty {
                            Text("≈ \(step.analogy)").font(.system(size: 9.5)).italic().foregroundColor(.gray)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                if !guide.mnemonics.isEmpty {
                    section("Memory aids", items: guide.mnemonics, color: .purple)
                }
                section("Traps", items: guide.commonMistakes, color: .orange)
            }
        }
        .padding(36)
        .frame(width: 612, alignment: .topLeading)
        .background(Color.white)
        .foregroundColor(.black)
        .environment(\.colorScheme, .light)
    }

    private func section(_ title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).foregroundColor(color)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text("• ").font(.system(size: 10)) + Text(MarkdownText.attributed(item)).font(.system(size: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum CheatSheetRenderer {
    enum RenderError: LocalizedError {
        case failed
        var errorDescription: String? { "Couldn't create the PDF." }
    }

    /// Renders the cheat sheet to a PDF, splitting it across US Letter pages as needed.
    @MainActor
    static func writePDF(for guide: StudyGuide, to url: URL) throws {
        let renderer = ImageRenderer(content: CheatSheetView(guide: guide))
        renderer.proposedSize = ProposedViewSize(width: 612, height: nil)
        let pageHeight: CGFloat = 792
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 612, height: pageHeight)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            let pages = max(1, Int(ceil(size.height / pageHeight)))
            for page in 0..<pages {
                ctx.beginPDFPage(nil)
                ctx.saveGState()
                // PDF origin is bottom-left; shift so this page's slice of the content is visible.
                let offset = size.height - pageHeight * CGFloat(page + 1)
                ctx.translateBy(x: 0, y: -offset)
                draw(ctx)
                ctx.restoreGState()
                ctx.endPDFPage()
            }
            ctx.closePDF()
            ok = true
        }
        if !ok { throw RenderError.failed }
    }
}
