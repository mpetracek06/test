import SwiftUI
import StudySprintCore

struct QuizView: View {
    @EnvironmentObject private var app: AppModel
    @Binding var guide: StudyGuide

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var answers: [UUID: Int] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var finished = false
    @State private var focusWeak = true
    @State private var questionCount = 8

    private var lastMissed: [Int] { guide.quizAttempts.last?.missedSteps ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { ErrorBanner(message: error) { self.error = nil } }
                if loading {
                    loadingView
                } else if questions.isEmpty {
                    startView
                } else if finished {
                    resultsView
                } else {
                    questionView
                }
            }
            .padding(28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if AppModel.screenshotScreen == "quizq" && questions.isEmpty {
                questions = DemoContent.quiz()
                answers[questions[0].id] = 0
            }
        }
    }

    // MARK: Start

    private var startView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.badge.questionmark")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.gradient)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Test yourself").font(.title.bold())
                    Text("Fresh questions every time, written by Claude from your guide. Testing yourself beats re-reading — it's the fastest way to make it stick and to find what you don't know yet.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Card {
                HStack {
                    Stepper("\(questionCount) questions", value: $questionCount, in: 4...20, step: 2)
                    Spacer()
                    if !lastMissed.isEmpty {
                        Toggle("Focus on my weak spots (steps \(lastMissed.map(String.init).joined(separator: ", ")))", isOn: $focusWeak)
                    }
                }
            }
            Button {
                start()
            } label: {
                Label("Start quiz", systemImage: "play.fill").padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent).tint(.indigo).controlSize(.large)
            .keyboardShortcut(.defaultAction)

            if !guide.quizAttempts.isEmpty {
                Card(title: "History", systemImage: "chart.bar.fill", tint: .indigo) {
                    ScoreHistory(attempts: guide.quizAttempts)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Writing \(questionCount) questions…").font(.headline)
            Text("Targeting the ideas that matter most.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: Question

    private var questionView: some View {
        let q = questions[index]
        let chosen = answers[q.id]
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Question \(index + 1) of \(questions.count)").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if guide.steps.indices.contains(q.stepNumber - 1) {
                    Pill(text: "Step \(q.stepNumber): \(guide.steps[q.stepNumber - 1].title)", tint: .indigo)
                }
            }
            ProgressView(value: Double(index), total: Double(questions.count))
            Text(MarkdownText.attributed(q.question))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)

            VStack(spacing: 10) {
                ForEach(q.choices.indices, id: \.self) { i in
                    ChoiceButton(letter: ["A", "B", "C", "D", "E", "F"][min(i, 5)], text: q.choices[i],
                                 state: choiceState(i, q: q, chosen: chosen)) {
                        guard chosen == nil else { return }
                        withAnimation(.easeOut(duration: 0.15)) { answers[q.id] = i }
                        NSSound(named: i == q.correctIndex ? "Pop" : "Basso")?.play()
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                }
            }

            if let chosen {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: chosen == q.correctIndex ? "checkmark.circle.fill" : "lightbulb.fill")
                        .foregroundStyle(chosen == q.correctIndex ? Color.green : Color.orange)
                        .font(.title3)
                    MarkdownText(q.explanation).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill((chosen == q.correctIndex ? Color.green : Color.orange).opacity(0.1)))

                HStack {
                    Spacer()
                    Button {
                        if index + 1 < questions.count {
                            withAnimation { index += 1 }
                        } else {
                            finish()
                        }
                    } label: {
                        Label(index + 1 < questions.count ? "Next" : "See results", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent).tint(.indigo)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Press 1–\(q.choices.count) to answer").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func choiceState(_ i: Int, q: QuizQuestion, chosen: Int?) -> ChoiceButton.Appearance {
        guard let chosen else { return .idle }
        if i == q.correctIndex { return .correct }
        if i == chosen { return .wrong }
        return .dimmed
    }

    // MARK: Results

    private var score: Int { questions.filter { answers[$0.id] == $0.correctIndex }.count }

    private var missedSteps: [Int] {
        Array(Set(questions.filter { answers[$0.id] != $0.correctIndex }.map(\.stepNumber)))
            .filter { $0 > 0 }.sorted()
    }

    private var resultsView: some View {
        let pct = questions.isEmpty ? 0 : Double(score) / Double(questions.count)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 20) {
                ProgressRing(progress: pct, lineWidth: 10, size: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text(pct >= 0.9 ? "Outstanding." : pct >= 0.7 ? "Solid — a few gaps to patch." : "Good diagnosis. Now let's fix the gaps.")
                        .font(.title2.bold())
                    Text("\(score) of \(questions.count) correct").foregroundStyle(.secondary)
                }
            }

            if !missedSteps.isEmpty {
                Card(title: "Your weak spots", systemImage: "scope", tint: .orange) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(missedSteps, id: \.self) { n in
                            if guide.steps.indices.contains(n - 1) {
                                Text("Step \(n): \(guide.steps[n - 1].title)")
                            }
                        }
                    }
                    HStack {
                        Button {
                            fixGapsWithTutor()
                        } label: {
                            Label("Fix my gaps with the tutor", systemImage: "graduationcap.fill")
                        }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        Button("New quiz on weak spots") { focusWeak = true; start() }
                    }
                    .padding(.top, 6)
                }
            }

            Card(title: "Review", systemImage: "list.bullet.clipboard") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(questions) { q in
                        let right = answers[q.id] == q.correctIndex
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(right ? Color.green : Color.red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(MarkdownText.attributed(q.question)).fixedSize(horizontal: false, vertical: true)
                                if !right {
                                    Text("Answer: \(q.choices[q.correctIndex])").font(.callout).foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Back to start") { questions = [] }
                Spacer()
                Button("Another quiz") { start() }
                    .buttonStyle(.borderedProminent).tint(.indigo)
            }
        }
    }

    // MARK: Actions

    private func start() {
        loading = true
        error = nil
        finished = false
        index = 0
        answers = [:]
        let services = app.services
        let snapshot = guide
        let focus = focusWeak ? lastMissed : []
        let count = questionCount
        Task { @MainActor in
            do {
                questions = try await services.makeQuiz(for: snapshot, count: count, focusSteps: focus)
            } catch {
                self.error = error.localizedDescription
                questions = []
            }
            loading = false
        }
    }

    private func finish() {
        finished = true
        guide.quizAttempts.append(QuizAttempt(score: score, total: questions.count, missedSteps: missedSteps))
        NSSound(named: score == questions.count ? "Hero" : "Glass")?.play()
    }

    private func fixGapsWithTutor() {
        let missed = questions.filter { answers[$0.id] != $0.correctIndex }
        let list = missed.map { q -> String in
            let mine = answers[q.id].map { q.choices[$0] } ?? "(no answer)"
            return "- \(q.question)\n  I answered: \(mine)\n  Correct: \(q.choices[q.correctIndex])"
        }.joined(separator: "\n")
        app.pendingTutorPrompt = """
        I just took a quiz and missed these:
        \(list)

        Diagnose the misunderstanding behind my wrong answers, then fix it in the fastest way possible: \
        a short explanation, one concrete example, and one check question for me to answer.
        """
        app.tab = .tutor
    }
}

