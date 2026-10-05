import SwiftUI
import StudySprintCore

/// Focus mode: one step at a time. Learn → (optionally test out) → recall check → next.
struct SprintModeView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var guide: StudyGuide

    enum Phase: Equatable { case learn, testOut, recall, complete }

    @State private var index = 0
    @State private var phase: Phase = .learn
    @State private var sessionStart = Date()
    @State private var stepStart = Date()
    @State private var videoIndex = 0
    @State private var speed = 1.0
    @State private var recallChecked: Set<Int> = []
    @State private var peeked = false

    private var hideLesson: Bool { (phase == .recall || phase == .testOut) && !peeked }
    @State private var stepsThisSession = 0
    @State private var testedOutThisSession = 0

    // Test out
    @State private var testAnswer = ""
    @State private var grading = false
    @State private var verdict: TestOutVerdict?
    @State private var testError: String?

    private var step: StudyStep? { guide.steps.indices.contains(index) ? guide.steps[index] : nil }
    private var playableVideos: [VideoResource] { step?.videos.filter { $0.youTubeID != nil } ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            Group {
                if phase == .complete || step == nil {
                    completeView
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        lesson
                            .frame(minWidth: 380, idealWidth: 460, maxWidth: 520)
                            .blur(radius: hideLesson ? 9 : 0)
                            .overlay {
                                if hideLesson {
                                    VStack(spacing: 10) {
                                        Image(systemName: "eye.slash.fill").font(.largeTitle).foregroundStyle(Theme.gradient)
                                        Text("Lesson hidden").font(.title3.bold())
                                        Text("Recall works only if you can't see the answer.")
                                            .foregroundStyle(.secondary)
                                        Button("Peek at the lesson") {
                                            peeked = true
                                        }
                                        .buttonStyle(.link)
                                    }
                                    .padding(24)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
                                }
                            }
                            .animation(.easeInOut(duration: 0.25), value: hideLesson)
                        Divider()
                        rightPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if phase != .complete && step != nil {
                Divider()
                bottomBar
            }
        }
        .frame(minWidth: 1100, idealWidth: 1240, minHeight: 720, idealHeight: 820)
        .onAppear {
            index = guide.nextStepIndex ?? 0
            if guide.nextStepIndex == nil { phase = .complete }
            sessionStart = Date()
            resetStep()
            switch AppModel.screenshotScreen {
            case "recall":
                phase = .recall
                recallChecked = [0]
            case "testout":
                phase = .testOut
                testAnswer = "Pyruvate goes into the mitochondria and gets broken down; it mostly makes NADH and FADH2 that carry electrons to the ETC, and releases CO2. Only a little ATP."
                verdict = .init(passed: true, feedback: "Spot on — you named the location, the real products (loaded electron carriers), and the CO₂. Skipping saves you 12 minutes.")
            default: break
            }
        }
        .onDisappear {
            app.recordStudy(guideID: guide.id, minutes: Date().timeIntervalSince(sessionStart) / 60)
            Speaker.shared.stop()
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            Text(guide.emoji).font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sprint · \(guide.topic)").font(.headline).lineLimit(1)
                TimelineView(.periodic(from: sessionStart, by: 1)) { ctx in
                    Text("\(elapsedString(since: sessionStart, now: ctx.date)) elapsed · \(guide.remainingMinutes) min of plan left")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(guide.steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(dotColor(i))
                        .frame(width: i == index && phase != .complete ? 26 : 12, height: 8)
                        .onTapGesture { jump(to: i) }
                        .help("\(i + 1). \(guide.steps[i].title)")
                }
            }
            .animation(.spring(response: 0.3), value: index)
            Spacer()
            Button("End sprint") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func dotColor(_ i: Int) -> Color {
        let s = guide.steps[i].status
        if i == index && phase != .complete { return .indigo }
        return s.isComplete ? s.color : Color.primary.opacity(0.15)
    }

    // MARK: Lesson (left)

    private var lesson: some View {
        ScrollView {
            if let step {
                VStack(alignment: .leading, spacing: 16) {
                    Text("STEP \(index + 1) OF \(guide.steps.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        Text(step.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        SpeakButton(id: "sprint-\(step.id)", text: step.explanation + "\n" + step.analogy)
                            .font(.title3)
                    }
                    Text(step.why).foregroundStyle(.secondary)

                    MarkdownText(step.explanation)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lock these in").font(.subheadline.bold())
                            BulletList(items: step.keyPoints, bullet: "●", color: .indigo)
                        }
                    }

                    ForEach(guide.numberedFigures(forStep: index + 1), id: \.figure.id) {
                        FigureCard(figure: $0.figure, number: $0.number, compact: true)
                    }
                }
                .padding(24)
            }
        }
    }

    // MARK: Right pane

    @ViewBuilder
    private var rightPane: some View {
        switch phase {
        case .testOut: testOutPane
        case .recall: recallPane
        default: videoPane
        }
    }

    @ViewBuilder
    private var videoPane: some View {
        if playableVideos.isEmpty, let videos = step?.videos, !videos.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Label("Suggested videos", systemImage: "play.rectangle.fill")
                    .font(.title3.bold())
                Text("These open a YouTube search in your browser. Watch only the part noted, then come back and hit **Done**.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(videos) { VideoRow(video: $0, onPlay: { _ in }) }
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if playableVideos.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "book.pages")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.gradient)
                Text("No video needed here").font(.title3.bold())
                Text("Reading is faster for this step. Read it once, then hit **Done** and test yourself.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let video = playableVideos[min(videoIndex, playableVideos.count - 1)]
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if playableVideos.count > 1 {
                        Picker("", selection: $videoIndex) {
                            ForEach(playableVideos.indices, id: \.self) { i in
                                Text("Video \(i + 1)").tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(video.channel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SpeedPicker(speed: $speed)
                }
                if !video.watchTip.isEmpty || video.startSeconds > 0 {
                    Label {
                        Text(watchLine(video))
                    } icon: {
                        Image(systemName: "scissors")
                    }
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
                YouTubePlayerView(video: video, speed: speed)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .id(video.id)
            }
            .padding(20)
            .onChange(of: videoIndex) { _ in speed = currentVideoSpeed }
        }
    }

    private func watchLine(_ v: VideoResource) -> String {
        var parts: [String] = []
        if v.startSeconds > 0 || v.endSeconds > 0 {
            parts.append("Plays \(YouTube.timestamp(v.startSeconds))–\(v.endSeconds > 0 ? YouTube.timestamp(v.endSeconds) : "end")")
        }
        if !v.watchTip.isEmpty { parts.append(v.watchTip) }
        return parts.joined(separator: " · ")
    }

    private var currentVideoSpeed: Double {
        playableVideos.indices.contains(videoIndex) ? playableVideos[videoIndex].playbackSpeed : 1
    }

    private var testOutPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Prove you already know it", systemImage: "bolt.shield.fill")
                .font(.title2.bold())
                .foregroundStyle(Theme.gradient)
            Text("Answer in your own words. If Claude agrees you've got it, you skip this step and save \(step?.minutes ?? 0) minutes.")
                .foregroundStyle(.secondary)
            Card {
                MarkdownText(step?.testOut?.question ?? "")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: $testAnswer)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 140)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
                .disabled(grading || verdict?.passed == true)

            if let testError { ErrorBanner(message: testError) }

            if let verdict {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: verdict.passed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .font(.title2)
                        .foregroundStyle(verdict.passed ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verdict.passed ? "You know this. Skipping ahead." : "Not quite — worth studying.")
                            .font(.headline)
                        Text(verdict.feedback).fixedSize(horizontal: false, vertical: true)
                        if !verdict.passed, let answer = step?.testOut?.answer {
                            Text("Key points: \(answer)").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill((verdict.passed ? Color.green : Color.orange).opacity(0.1)))
            }

            HStack {
                Button("Back to the lesson") { phase = .learn; verdict = nil }
                Spacer()
                if verdict?.passed == true {
                    Button {
                        testedOutThisSession += 1
                        complete(as: .testedOut)
                    } label: {
                        Label("Skip ahead", systemImage: "forward.fill")
                    }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        gradeTestOut()
                    } label: {
                        if grading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Check my answer", systemImage: "checkmark")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(grading || testAnswer.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            Spacer()
        }
        .padding(28)
    }

    private var recallPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Recall check", systemImage: "brain.head.profile")
                .font(.title2.bold())
                .foregroundStyle(Theme.gradient)
            Text("Answer each question out loud or in your head, then tick it. Pulling it from memory is what makes it stick.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            let questions = step?.activeRecall ?? []
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                    Button {
                        if recallChecked.contains(i) { recallChecked.remove(i) } else { recallChecked.insert(i) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: recallChecked.contains(i) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(recallChecked.contains(i) ? Color.green : Color.secondary)
                                .font(.title3)
                            Text(MarkdownText.attributed(q))
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Review the lesson again") { phase = .learn }
                Spacer()
                Button {
                    complete(as: .done)
                } label: {
                    Label(index + 1 < guide.steps.count ? "Next step" : "Finish sprint", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent).tint(.indigo)
                .keyboardShortcut(.defaultAction)
                .disabled(recallChecked.count < questions.count && !questions.isEmpty)
            }
            if recallChecked.count < questions.count {
                Text("Can't answer one? Go back to the lesson — it's faster than forgetting it later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(28)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            if let step {
                StepTimer(start: stepStart, minutes: step.minutes)
            }
            Spacer()
            if phase == .learn {
                if step?.testOut != nil {
                    Button {
                        phase = .testOut
                    } label: {
                        Label("I already know this", systemImage: "bolt.shield")
                    }
                    .help("Answer one question to skip this step")
                }
                Button {
                    recallChecked = []
                    if step?.activeRecall.isEmpty ?? true {
                        complete(as: .done)
                    } else {
                        phase = .recall
                    }
                } label: {
                    Label("Done — test me", systemImage: "checkmark")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Completion

    private var completeView: some View {
        let used = Int(Date().timeIntervalSince(sessionStart) / 60)
        return VStack(spacing: 18) {
            Text("🎉").font(.system(size: 80))
            GradientTitle(text: guide.progress >= 1 ? "Sprint complete!" : "Nice work", size: 36)
            Text(guide.progress >= 1
                 ? "You've covered every step of \(guide.topic)."
                 : "You finished \(stepsThisSession) step\(stepsThisSession == 1 ? "" : "s") this session.")
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                SummaryTile(value: "\(guide.completedSteps)/\(guide.steps.count)", label: "steps done")
                SummaryTile(value: "\(testedOutThisSession)", label: "tested out")
                SummaryTile(value: "\(max(used, 1)) min", label: "this session")
                SummaryTile(value: "\(guide.flashcards.count)", label: "flashcards ready")
            }
            Text("Lock it in now: a quiz finds your weak spots, and flashcards keep it from fading.")
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            HStack(spacing: 12) {
                Button {
                    app.tab = .quiz
                    dismiss()
                } label: {
                    Label("Take the quiz", systemImage: "checkmark.circle").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent).tint(.indigo).controlSize(.large)
                Button {
                    app.tab = .cards
                    dismiss()
                } label: {
                    Label("Review flashcards", systemImage: "rectangle.on.rectangle.angled")
                }
                .controlSize(.large)
                if guide.progress >= 1 {
                    Button("Restart from step 1") {
                        for i in guide.steps.indices { guide.steps[i].status = .notStarted }
                        index = 0
                        phase = .learn
                        resetStep()
                    }
                    .controlSize(.large)
                }
                Button("Close") { dismiss() }.controlSize(.large)
            }
        }
        .padding(40)
    }

    // MARK: Actions

    private func resetStep() {
        stepStart = Date()
        peeked = false
        videoIndex = 0
        speed = currentVideoSpeed
        recallChecked = []
        testAnswer = ""
        verdict = nil
        testError = nil
        Speaker.shared.stop()
    }

    private func jump(to i: Int) {
        index = i
        phase = .learn
        resetStep()
    }

    private func complete(as status: StepStatus) {
        guard guide.steps.indices.contains(index) else { return }
        guide.steps[index].status = status
        stepsThisSession += 1
        if let next = guide.steps.indices.first(where: { $0 > index && !guide.steps[$0].status.isComplete })
            ?? guide.nextStepIndex {
            withAnimation(.easeInOut(duration: 0.25)) {
                index = next
                phase = .learn
            }
            resetStep()
        } else {
            NSSound(named: "Hero")?.play()
            withAnimation { phase = .complete }
        }
    }

    private func gradeTestOut() {
        guard let step, let testOut = step.testOut else { return }
        grading = true
        testError = nil
        let services = app.services
        let answer = testAnswer
        Task { @MainActor in
            do {
                verdict = try await services.gradeTestOut(stepTitle: step.title, testOut: testOut, answer: answer)
            } catch {
                testError = error.localizedDescription
            }
            grading = false
        }
    }
}

private struct StepTimer: View {
    let start: Date
    let minutes: Int

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(start)
            let total = Double(minutes * 60)
            let over = elapsed > total
            HStack(spacing: 10) {
                ProgressRing(progress: min(1, elapsed / max(total, 1)), lineWidth: 4, size: 30, showLabel: false)
                VStack(alignment: .leading, spacing: 0) {
                    Text(over ? "+\(elapsedString(since: start.addingTimeInterval(total), now: ctx.date))"
                              : elapsedString(since: ctx.date, now: start.addingTimeInterval(total)))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(over ? Color.orange : Color.primary)
                    Text(over ? "over the step budget" : "left for this step")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SummaryTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 130, height: 76)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
