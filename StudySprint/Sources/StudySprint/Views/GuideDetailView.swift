import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GuideDetailView: View {
    @Binding var guide: StudyGuide
    @State private var showFlashcards = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Card(title: "TL;DR", systemImage: "text.quote") {
                    Text(guide.tldr).textSelection(.enabled)
                }

                Card(title: "The 20% that gets you 80%", systemImage: "target") {
                    BulletList(items: guide.paretoConcepts)
                }

                Text("Learning path")
                    .font(.title2.bold())
                    .padding(.top, 6)

                ForEach(guide.steps.indices, id: \.self) { i in
                    StepCard(step: $guide.steps[i], number: i + 1)
                }

                HStack(alignment: .top, spacing: 18) {
                    Card(title: "Common mistakes", systemImage: "exclamationmark.triangle") {
                        BulletList(items: guide.commonMistakes)
                    }
                    Card(title: "Safe to skip (for now)", systemImage: "forward") {
                        BulletList(items: guide.skipList)
                    }
                }

                Card(title: "Final self-test", systemImage: "checkmark.seal") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(guide.selfTest.enumerated()), id: \.offset) { item in
                            RevealRow(prompt: "\(item.offset + 1). \(item.element)")
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showFlashcards) {
            FlashcardsView(cards: guide.flashcards)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showFlashcards = true
                } label: {
                    Label("Flashcards", systemImage: "rectangle.on.rectangle.angled")
                }
                .disabled(guide.flashcards.isEmpty)
                .help("Drill \(guide.flashcards.count) flashcards")

                Button(action: exportMarkdown) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Save this guide as Markdown")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guide.topic)
                .font(.largeTitle.bold())
                .textSelection(.enabled)
            HStack(spacing: 14) {
                Label("\(guide.totalMinutes) min plan", systemImage: "clock")
                Label("\(guide.steps.count) steps", systemImage: "list.number")
                Label("\(guide.flashcards.count) flashcards", systemImage: "rectangle.stack")
                Spacer()
                SprintTimer(minutes: max(guide.totalMinutes, 1))
            }
            .foregroundStyle(.secondary)
            ProgressView(value: guide.progress) {
                Text("\(guide.steps.filter(\.done).count) of \(guide.steps.count) steps done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(guide.topic) study guide.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? MarkdownExporter.markdown(for: guide).write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Step

private struct StepCard: View {
    @Binding var step: StudyStep
    let number: Int
    @State private var expanded: Bool? = nil

    var body: some View {
        let isExpanded = Binding(get: { expanded ?? !step.done }, set: { expanded = $0 })

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    step.done.toggle()
                    expanded = !step.done
                } label: {
                    Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(step.done ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(step.done ? "Mark as not done" : "Mark as done")

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(number). \(step.title)")
                        .font(.headline)
                        .strikethrough(step.done)
                    Text(step.why)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(step.minutes) min")
                    .font(.callout.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                Button {
                    isExpanded.wrappedValue.toggle()
                } label: {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }

            if isExpanded.wrappedValue {
                Text(step.explanation)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !step.keyPoints.isEmpty {
                    BulletList(items: step.keyPoints)
                }

                if !step.videos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Watch").font(.subheadline.bold())
                        ForEach(step.videos) { VideoRow(video: $0) }
                    }
                }

                if !step.activeRecall.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Answer from memory before moving on")
                            .font(.subheadline.bold())
                        ForEach(step.activeRecall, id: \.self) { RevealRow(prompt: $0) }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
        .opacity(step.done && !isExpanded.wrappedValue ? 0.7 : 1)
    }
}

private struct VideoRow: View {
    let video: VideoResource

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: video.verified ? "play.rectangle.fill" : "magnifyingglass")
                .font(.title3)
                .foregroundStyle(video.verified ? Color.red : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if let url = URL(string: video.url) {
                    Link(video.title, destination: url)
                        .font(.body.weight(.medium))
                } else {
                    Text(video.title)
                }
                Text([video.channel, video.duration].filter { !$0.isEmpty }.joined(separator: " · ")
                     + (video.verified ? "" : " · opens a YouTube search"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !video.watchTip.isEmpty {
                    Label(video.watchTip, systemImage: "hare")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Small building blocks

private struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A recall question you tick off once you've answered it from memory.
private struct RevealRow: View {
    let prompt: String
    @State private var answered = false

    var body: some View {
        Button {
            answered.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: answered ? "checkmark.square.fill" : "square")
                    .foregroundStyle(answered ? Color.green : Color.secondary)
                Text(prompt)
                    .foregroundStyle(answered ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Countdown for the whole sprint — a visible clock keeps sessions short and focused.
private struct SprintTimer: View {
    let minutes: Int
    @State private var remaining: TimeInterval = 0
    @State private var endDate: Date?

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(format(left(at: context.date)))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(endDate == nil ? .secondary : .primary)
            }
            Button {
                if let endDate {
                    remaining = max(endDate.timeIntervalSinceNow, 0)
                    self.endDate = nil
                } else {
                    endDate = Date().addingTimeInterval(remaining)
                }
            } label: {
                Image(systemName: endDate == nil ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderless)
            .help(endDate == nil ? "Start sprint timer" : "Pause")
            Button {
                endDate = nil
                remaining = TimeInterval(minutes * 60)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset")
        }
        .onAppear { remaining = TimeInterval(minutes * 60) }
    }

    private func left(at date: Date) -> TimeInterval {
        guard let endDate else { return remaining }
        return max(endDate.timeIntervalSince(date), 0)
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
