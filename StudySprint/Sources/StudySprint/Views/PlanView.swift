import SwiftUI
import StudySprintCore

struct PlanView: View {
    @Binding var guide: StudyGuide
    var onStartSprint: () -> Void
    @State private var playing: VideoResource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    Card(title: "TL;DR", systemImage: "text.quote", tint: .indigo,
                         trailing: AnyView(SpeakButton(id: "tldr-\(guide.id)", text: guide.tldr))) {
                        MarkdownText(guide.tldr).fixedSize(horizontal: false, vertical: true)
                    }
                    Card(title: "The 20% that gets you 80%", systemImage: "target", tint: .pink) {
                        BulletList(items: guide.paretoConcepts, bullet: "★", color: .pink)
                    }
                }

                HStack {
                    Text("Learning path").font(.title2.bold())
                    Spacer()
                    Text("\(guide.remainingMinutes) min left")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.top, 4)

                let general = numberedFigures(forStep: 0)
                if !general.isEmpty {
                    Card(title: "Figures from your notes", systemImage: "photo.on.rectangle.angled", tint: .indigo) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(general, id: \.figure.id) { FigureCard(figure: $0.figure, number: $0.number) }
                        }
                    }
                }

                ForEach(guide.steps.indices, id: \.self) { i in
                    StepCard(step: $guide.steps[i], number: i + 1,
                             isNext: guide.nextStepIndex == i,
                             figures: numberedFigures(forStep: i + 1),
                             onPlay: { playing = $0 })
                }

                if !guide.mnemonics.isEmpty {
                    Card(title: "Memory aids", systemImage: "sparkles", tint: .purple) {
                        BulletList(items: guide.mnemonics, bullet: "✦", color: .purple)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Common mistakes", systemImage: "exclamationmark.triangle", tint: .orange) {
                        BulletList(items: guide.commonMistakes, bullet: "!", color: .orange)
                    }
                    Card(title: "Safe to skip (for now)", systemImage: "forward", tint: .teal) {
                        BulletList(items: guide.skipList, bullet: "→", color: .teal)
                    }
                }

                Card(title: "Final self-test", systemImage: "checkmark.seal", tint: .green) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(guide.selfTest.enumerated()), id: \.offset) { item in
                            CheckRow(text: "\(item.offset + 1). \(item.element)")
                        }
                    }
                }

                if !guide.sources.isEmpty {
                    Card(title: "Sources Claude read (\(guide.sources.count))", systemImage: "books.vertical", tint: .secondary) {
                        DisclosureGroup("Show sources") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(guide.sources) { hit in
                                    if let url = URL(string: hit.url) {
                                        Link(destination: url) {
                                            Label(hit.title, systemImage: hit.isVideo ? "play.rectangle" : "globe")
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $playing) { video in
            VideoSheet(video: video)
        }
    }
}

/// A figure plus its number in the guide ("Figure 3").
struct NumberedFigure {
    let number: Int
    let figure: GuideFigure
}

extension StudyGuide {
    func numberedFigures(forStep step: Int) -> [NumberedFigure] {
        figures.enumerated()
            .filter { $0.element.stepNumber == step }
            .map { NumberedFigure(number: $0.offset + 1, figure: $0.element) }
    }
}

extension PlanView {
    func numberedFigures(forStep step: Int) -> [NumberedFigure] { guide.numberedFigures(forStep: step) }
}

// MARK: - Step

struct StepCard: View {
    @EnvironmentObject private var app: AppModel
    @Binding var step: StudyStep
    let number: Int
    var isNext = false
    var figures: [NumberedFigure] = []
    var onPlay: (VideoResource) -> Void
    @State private var expanded: Bool?

    var body: some View {
        let isExpanded = expanded ?? (isNext || !step.status.isComplete && number == 1)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        step.status = step.status.isComplete ? .notStarted : .done
                        expanded = !step.status.isComplete
                    }
                } label: {
                    Image(systemName: step.status.icon)
                        .font(.title2)
                        .foregroundStyle(step.status.color)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Mark done") { step.status = .done }
                    Button("Mark tested out") { step.status = .testedOut }
                    Button("Reset") { step.status = .notStarted }
                }
                .help("Click to toggle done; right-click for more")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("\(number). \(step.title)")
                            .font(.headline)
                            .strikethrough(step.status.isComplete, color: .secondary)
                        if isNext { Pill(text: "Up next", tint: .indigo) }
                        if step.status == .testedOut { Pill(text: "Tested out", tint: Theme.testedOut) }
                    }
                    Text(step.why).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if !step.videos.isEmpty {
                    Image(systemName: "play.rectangle.fill").foregroundStyle(.red.opacity(0.8))
                        .help("\(step.videos.count) video\(step.videos.count == 1 ? "" : "s")")
                }
                Text("\(step.minutes) min")
                    .font(.callout.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.indigo.opacity(0.13)))
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded = !isExpanded }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        MarkdownText(step.explanation)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        SpeakButton(id: step.id.uuidString, text: step.explanation + "\n" + step.analogy)
                    }

                    if !step.analogy.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                            MarkdownText(step.analogy).italic()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.1)))
                    }

                    if !step.keyPoints.isEmpty {
                        BulletList(items: step.keyPoints)
                    }

                    ForEach(figures, id: \.figure.id) { FigureCard(figure: $0.figure, number: $0.number) }

                    if !step.videos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Watch").font(.subheadline.bold())
                            ForEach(step.videos) { VideoRow(video: $0, onPlay: onPlay) }
                        }
                    }

                    if !step.activeRecall.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Answer from memory before moving on").font(.subheadline.bold())
                            ForEach(Array(step.activeRecall.enumerated()), id: \.offset) { CheckRow(text: $0.element) }
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Stuck?").font(.caption).foregroundStyle(.secondary)
                        ForEach(askOptions, id: \.label) { option in
                            Button(option.label) { ask(option.prompt) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(isNext ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)),
                              lineWidth: isNext ? 2 : 1)
        )
        .opacity(step.status.isComplete && !isExpanded ? 0.72 : 1)
    }
}

