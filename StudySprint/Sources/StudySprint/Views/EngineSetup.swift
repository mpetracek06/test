import SwiftUI
import StudySprintCore

/// Shown on the New Sprint screen until an engine is ready: free local setup or a Claude key.
struct EngineSetupCard: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var ollama: OllamaManager
    @ObservedObject var claudeCode: ClaudeCodeManager

    var body: some View {
        Card(title: "Set up StudySprint", systemImage: "wand.and.stars", tint: .indigo) {
            Picker("", selection: $app.engineKind) {
                ForEach(EngineKind.allCases) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)

            switch app.engineKind {
            case .free: FreeSetupSteps(ollama: ollama)
            case .plan: PlanSetupSteps(claudeCode: claudeCode)
            case .claude: ClaudeKeyForm()
            }

            HStack(spacing: 6) {
                Text("Just looking?").foregroundStyle(.secondary)
                Button("Explore a demo sprint →") { app.loadDemo() }
                    .buttonStyle(.link)
            }
            .font(.callout)
        }
    }
}

/// The three steps to free mode: install Ollama, open it, download a model.
struct FreeSetupSteps: View {
    @ObservedObject var ollama: OllamaManager
    var showModelPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Free mode uses **Ollama**, a free app that runs AI models privately on your Mac — no account, no API key, no cost. Your notes never leave your computer. Videos come from free YouTube search.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SetupStep(number: 1, done: ollama.status != .notInstalled && ollama.status != .checking,
                      title: "Install Ollama (free)") {
                if ollama.status == .notInstalled {
                    HStack {
                        Button("Download Ollama") { ollama.openDownloadPage() }
                            .buttonStyle(.borderedProminent).tint(.indigo)
                        Text("Open the download, drag Ollama to Applications, then open it once.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            SetupStep(number: 2, done: ollama.isRunning, title: "Open Ollama") {
                if ollama.status == .notRunning {
                    HStack {
                        Button("Open Ollama") { ollama.launchOllama() }
                            .buttonStyle(.borderedProminent).tint(.indigo)
                        Text("It runs quietly in your menu bar. This page updates by itself.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if ollama.status == .checking {
                    ProgressView().controlSize(.small)
                }
            }

            SetupStep(number: 3, done: ollama.isReady, title: "Download a study model (one time)") {
                if ollama.isRunning && (!ollama.isReady || showModelPicker) {
                    ModelChooser(ollama: ollama)
                }
            }

            if ollama.isReady {
                Label("Ready! Everything is free from here on.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }
        }
        .onAppear { ollama.startWatching() }
        .onDisappear { ollama.stopWatching() }
    }
}

/// Claude plan mode: StudySprint drives Claude Code (`claude -p`), logged in with the person's
/// Claude account, so it uses plan usage and never API credit.
struct PlanSetupSteps: View {
    @ObservedObject var claudeCode: ClaudeCodeManager
    var showModelPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Uses your **Claude Pro or Max plan** through **Claude Code**, Anthropic's official app. Guides count toward your plan's usage limits — no API key, no credit, no extra charges. You get Claude's full quality, including live web research.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SetupStep(number: 1, done: claudeCode.isInstalled, title: "Install Claude Code (free download)") {
                if !claudeCode.isInstalled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button("Install in Terminal") { claudeCode.installInTerminal() }
                                .buttonStyle(.borderedProminent).tint(.indigo)
                            Button("Copy command") { claudeCode.copyInstallCommand() }
                        }
                        Text("Runs Anthropic's official installer: `\(ClaudeCodeManager.installCommand)`")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } else if let v = claudeCode.install?.version {
                    Text(v).font(.caption).foregroundStyle(.secondary)
                }
            }

            SetupStep(number: 2, done: claudeCode.isReady, title: "Log in with your Claude account") {
                if claudeCode.isInstalled && !claudeCode.isReady {
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Log in") { claudeCode.loginInTerminal() }
                            .buttonStyle(.borderedProminent).tint(.indigo)
                        if claudeCode.auth?.loggedIn == true {
                            Text("Claude Code is logged in with an API key, which would cost money. Log in again and choose your Claude account (Pro/Max) instead.")
                                .font(.caption).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Terminal opens; choose your Claude account (Pro or Max) in the browser. This page updates by itself.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if claudeCode.isReady {
                Label("Ready! Guides use your Claude plan — never API credit.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            if claudeCode.isReady || showModelPicker {
                Picker("Model", selection: $claudeCode.model) {
                    ForEach(ClaudeCodeRunner.Model.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 460)
            }

            HStack {
                Button("Check again") { Task { await claudeCode.refresh() } }
                    .disabled(claudeCode.checking)
                if claudeCode.checking { ProgressView().controlSize(.small) }
            }
            .font(.caption)
        }
        .onAppear { claudeCode.startWatching() }
        .onDisappear { claudeCode.stopWatching() }
    }
}

struct ModelChooser: View {
    @ObservedObject var ollama: OllamaManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(OllamaManager.options) { option in
                HStack(spacing: 10) {
                    Image(systemName: ollama.selectedModel == option.name && ollama.has(option.name)
                          ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(Color.indigo)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(option.title).font(.body.weight(.medium))
                            if option == OllamaManager.recommended {
                                Pill(text: "Recommended for this Mac", tint: .green)
                            }
                        }
                        Text("\(option.size) · \(option.note)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if ollama.has(option.name) {
                        if ollama.selectedModel == option.name {
                            Text("In use").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Use") { ollama.selectedModel = option.name }
                        }
                    } else if ollama.pulling == option.name {
                        Button("Cancel") { ollama.cancelDownload() }
                    } else {
                        Button("Download") { ollama.download(option.name) }
                            .disabled(ollama.pulling != nil)
                    }
                }
                if ollama.pulling == option.name, let p = ollama.pullProgress {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: p.fraction)
                        Text(p.total > 0
                             ? "\(p.status) · \(ByteCountFormatter.string(fromByteCount: p.completed, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: p.total, countStyle: .file))"
                             : p.status)
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.leading, 28)
                }
            }
            // Any other model already installed in Ollama can be used too.
            let others = ollama.installed.map(\.name).filter { name in
                !OllamaManager.options.contains { name == $0.name || name == $0.name + ":latest" }
            }
            if !others.isEmpty {
                Picker("Other installed models", selection: $ollama.selectedModel) {
                    ForEach(others, id: \.self) { Text($0).tag($0) }
                    if !others.contains(ollama.selectedModel) { Text("—").tag(ollama.selectedModel) }
                }
                .frame(maxWidth: 360)
            }
            if let error = ollama.pullError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

private struct SetupStep<Content: View>: View {
    let number: Int
    let done: Bool
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.indigo.opacity(0.15)).frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.bold()).foregroundStyle(Color.indigo)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline).foregroundStyle(done ? .secondary : .primary)
                content
            }
            Spacer(minLength: 0)
        }
    }
}

struct ClaudeKeyForm: View {
    @EnvironmentObject private var app: AppModel
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude researches the web live and writes the best guides. Each guide costs a few cents of API credit (billed by Anthropic, separate from a Claude.ai subscription). Your key is stored in your macOS Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField("sk-ant-…", text: $key)
                    .textFieldStyle(.roundedBorder)
                Button("Save key") { _ = app.saveAPIKey(key) }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
                Link("Get a key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
            }
        }
    }
}

/// Small "which engine" control next to the Build button.
struct EngineMenu: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var ollama: OllamaManager

    var body: some View {
        Menu {
            Picker("Engine", selection: $app.engineKind) {
                ForEach(EngineKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(app.engineLabel, systemImage: app.engineKind == .free ? "leaf.fill" : "sparkles")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose which AI builds your sprint")
    }
}
