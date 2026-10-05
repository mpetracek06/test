import SwiftUI
import StudySprintCore

/// A picture from the learner's notes with Claude's explanation. Click to enlarge.
struct FigureCard: View {
    let figure: GuideFigure
    var number: Int? = nil
    var compact = false
    @State private var enlarged = false

    var body: some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                             : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            Button {
                enlarged = true
            } label: {
                FigureImage(figure: figure)
                    .frame(width: compact ? nil : 260)
                    .frame(maxWidth: compact ? .infinity : 260, maxHeight: compact ? 260 : 200)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.bold())
                            .padding(5)
                            .background(Circle().fill(.ultraThinMaterial))
                            .padding(6)
                    }
            }
            .buttonStyle(.plain)
            .help("Enlarge")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "photo").foregroundStyle(Color.indigo)
                    Text(number.map { "Figure \($0) · \(figure.title)" } ?? figure.title)
                        .font(.subheadline.bold())
                }
                if figure.explanation.isEmpty {
                    Text("From your notes. (Pick a model that can see pictures to get an explanation.)")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    MarkdownText(figure.explanation)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !figure.notice.isEmpty {
                    Text("Look for").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 2)
                    BulletList(items: figure.notice, bullet: "→", color: .indigo)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.indigo.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.indigo.opacity(0.15)))
        .sheet(isPresented: $enlarged) { FigureViewer(figure: figure, number: number) }
    }
}

struct FigureImage: View {
    let figure: GuideFigure

    var body: some View {
        if let image = FigureStore.image(for: figure) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 120)
                .overlay(Image(systemName: "photo").font(.title).foregroundStyle(.secondary))
        }
    }
}

struct FigureViewer: View {
    let figure: GuideFigure
    var number: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FigureImage(figure: figure)
                .padding(20)
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(number.map { "Figure \($0)" } ?? "Figure").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(figure.title).font(.title2.bold())
                    if !figure.explanation.isEmpty {
                        HStack(alignment: .top) {
                            MarkdownText(figure.explanation).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            SpeakButton(id: "figure-\(figure.id)", text: figure.explanation)
                        }
                    }
                    if !figure.notice.isEmpty {
                        Text("Look for").font(.headline).padding(.top, 4)
                        BulletList(items: figure.notice, bullet: "→", color: .indigo)
                    }
                }
                .padding(20)
            }
            .frame(width: 340)
        }
        .frame(minWidth: 960, minHeight: 600)
        .overlay(alignment: .topTrailing) {
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .padding(12)
        }
    }
}
