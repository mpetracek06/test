import SwiftUI

/// Quick active-recall drill: cards you miss go to the back of the queue until you get them all.
struct FlashcardsView: View {
    let cards: [Flashcard]
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Flashcard] = []
    @State private var showingBack = false
    @State private var misses = 0

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Flashcards").font(.title2.bold())
                Spacer()
                Text("\(cards.count - queue.count) / \(cards.count) mastered")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ProgressView(value: Double(cards.count - queue.count), total: Double(max(cards.count, 1)))

            if let card = queue.first {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showingBack.toggle() }
                } label: {
                    VStack(spacing: 12) {
                        Text(showingBack ? "ANSWER" : "QUESTION")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(showingBack ? card.back : card.front)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(showingBack ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.2)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                HStack(spacing: 14) {
                    Button {
                        misses += 1
                        next(remember: false)
                    } label: {
                        Label("Again", systemImage: "arrow.uturn.backward").frame(minWidth: 110)
                    }
                    .keyboardShortcut("1", modifiers: [])

                    Button {
                        next(remember: true)
                    } label: {
                        Label("Got it", systemImage: "checkmark").frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("2", modifiers: [])
                }
                .controlSize(.large)
                .disabled(!showingBack)

                Text("Space flips · 1 = again · 2 = got it")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("All \(cards.count) cards mastered").font(.title3.bold())
                    Text(misses == 0 ? "Perfect run." : "\(misses) repeat\(misses == 1 ? "" : "s") along the way.")
                        .foregroundStyle(.secondary)
                    Button("Shuffle and go again", action: restart)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear(perform: restart)
    }

    private func next(remember: Bool) {
        guard !queue.isEmpty else { return }
        let card = queue.removeFirst()
        if !remember { queue.append(card) }
        showingBack = false
    }

    private func restart() {
        queue = cards.shuffled()
        showingBack = false
        misses = 0
    }
}
