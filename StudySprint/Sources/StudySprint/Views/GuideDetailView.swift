import AppKit
import SwiftUI
import UniformTypeIdentifiers
import StudySprintCore

struct GuideDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Binding var guide: StudyGuide
    @State private var showSprint = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Picker("", selection: $app.tab) {
                ForEach(GuideTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch app.tab {
                case .plan: PlanView(guide: $guide, onStartSprint: { showSprint = true })
                case .map: KnowledgeMapView(guide: $guide, onStartSprint: { showSprint = true })
                case .tutor: TutorView(guide: $guide)
                case .quiz: QuizView(guide: $guide)
                case .feynman: FeynmanView(guide: $guide)
                case .cards: CardsView(guide: $guide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if ["sprint", "recall", "testout"].contains(AppModel.screenshotScreen ?? "") { showSprint = true }
        }
        .sheet(isPresented: $showSprint) {
            SprintModeView(guide: $guide)
                .environmentObject(app)
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Cheat sheet (PDF)…", action: exportCheatSheet)
                    Button("Full guide (Markdown)…", action: exportMarkdown)
                    Divider()
                    Button("Copy guide as Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(MarkdownExporter.markdown(for: guide), forType: .string)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export a cheat sheet or the full guide")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(guide.emoji)
                .font(.system(size: 46))
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.gradient.opacity(0.18)))
            VStack(alignment: .leading, spacing: 6) {
                Text(guide.topic)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Pill(text: "\(guide.totalMinutes) min plan", systemImage: "clock", tint: .indigo)
                    Pill(text: "\(guide.completedSteps)/\(guide.steps.count) steps", systemImage: "list.number", tint: .purple)
                    let due = guide.dueCards().count
                    if due > 0 {
                        Pill(text: "\(due) cards due", systemImage: "rectangle.stack", tint: .orange)
                    }
                    if let cost = guide.buildCost, cost > 0 {
                        Pill(text: "≈ \(CostEstimator.format(cost))", systemImage: "dollarsign.circle", tint: .secondary)
                            .help("Approximate API cost to build this guide")
                    }
                    if guide.minutesStudied >= 1 {
                        Pill(text: "\(Int(guide.minutesStudied)) min studied", systemImage: "flame", tint: .pink)
                    }
                }
            }
            Spacer()
            ProgressRing(progress: guide.progress, lineWidth: 6, size: 56)
            Button {
                showSprint = true
            } label: {
                Label(guide.progress == 0 ? "Start sprint" : guide.progress >= 1 ? "Sprint again" : "Resume sprint",
                      systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .help("Focus mode: one step at a time (⇧⌘S)")
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(guide.topic) – study sprint.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MarkdownExporter.markdown(for: guide).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }

    @MainActor
    private func exportCheatSheet() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(guide.topic) – cheat sheet.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CheatSheetRenderer.writePDF(for: guide, to: url)
            NSWorkspace.shared.open(url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
