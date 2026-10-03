import SwiftUI
import UniformTypeIdentifiers
import StudySprintCore

struct NewGuideView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NewGuideContent(generation: app.generation)
    }
}

private struct NewGuideContent: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var generation: GenerationController

    @AppStorage("draftNotes") private var notes = ""
    @State private var topic = ""
    @State private var budget: TimeBudget = .oneHour
    @State private var level: StartingLevel = .newToIt
    @State private var goal: LearningGoal = .passExam
    @AppStorage(SettingsKey.depth) private var depthRaw = ResearchDepth.balanced.rawValue
    @State private var showImporter = false
    @State private var isDropTarget = false
    @State private var importError: String?

    private var depth: ResearchDepth { ResearchDepth(rawValue: depthRaw) ?? .balanced }
    private var wordCount: Int { notes.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        if generation.isRunning {
            LiveResearchView(generation: generation)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !app.hasAPIKey { APIKeyBanner() }
                    if let error = generation.error {
                        ErrorBanner(message: error) { generation.error = nil }
                    }
                    if let importError {
                        ErrorBanner(message: importError) { self.importError = nil }
                    }
                    notesEditor
                    options
                    buildBar
                }
                .padding(28)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: NotesImporter.supportedTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): urls.forEach(importFile)
                case .failure(let error): importError = error.localizedDescription
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            GradientTitle(text: "Learn anything, fast.", size: 34)
            Text("Drop in your notes. Claude researches the topic, finds the best videos (and exactly which minutes to watch), and builds the shortest path to mastery: core ideas first, then quizzes, a tutor, and spaced-repetition flashcards.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                if notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste lecture notes, a syllabus, a textbook chapter, or just a topic…")
                        Text("…or drop a PDF, Word, Markdown, or text file here.")
                    }
                    .foregroundStyle(.tertiary)
                    .padding(16)
                    .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 240, maxHeight: 420)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(isDropTarget ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.12)),
                                  lineWidth: isDropTarget ? 3 : 1)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: handleDrop)

            HStack(spacing: 12) {
                Button { showImporter = true } label: {
                    Label("Import files…", systemImage: "doc.badge.plus")
                }
                Menu {
                    ForEach(SampleNotes.all, id: \.title) { sample in
                        Button(sample.title) {
                            notes = sample.notes
                            topic = sample.title
                        }
                    }
                } label: {
                    Label("Try an example", systemImage: "wand.and.stars")
                }
                .fixedSize()
                if !notes.isEmpty {
                    Button("Clear") { notes = ""; topic = "" }
                        .buttonStyle(.borderless)
                }
                Spacer()
                Text("\(wordCount) words").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private var options: some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("Topic").foregroundStyle(.secondary)
                    TextField("Optional — inferred from your notes", text: $topic)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Time I have").foregroundStyle(.secondary)
                    Picker("", selection: $budget) {
                        ForEach(TimeBudget.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                GridRow {
                    Text("My level").foregroundStyle(.secondary)
                    Picker("", selection: $level) {
                        ForEach(StartingLevel.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                GridRow {
                    Text("Goal").foregroundStyle(.secondary)
                    Picker("", selection: $goal) {
                        ForEach(LearningGoal.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                GridRow {
                    Text("Research").foregroundStyle(.secondary)
                    HStack {
                        Picker("", selection: $depthRaw) {
                            ForEach(ResearchDepth.allCases) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        .frame(maxWidth: 280)
                        Text(depth.blurb).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var buildBar: some View {
        HStack {
            Text("Tip: ⌘↩ builds. You can keep browsing while it works.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: build) {
                Label("Build my study sprint", systemImage: "bolt.fill")
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !app.hasAPIKey)
        }
    }

    private func build() {
        let request = GuideRequest(notes: notes, topicHint: topic, budget: budget, level: level, goal: goal, depth: depth)
        generation.start(request)
        topic = ""
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { importFile(url) }
            }
        }
        return !providers.isEmpty
    }

    private func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try NotesImporter.text(from: url)
            notes += (notes.isEmpty ? "" : "\n\n") + "# \(url.lastPathComponent)\n" + text
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct APIKeyBanner: View {
    @EnvironmentObject private var app: AppModel
    @State private var key = ""

    var body: some View {
        Card(title: "Connect Claude", systemImage: "key.fill", tint: .orange) {
            Text("StudySprint uses your Anthropic API key. It's stored in your macOS Keychain and only sent to api.anthropic.com. Get one at console.anthropic.com.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                SecureField("sk-ant-…", text: $key)
                    .textFieldStyle(.roundedBorder)
                Button("Save key") { _ = app.saveAPIKey(key) }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Live research

struct LiveResearchView: View {
    @ObservedObject var generation: GenerationController

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    ResearchOrb()
                    VStack(alignment: .leading, spacing: 4) {
                        GradientTitle(text: "Building your sprint", size: 26)
                        HStack(spacing: 8) {
                            PulseDot()
                            Text(generation.phase).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    TimelineView(.periodic(from: generation.startedAt, by: 1)) { ctx in
                        Text(elapsedString(since: generation.startedAt, now: ctx.date))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Button("Cancel", role: .cancel) { generation.cancel() }
                        .keyboardShortcut(.cancelAction)
                }

                HStack(spacing: 12) {
                    StatTile(value: "\(generation.searches)", label: "searches", icon: "magnifyingglass", tint: .blue)
                    StatTile(value: "\(generation.sources.count)", label: "sources read", icon: "doc.text.magnifyingglass", tint: .purple)
                    StatTile(value: "\(generation.videoCount)", label: "videos found", icon: "play.rectangle.fill", tint: .red)
                    StatTile(value: generation.characters > 0 ? "\(generation.characters / 5)" : "–",
                             label: "words written", icon: "pencil.line", tint: .green)
                }
            }
            .padding(24)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(generation.items) { item in
                            ResearchRow(item: item).id(item.id)
                        }
                    }
                    .padding(24)
                }
                .onChange(of: generation.items.count) { _ in
                    if let last = generation.items.last {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.08)))
        .animation(.spring(response: 0.3), value: value)
    }
}

private struct ResearchRow: View {
    let item: ResearchLogItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 6) {
                switch item.kind {
                case .search:
                    Text("Searching ").foregroundColor(.secondary) + Text("“\(item.text)”").bold()
                case .found:
                    Text(item.text).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(item.hits.prefix(5)) { hit in
                            HStack(spacing: 6) {
                                Image(systemName: hit.isVideo ? "play.rectangle.fill" : "globe")
                                    .font(.caption)
                                    .foregroundStyle(hit.isVideo ? Color.red : Color.secondary)
                                Text(hit.title).font(.callout).lineLimit(1)
                                Text(URL(string: hit.url)?.host ?? "").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                case .note:
                    Text(item.text).italic()
                case .phase, .fallback:
                    Text(item.text).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var icon: String {
        switch item.kind {
        case .phase: return "circle.dotted"
        case .search: return "magnifyingglass"
        case .found: return "tray.full"
        case .note: return "lightbulb"
        case .fallback: return "arrow.triangle.branch"
        }
    }

    private var color: Color {
        switch item.kind {
        case .phase: return .secondary
        case .search: return .blue
        case .found: return .purple
        case .note: return .orange
        case .fallback: return .gray
        }
    }
}

/// An animated orb so the wait feels alive.
private struct ResearchOrb: View {
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.gradient)
                .frame(width: 54, height: 54)
                .blur(radius: 8)
                .opacity(0.6)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 48, height: 48)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spin)
            Image(systemName: "brain")
                .font(.title2)
                .foregroundStyle(.white)
        }
        .onAppear { spin = true }
    }
}

enum SampleNotes {
    struct Sample { let title: String; let notes: String }

    static let all: [Sample] = [
        Sample(title: "Cellular respiration", notes: """
        BIO 101 — Lecture 9: Cellular respiration
        - Glucose + O2 -> CO2 + H2O + ATP
        - Glycolysis (cytoplasm): glucose -> 2 pyruvate, net 2 ATP, 2 NADH
        - Pyruvate oxidation -> acetyl CoA
        - Krebs / citric acid cycle (mitochondrial matrix): makes NADH, FADH2, some ATP, releases CO2
        - Electron transport chain + chemiosmosis (inner membrane): proton gradient, ATP synthase, O2 final e- acceptor
        - ~30-32 ATP per glucose
        - Anaerobic: fermentation (lactic acid, alcoholic) regenerates NAD+
        Exam next week: know where each stage happens, inputs/outputs, why O2 matters
        """),
        Sample(title: "Big-O notation", notes: """
        CS intro — algorithm analysis
        Big-O describes how runtime grows with input size n (worst case, ignore constants).
        Common: O(1), O(log n) binary search, O(n) linear scan, O(n log n) merge sort, O(n^2) nested loops, O(2^n).
        Drop constants and lower-order terms. Space complexity too.
        Need to be able to look at code and say its complexity. Interview prep.
        """),
        Sample(title: "Supply and demand", notes: """
        ECON 1 — markets
        demand curve slopes down, supply slopes up, equilibrium price where they cross
        shifts vs movements along the curve
        price ceilings/floors -> shortages/surpluses
        elasticity: % change Qd / % change P
        consumer + producer surplus, deadweight loss from taxes
        """),
    ]
}