extension StepCard {
    struct AskOption { let label: String; let prompt: String }

    var askOptions: [AskOption] {
        let t = "step \(number), “\(step.title)”"
        return [
            AskOption(label: "Explain simpler", prompt: "Explain \(t) more simply, like I'm 12. One analogy, one tiny example."),
            AskOption(label: "Another example", prompt: "Give me a different worked example for \(t), step by step."),
            AskOption(label: "Why does it matter?", prompt: "Why does \(t) matter? Connect it to the big picture and to a real-world case."),
            AskOption(label: "Quiz me", prompt: "Quiz me on \(t): one question at a time, wait for my answer, then tell me if I'm right."),
        ]
    }

    func ask(_ prompt: String) {
        app.pendingTutorPrompt = prompt
        app.tab = .tutor
    }
}

struct VideoRow: View {
    let video: VideoResource
    var onPlay: (VideoResource) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                if video.youTubeID != nil {
                    onPlay(video)
                } else if let url = URL(string: video.url) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(video.verified ? Color.red.opacity(0.9) : Color.secondary.opacity(0.25))
                        .frame(width: 64, height: 40)
                    Image(systemName: video.youTubeID != nil ? "play.fill" : "magnifyingglass")
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .help(video.youTubeID != nil ? "Play inside StudySprint" : "Search YouTube for this video")

            VStack(alignment: .leading, spacing: 3) {
                if let url = URL(string: video.url) {
                    Link(video.title, destination: url).font(.body.weight(.medium))
                } else {
                    Text(video.title)
                }
                HStack(spacing: 6) {
                    Text([video.channel, video.duration].filter { !$0.isEmpty }.joined(separator: " · "))
                    if !video.verified { Text("· opens a YouTube search") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if video.startSeconds > 0 || video.endSeconds > 0 {
                        Pill(text: "\(YouTube.timestamp(video.startSeconds))–\(video.endSeconds > 0 ? YouTube.timestamp(video.endSeconds) : "end")",
                             systemImage: "scissors", tint: .orange)
                    }
                    if video.playbackSpeed != 1 {
                        Pill(text: String(format: "%.2gx", video.playbackSpeed), systemImage: "hare", tint: .orange)
                    }
                    if !video.watchTip.isEmpty {
                        Text(video.watchTip).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A question you tick off once you've answered it from memory.
struct CheckRow: View {
    let text: String
    @State private var checked = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { checked.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? Color.green : Color.secondary)
                Text(MarkdownText.attributed(text))
                    .foregroundStyle(checked ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}

struct VideoSheet: View {
    let video: VideoResource
    @Environment(\.dismiss) private var dismiss
    @State private var speed: Double

    init(video: VideoResource) {
        self.video = video
        _speed = State(initialValue: video.playbackSpeed)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title).font(.headline).lineLimit(1)
                    Text(video.watchTip.isEmpty ? video.channel : video.watchTip)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                SpeedPicker(speed: $speed)
                Button("Open in browser") {
                    if let url = URL(string: video.url) { NSWorkspace.shared.open(url) }
                }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            YouTubePlayerView(video: video, speed: speed)
        }
        .frame(width: 960, height: 620)
    }
}

struct SpeedPicker: View {
    @Binding var speed: Double
    let options: [Double] = [1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        Picker("Speed", selection: $speed) {
            ForEach(options, id: \.self) { Text(String(format: "%.2gx", $0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 240)
        .help("Playback speed")
    }
}
