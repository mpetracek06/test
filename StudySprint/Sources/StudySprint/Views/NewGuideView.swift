import SwiftUI
import UniformTypeIdentifiers
import StudySprintCore

struct NewGuideView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NewGuideContent(generation: app.generation, ollama: app.ollama, claudeCode: app.claudeCode)
    }
}

private struct NewGuideContent: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var generation: GenerationController
    @ObservedObject var ollama: OllamaManager
    @ObservedObject var claudeCode: ClaudeCodeManager

    @AppStorage("draftNotes") private var notes = ""
    @State private var topic = ""
    @State private var budget: TimeBudget = .oneHour
    @State private var level: StartingLevel = .newToIt
    @State private var goal: LearningGoal = .passExam
    @AppStorage(SettingsKey.depth) private var depthRaw = ResearchDepth.balanced.rawValue
    @State private var showImporter = false
    @State private var isDropTarget = false
    @State private var importError: String?
    @State private var attachments: [NoteAttachment] = []

    private var depth: ResearchDepth { ResearchDepth(rawValue: depthRaw) ?? .balanced }
    private var wordCount: Int { notes.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        if generation.isRunning {
            LiveResearchView(generation: generation)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !app.engineReady { EngineSetupCard(ollama: ollama, claudeCode: claudeCode) }
                    if let error = generation.error {
                        ErrorBanner(message: error) { generation.error = nil }
                    }
                    if let importError {
                        ErrorBanner(message: importError) { self.importError = nil }
                    }
                    notesEditor
                    if !attachments.isEmpty { attachmentStrip }
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
            Text("Drop in your notes. StudySprint finds the best videos and builds the shortest path to mastery: core ideas first, then quizzes, a tutor, and spaced-repetition flashcards.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                NotesTextEditor(text: $notes, onPictures: addPictures, onFiles: { $0.forEach(importFile) })
                    .padding(4)
                if notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste lecture notes, a syllabus, a textbook chapter, or just a topic…")
                        Text("…or drop PDFs, Word docs, or photos of handwritten notes here.")
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
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTarget, perform: handleDrop)

            HStack(spacing: 12) {
                Button { showImporter = true } label: {
                    Label("Import files…", systemImage: "doc.badge.plus")
                }
                Button(action: pasteImage) {
                    Label("Paste image", systemImage: "photo.on.rectangle")
                }
                .help("Paste a screenshot or photo of your notes from the clipboard")
                Menu {
                    ForEach(SampleNotes.all, id: \.title) { sample in
                        Button(sample.title) {
                            notes = sample.notes
                            topic = sample.title
                        }
                    }
                    Divider()
                    Button("Open the ready-made demo sprint") { app.loadDemo() }
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
                if app.engineKind != .free {
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
    }

    private var buildBar: some View {
        HStack {
            EngineMenu(ollama: ollama)
            Text("⌘↩ builds · keep browsing while it works")
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
            .disabled((notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty) || !app.engineReady)
        }
    }

    private func build() {
        var request = GuideRequest(notes: notes, topicHint: topic, budget: budget, level: level, goal: goal, depth: depth)
        request.attachments = attachments
        generation.start(request)
        topic = ""
        attachments = []
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { importFile(url) }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    DispatchQueue.main.async { addImage(image, name: "Dropped image") }
                }
            }
        }
        return !providers.isEmpty
    }

    private func pasteImage() {
        let pictures = NotesImporter.pictures(from: .general)
        guard !pictures.isEmpty else {
            importError = "There's no picture on the clipboard. Copy a picture, a screenshot, or text with pictures first."
            return
        }
        addPictures(pictures)
    }

    /// Pictures that arrived with pasted or dropped content.
    private func addPictures(_ pictures: [NoteAttachment]) {
        let room = max(0, Self.maxFigures - attachments.filter(\.isFigure).count)
        let accepted = pictures.prefix(room)
        withAnimation { attachments += accepted }
        if accepted.count < pictures.count {
            importError = "Only the first \(Self.maxFigures) pictures are used in one guide."
        }
    }

    private func addImage(_ image: NSImage, name: String) {
        if let a = NotesImporter.attachment(from: image, name: name) {
            withAnimation { attachments.append(a) }
        } else {
            importError = "Couldn't read that image."
        }
    }

    static let maxFigures = 20

    private var attachmentStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            let figureCount = attachments.filter(\.isFigure).count
            Text(figureCount > 0
                 ? "\(figureCount) picture\(figureCount == 1 ? "" : "s") will be shown in your guide and explained. Right-click a photo of handwritten notes to mark it as a notes page instead."
                 : "These are read as pages of your notes — handwriting included.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(attachments) { a in
                        ZStack(alignment: .topTrailing) {
                            VStack(spacing: 4) {
                                Group {
                                    if a.kind == .image, let img = NSImage(data: a.data) {
                                        Image(nsImage: img).resizable().scaledToFill()
                                    } else {
                                        Image(systemName: "doc.richtext").font(.system(size: 30)).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 96, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                                Text(a.name).font(.caption2).lineLimit(1).frame(width: 96)
                                Text(a.isFigure ? "Picture to explain" : a.kind == .pdf ? "Scanned pages" : "Notes page")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(a.isFigure ? Color.indigo : Color.secondary)
                            }
                            .contextMenu {
                                if a.kind == .image {
                                    Button(a.isFigure ? "Treat as a page of notes (read, not shown)" : "Treat as a picture to explain") {
                                        if let i = attachments.firstIndex(where: { $0.id == a.id }) {
                                            attachments[i].role = a.isFigure ? .page : .figure
                                        }
                                    }
                                }
                                Button("Remove", role: .destructive) { attachments.removeAll { $0.id == a.id } }
                            }
                            Button {
                                withAnimation { attachments.removeAll { $0.id == a.id } }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            for item in try NotesImporter.load(from: url) {
                switch item {
                case .text(let text):
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    notes += (notes.isEmpty ? "" : "\n\n") + "# \(url.lastPathComponent)\n" + text
                case .attachment(let a):
                    guard attachments.filter(\.isFigure).count < Self.maxFigures || !a.isFigure else { continue }
                    withAnimation { attachments.append(a) }
                }
            }
        } catch {
            importError = error.localizedDescription
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
