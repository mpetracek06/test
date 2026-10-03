import SwiftUI
import StudySprintCore

/// Global review: every due card across all guides, scheduled with spaced repetition.
struct ReviewView: View {
    @EnvironmentObject private var app: AppModel
    @State private var sessionID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                GradientTitle(text: "Review", size: 30)
                Spacer()
                StatBadge(value: "\(app.log.streak())", label: "day streak", icon: "flame.fill", tint: .orange)
                StatBadge(value: "\(app.log.reviews())", label: "reviewed today", icon: "checkmark.seal.fill", tint: .green)
                StatBadge(value: "\(app.dueCount)", label: "due now", icon: "tray.full.fill", tint: .indigo)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            Divider()
            ReviewSession(guideID: nil)
                .id(sessionID)
        }
    }
}

/// The cards tab inside a guide.
struct CardsView: View {
    @EnvironmentObject private var app: AppModel
    @Binding var guide: StudyGuide
    @State private var mode: Mode = .overview

    enum Mode { case overview, review, cram }

    var body: some View {
        switch mode {
        case .review:
            VStack(spacing: 0) {
                backBar
                ReviewSession(guideID: guide.id)
            }
        case .cram:
            VStack(spacing: 0) {
                backBar
                CramDrill(cards: guide.flashcards)
            }
        case .overview:
            overview
        }
    }