struct ChoiceButton: View {
    enum Appearance { case idle, correct, wrong, dimmed }
    let letter: String
    let text: String
    let state: Appearance
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(letter)
                    .font(.system(.headline, design: .rounded))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(badgeColor.opacity(0.18)))
                    .foregroundStyle(badgeColor)
                Text(MarkdownText.attributed(text))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if state == .correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                if state == .wrong { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 12).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: state == .idle ? 1 : 2))
            .opacity(state == .dimmed ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }

    private var badgeColor: Color {
        switch state {
        case .correct: return .green
        case .wrong: return .red
        default: return .indigo
        }
    }
    private var fill: Color {
        switch state {
        case .correct: return Color.green.opacity(0.1)
        case .wrong: return Color.red.opacity(0.1)
        default: return Color(nsColor: .controlBackgroundColor)
        }
    }
    private var stroke: Color {
        switch state {
        case .correct: return .green
        case .wrong: return .red
        default: return Color.primary.opacity(0.1)
        }
    }
}

struct ScoreHistory: View {
    let attempts: [QuizAttempt]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(attempts.suffix(20)) { a in
                let pct = a.total == 0 ? 0 : Double(a.score) / Double(a.total)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.gradient)
                        .frame(width: 22, height: max(4, 70 * pct))
                    Text("\(Int(pct * 100))").font(.caption2).foregroundStyle(.secondary)
                }
                .help("\(a.score)/\(a.total) on \(a.date.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .frame(height: 90, alignment: .bottom)
    }
}
