import SwiftUI

struct SettingsView: View {
    @State private var apiKey = KeychainStore.loadAPIKey() ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                SecureField("Anthropic API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        saved = KeychainStore.saveAPIKey(apiKey)
                    }
                    .keyboardShortcut(.defaultAction)
                    if saved {
                        Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Text("Get a key at console.anthropic.com. It's stored in your macOS Keychain and only sent to api.anthropic.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: apiKey) { _ in saved = false }
    }
}
