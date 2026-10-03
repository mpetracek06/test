import SwiftUI
import UniformTypeIdentifiers

struct NewGuideView: View {
    @EnvironmentObject private var store: GuideStore
    var onCreated: (UUID) -> Void

    @State private var notes = ""
    @State private var topic = ""
    @State private var budget: TimeBudget = .oneHour
    @State private var level: StartingLevel = .newToIt
    @State private var goal: LearningGoal = .passExam

    @State private var isWorking = false
    @State private var status = ""
    @State private var startedAt = Date()
    @State private var errorMessage: String?
    @State private var showImporter = false
    @State private var isDropTarget = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Turn your notes into a study sprint")
                    .font(.largeTitle.bold())
                Text("Paste or drop your notes. You'll get the shortest path to learning it: the core ideas first, hand-picked videos (with exactly which parts to watch), recall questions, and flashcards.")
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if notes.isEmpty {
                    Text("Paste lecture notes, a syllabus, textbook excerpts… or drop a .txt, .md, .pdf, .docx file here.")
                        .foregroundStyle(.tertiary)
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isDropTarget ? Color.accentColor : Color.secondary.opacity(0.25),
                                  lineWidth: isDropTarget ? 2 : 1)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: handleDrop)
            .frame(minHeight: 220)

            HStack(spacing: 10) {
                Button {
                    showImporter = true
                } label: {
                    Label("Import file…", systemImage: "doc.badge.plus")
                }
                Text("\(notes.split(whereSeparator: \.isWhitespace).count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("Topic (optional — inferred from notes)", text: $topic)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Time I have").foregroundStyle(.secondary)
                    Picker("", selection: $budget) {
                        ForEach(TimeBudget.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("My level").foregroundStyle(.secondary)
                    Picker("", selection: $level) {
                        ForEach(StartingLevel.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Goal").foregroundStyle(.secondary)
                    Picker("", selection: $goal) {
                        ForEach(LearningGoal.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .frame(maxWidth: 640, alignment: .leading)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text("\(status)  \(Int(context.date.timeIntervalSince(startedAt)))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button("Cancel") { task?.cancel() }
                }
                Spacer()
                Button {
                    generate()
                } label: {
                    Label("Build my study sprint", systemImage: "bolt.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isWorking || notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: NotesImporter.supportedTypes,
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): urls.forEach(importFile)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func generate() {
        errorMessage = nil
        isWorking = true
        startedAt = Date()
        status = "Starting…"
        let request = GuideRequest(notes: notes, topicHint: topic, budget: budget, level: level, goal: goal)
        let client = ClaudeClient(apiKey: KeychainStore.loadAPIKey() ?? "")

        task = Task { @MainActor in
            defer { isWorking = false }
            do {
                let guide = try await client.generateGuide(request) { status = $0 }
                store.add(guide)
                notes = ""
                topic = ""
                onCreated(guide.id)
            } catch is CancellationError {
                errorMessage = "Cancelled."
            } catch let error as URLError where error.code == .cancelled {
                errorMessage = "Cancelled."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
            errorMessage = error.localizedDescription
        }
    }
}
