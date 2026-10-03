import SwiftUI
import StudySprintCore

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var apiKey = KeychainStore.loadAPIKey() ?? ""
    @State private var reveal = false
    @State private var status: String?
    @State private var testing = false
    @AppStorage(SettingsKey.model) private var model = ClaudeModel.opus.rawValue
    @AppStorage(SettingsKey.depth) private var depth = ResearchDepth.balanced.rawValue
    @AppStorage(ReminderScheduler.enabledKey) private var reminders = true

    var body: some View {
        Form {
            Section("Claude API") {
                HStack {
                    Group {
                        if reveal {
                            TextField("sk-ant-…", text: $apiKey)
                        } else {
                            SecureField("sk-ant-…", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button { reveal.toggle() } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                HStack {
                    Button("Save") {
                        status = app.saveAPIKey(apiKey) ? "Saved to Keychain." : "Couldn't save to Keychain."
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Test connection", action: test)
                        .disabled(testing || apiKey.isEmpty)
                    if testing { ProgressView().controlSize(.small) }
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
                Text("Get a key at console.anthropic.com. It's stored in your macOS Keychain and only sent to api.anthropic.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                Picker("Model", selection: $model) {
                    ForEach(ClaudeModel.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Default research depth", selection: $depth) {
                    ForEach(ResearchDepth.allCases) { Text("\($0.rawValue) (\($0.blurb))").tag($0.rawValue) }
                }
            }

            Section("Reminders") {
                Toggle("Notify me when flashcards are due", isOn: $reminders)
                    .onChange(of: reminders) { on in
                        if on { ReminderScheduler.requestPermission() }
                        ReminderScheduler.schedule(nextDue: app.nextDueDate, dueNow: app.dueCount)
                    }
            }

            Section("Data") {
                HStack {
                    Text("\(app.guides.count) guides · \(app.guides.reduce(0) { $0 + $1.flashcards.count }) flashcards")
                    Spacer()
                    Button("Show in Finder") { app.revealDataFolder() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.vertical, 8)
    }

    private func test() {
        _ = app.saveAPIKey(apiKey)
        testing = true
        status = nil
        let client = app.client
        Task { @MainActor in
            do {
                let reply = try await client.send([
                    "max_tokens": 64,
                    "output_config": ["effort": "low"],
                    "messages": [["role": "user", "content": "Reply with just: OK"]],
                ])
                status = reply.text.isEmpty ? "Connected." : "Connected ✓ (\(client.model))"
            } catch {
                status = error.localizedDescription
            }
            testing = false
        }
    }
}
