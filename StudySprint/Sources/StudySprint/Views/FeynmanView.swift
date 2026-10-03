import SwiftUI
import StudySprintCore

/// The Feynman technique: explain it simply in your own words, then get graded on the gaps.
struct FeynmanView: View {
    @EnvironmentObject private var app: AppModel
    @Binding var guide: StudyGuide

    @State private var concept = ""
    @State private var explanation = ""
    @State private var grading = false
    @State private var error: String?
    @State private var result: FeynmanResult?

    private var concepts: [String] {
        var seen = Set<String>()
        return (guide.paretoConcepts.map(Self.conceptName) + guide.steps.map(\.title))
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// "**ATP is energy currency**: respiration…" → "ATP is energy currency"
    static func conceptName(_ s: String) -> String {
        if s.hasPrefix("**"), let end = s.dropFirst(2).range(of: "**") {
            return String(s[s.index(s.startIndex, offsetBy: 2)..<end.lowerBound])
        }
        let plain = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        return String(plain.split(separator: ":").first ?? Substring(plain)).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "person.wave.2.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.gradient)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Explain it like you're teaching").font(.title.bold())
                        Text("If you can't explain it simply, you don't understand it yet. Write an explanation for a smart 12-year-old — Claude grades it and shows you exactly what's missing.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Card {
                    HStack {
                        Text("Concept").foregroundStyle(.secondary)
                        Picker("", selection: $concept) {
                            ForEach(concepts, id: \.self) { Text($0).lineLimit(1).tag($0) }
                        }
                        .labelsHidden()
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $explanation)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                        if explanation.isEmpty {
                            Text("Explain “\(concept)” in your own words, as if to a 12-year-old…")
                                .foregroundStyle(.tertiary)
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 170)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))

                    HStack {
                        Text("\(explanation.split(whereSeparator: \.isWhitespace).count) words")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            grade()
                        } label: {
                            if grading {
                                ProgressView().controlSize(.small).padding(.horizontal, 30)
                            } else {
                                Label("Grade my explanation", systemImage: "sparkle.magnifyingglass")
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(grading || explanation.split(whereSeparator: \.isWhitespace).count < 8 || concept.isEmpty)
                    }
                }

                if let error { ErrorBanner(message: error) { self.error = nil } }
                if let result { ResultView(result: result) }

                if !guide.feynmanResults.isEmpty {
                    Card(title: "Your explanations", systemImage: "clock.arrow.circlepath") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(guide.feynmanResults.reversed()) { r in
                                Button {
                                    result = r
                                    concept = r.concept
                                } label: {
                                    HStack {
                                        ScoreBadge(score: r.score)
                                        Text(r.concept).lineLimit(1)
                                        Spacer()
                                        Text(r.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if concept.isEmpty { concept = concepts.first ?? "" }
        }
    }

    private func grade() {
        grading = true
        error = nil
        let services = app.services
        let snapshot = guide
        let c = concept, e = explanation
        Task { @MainActor in
            do {
                let r = try await services.gradeFeynman(concept: c, explanation: e, guide: snapshot)
                withAnimation { result = r }
                guide.feynmanResults.append(r)
                NSSound(named: r.score >= 85 ? "Hero" : "Pop")?.play()
            } catch {
                self.error = error.localizedDescription
            }
            grading = false
        }
    }
}

private struct ResultView: View {
    let result: FeynmanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Gauge(value: Double(result.score), in: 0...100) {
                    Text("Score")
                } currentValueLabel: {
                    Text("\(result.score)").font(.system(.title, design: .rounded).weight(.bold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(ScoreBadge.color(result.score))
                .scaleEffect(1.5)
                .frame(width: 90, height: 90)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.score >= 90 ? "You could teach this." : result.score >= 70 ? "Almost there." : "Some gaps to close.")
                        .font(.title2.bold())
                    MarkdownText(result.verdict).fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                if !result.nailed.isEmpty {
                    Card(title: "What you nailed", systemImage: "hand.thumbsup.fill", tint: .green) {
                        BulletList(items: result.nailed, bullet: "✓", color: .green)
                    }
                }
                if !result.gaps.isEmpty {
                    Card(title: "Gaps", systemImage: "puzzlepiece.extension", tint: .orange) {
                        BulletList(items: result.gaps, bullet: "○", color: .orange)
                    }
                }
            }
            if !result.misconceptions.isEmpty {
                Card(title: "Misconceptions", systemImage: "exclamationmark.octagon", tint: .red) {
                    BulletList(items: result.misconceptions, bullet: "✗", color: .red)
                }
            }
            if !result.improvedExplanation.isEmpty {
                Card(title: "A tighter version", systemImage: "wand.and.stars", tint: .indigo,
                     trailing: AnyView(SpeakButton(id: "feynman-\(result.id)", text: result.improvedExplanation))) {
                    MarkdownText(result.improvedExplanation).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !result.followUpQuestion.isEmpty {
                Card(title: "Push further", systemImage: "arrow.up.forward.circle", tint: .purple) {
                    MarkdownText(result.followUpQuestion).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct ScoreBadge: View {
    let score: Int

    static func color(_ score: Int) -> Color {
        score >= 85 ? .green : score >= 65 ? .orange : .red
    }

    var body: some View {
        Text("\(score)")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .monospacedDigit()
            .frame(width: 34, height: 22)
            .background(Capsule().fill(Self.color(score).opacity(0.18)))
            .foregroundStyle(Self.color(score))
    }
}
