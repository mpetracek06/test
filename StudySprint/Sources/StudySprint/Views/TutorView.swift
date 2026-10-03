import SwiftUI
import StudySprintCore

struct TutorView: View {
    @EnvironmentObject private var app: AppModel
    @Binding var guide: StudyGuide

    @State private var input = ""
    @State private var streamingText = ""
    @State private var status = ""
    @State private var isStreaming = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    private var suggestions: [String] {
        var s = ["Explain the hardest idea here like I'm 12",
                 "Quiz me, one question at a time",
                 "What will most likely be on the exam?"]
        if let first = guide.paretoConcepts.first {
            s.insert("Give me a real-world example of: \(first)", at: 1)
        }
        if let next = guide.nextStepIndex {
            s.append("Find me another great video on “\(guide.steps[next].title)”")
        }
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if guide.tutorTurns.isEmpty && !isStreaming {
                            welcome
                        }
                        ForEach(guide.tutorTurns) { turn in
                            ChatBubble(role: turn.role, text: turn.text).id(turn.id)
                        }
                        if isStreaming {
                            ChatBubble(role: .assistant, text: streamingText, status: status, isLive: true)
                                .id("live")
                        }
                        if let error {
                            ErrorBanner(message: error) { self.error = nil }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(24)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: streamingText) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: guide.tutorTurns.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }

            Divider()
            composer
        }
        .onAppear {
            if let prompt = app.pendingTutorPrompt {
                app.pendingTutorPrompt = nil
                send(prompt)
            }
            inputFocused = true
        }
        .onDisappear { task?.cancel() }
        .toolbar {
            ToolbarItem {
                Button {
                    task?.cancel()
                    guide.tutorTurns = []
                    guide.tutorSystem = nil
                    error = nil
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                }
                .help("Start a fresh tutor conversation")
                .disabled(guide.tutorTurns.isEmpty)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your personal tutor").font(.title2.bold())
                    Text("Knows your whole study guide. Ask anything — or pick a starter.")
                        .foregroundStyle(.secondary)
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button(s) { send(s) }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask your tutor…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { send(input) }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
            if isStreaming {
                Button {
                    task?.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.title)
                }
                .buttonStyle(.borderless)
                .help("Stop")
            } else {
                Button {
                    send(input)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                        .foregroundStyle(Theme.gradient)
                }
                .buttonStyle(.borderless)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send (Return)")
            }
        }
        .padding(14)
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""
        error = nil
        if guide.tutorSystem == nil {
            guide.tutorSystem = LearningServices.tutorSystem(for: guide)
        }
        let system = guide.tutorSystem ?? ""
        guide.tutorTurns.append(ChatTurn(role: .user, text: text))
        let history = guide.tutorTurns
        let services = app.services
        streamingText = ""
        status = ""
        isStreaming = true

        task = Task { @MainActor in
            do {
                let reply = try await services.tutorReply(
                    system: system,
                    history: history,
                    onText: { streamingText += $0; status = "" },
                    onStatus: { status = $0 }
                )
                guide.tutorTurns.append(reply)
            } catch {
                // Keep the conversation strictly alternating: take back the unanswered message.
                if guide.tutorTurns.last?.role == .user {
                    guide.tutorTurns.removeLast()
                    input = text
                }
                if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                    self.error = error.localizedDescription
                }
            }
            isStreaming = false
            streamingText = ""
        }
    }
}

struct ChatBubble: View {
    let role: ChatTurn.Role
    let text: String
    var status: String = ""
    var isLive = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if role == .user { Spacer(minLength: 80) }
            if role == .assistant {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(Theme.gradient)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.indigo.opacity(0.12)))
            }
            VStack(alignment: .leading, spacing: 6) {
                if !status.isEmpty {
                    HStack(spacing: 6) {
                        PulseDot(color: .blue)
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if text.isEmpty && isLive {
                    HStack(spacing: 6) {
                        PulseDot()
                        Text("Thinking…").foregroundStyle(.secondary)
                    }
                } else {
                    MarkdownText(text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(role == .user ? AnyShapeStyle(Color.indigo.opacity(0.85)) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
            )
            .foregroundStyle(role == .user ? Color.white : Color.primary)
            if role == .assistant { Spacer(minLength: 80) }
        }
    }
}

/// Wraps children onto new lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