    private var backBar: some View {
        HStack {
            Button {
                mode = .overview
            } label: {
                Label("All cards", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var overview: some View {
        let due = guide.dueCards().count
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        mode = .review
                    } label: {
                        Label(due > 0 ? "Review \(due) due" : "Nothing due", systemImage: "brain.head.profile")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(.indigo).controlSize(.large)
                    .disabled(due == 0)

                    Button {
                        mode = .cram
                    } label: {
                        Label("Cram all \(guide.flashcards.count)", systemImage: "bolt.fill")
                    }
                    .controlSize(.large)
                    .help("Drill every card now, ignoring the schedule — good the night before an exam")
                    Spacer()
                    Text("Spaced repetition shows each card right before you'd forget it.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(guide.flashcards) { card in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(MarkdownText.attributed(card.front)).font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(MarkdownText.attributed(card.back)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            HStack {
                                Pill(text: dueLabel(card.review), systemImage: "clock",
                                     tint: card.review.due <= Date() ? .orange : .secondary)
                                if card.review.lapses > 0 {
                                    Pill(text: "\(card.review.lapses) lapse\(card.review.lapses == 1 ? "" : "s")", tint: .red)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
            }
            .padding(24)
        }
    }

    private func dueLabel(_ r: ReviewState) -> String {
        if r.isNew { return "New" }
        let interval = r.due.timeIntervalSinceNow
        return interval <= 0 ? "Due now" : "Due in \(Scheduler.formatInterval(interval))"
    }
}

/// Shows due cards one at a time with Again / Hard / Good / Easy.
struct ReviewSession: View {
    @EnvironmentObject private var app: AppModel
    let guideID: UUID?

    @State private var queue: [AppModel.DueCard] = []
    @State private var revealed = false
    @State private var reviewedCount = 0
    @State private var started = false
    private let sessionCap = 100

    var body: some View {
        Group {
            if let current = queue.first, let card = app.card(current.guideID, current.card.id) {
                cardView(current: current, card: card)
            } else if started && reviewedCount > 0 {
                done
            } else {
                EmptyStateView(
                    systemImage: "checkmark.seal.fill",
                    title: "All caught up",
                    message: app.nextDueDate.map { "Next card due \($0.formatted(.relative(presentation: .named)))." }
                        ?? "Build a sprint to get flashcards — they'll show up here right before you'd forget them."
                )
            }
        }
        .onAppear {
            guard !started else { return }
            queue = Array(app.dueCards(in: guideID).prefix(sessionCap))
            started = true
        }
    }

    private func cardView(current: AppModel.DueCard, card: Flashcard) -> some View {
        VStack(spacing: 22) {
            HStack {
                if guideID == nil, let g = app.guide(current.guideID) {
                    Pill(text: "\(g.emoji) \(g.topic)", tint: .indigo)
                }
                if card.review.isNew { Pill(text: "New", systemImage: "sparkle", tint: .purple) }
                Spacer()
                Text("\(queue.count) left").foregroundStyle(.secondary).monospacedDigit()
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { revealed.toggle() }
            } label: {
                VStack(spacing: 18) {
                    Text(MarkdownText.attributed(card.front))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if revealed {
                        Divider().frame(maxWidth: 200)
                        Text(MarkdownText.attributed(card.back))
                            .font(.system(size: 18))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        Text("Think of the answer, then press Space").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(36)
                .frame(maxWidth: 640, minHeight: 280)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                )
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(revealed ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)), lineWidth: revealed ? 2 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            HStack(spacing: 12) {
                ForEach(ReviewGrade.allCases) { grade in
                    Button {
                        rate(grade, current: current, card: card)
                    } label: {
                        VStack(spacing: 2) {
                            Text(grade.label).font(.headline)
                            Text(Scheduler.preview(card.review, grade: grade)).font(.caption).opacity(0.8)
                        }
                        .frame(width: 92, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(color(for: grade))
                    .keyboardShortcut(KeyEquivalent(Character("\(grade.rawValue + 1)")), modifiers: [])
                }
            }
            .disabled(!revealed)
            .opacity(revealed ? 1 : 0.4)

            Text("Space flips · 1 Again · 2 Hard · 3 Good · 4 Easy")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var done: some View {
        VStack(spacing: 14) {
            Text("🧠").font(.system(size: 64))
            GradientTitle(text: "Session complete", size: 30)
            Text("\(reviewedCount) review\(reviewedCount == 1 ? "" : "s") done. 🔥 \(app.log.streak())-day streak.")
                .foregroundStyle(.secondary)
            if let next = app.nextDueDate {
                Text("Next card due \(next.formatted(.relative(presentation: .named))).").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func color(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }

    private func rate(_ grade: ReviewGrade, current: AppModel.DueCard, card: Flashcard) {
        app.grade(guideID: current.guideID, cardID: card.id, grade: grade)
        reviewedCount += 1
        withAnimation(.easeInOut(duration: 0.2)) {
            revealed = false
            let item = queue.removeFirst()
            // Missed cards come back at the end of this session too.
            if grade == .again { queue.append(item) }
        }
        if queue.isEmpty { NSSound(named: "Hero")?.play() }
    }
}

/// Unscheduled drill through every card ("cram mode").
struct CramDrill: View {
    let cards: [Flashcard]
    @State private var queue: [Flashcard] = []
    @State private var revealed = false
    @State private var misses = 0

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(cards.count - queue.count), total: Double(max(cards.count, 1)))
                .frame(maxWidth: 640)
            if let card = queue.first {
                Button {
                    withAnimation(.spring(response: 0.3)) { revealed.toggle() }
                } label: {
                    VStack(spacing: 16) {
                        Text(MarkdownText.attributed(card.front))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                        if revealed {
                            Text(MarkdownText.attributed(card.back)).font(.title3).multilineTextAlignment(.center)
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: 640, minHeight: 240)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color(nsColor: .controlBackgroundColor)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                HStack(spacing: 14) {
                    Button {
                        misses += 1
                        advance(knewIt: false)
                    } label: {
                        Label("Again", systemImage: "arrow.uturn.backward").frame(minWidth: 110)
                    }
                    .keyboardShortcut("1", modifiers: [])
                    Button {
                        advance(knewIt: true)
                    } label: {
                        Label("Got it", systemImage: "checkmark").frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .keyboardShortcut("2", modifiers: [])
                }
                .controlSize(.large)
                .disabled(!revealed)
                Text("Space flips · 1 again · 2 got it").font(.caption).foregroundStyle(.tertiary)
            } else {
                Text("✅").font(.system(size: 60))
                Text("All \(cards.count) cards mastered").font(.title2.bold())
                Text(misses == 0 ? "Perfect run." : "\(misses) repeat\(misses == 1 ? "" : "s") along the way.")
                    .foregroundStyle(.secondary)
                Button("Shuffle and go again", action: restart)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: restart)
    }

    private func advance(knewIt: Bool) {
        guard !queue.isEmpty else { return }
        let card = queue.removeFirst()
        if !knewIt { queue.append(card) }
        revealed = false
    }

    private func restart() {
        queue = cards.shuffled()
        revealed = false
        misses = 0
    }
}

private struct StatBadge: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.1)))
    }
}
