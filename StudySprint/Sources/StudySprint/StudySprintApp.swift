import AppKit
import SwiftUI

@main
struct StudySprintApp: App {
    @StateObject private var store = GuideStore()

    init() {
        // Lets the app show a normal window and Dock icon when launched with `swift run`.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("StudySprint") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }
}
