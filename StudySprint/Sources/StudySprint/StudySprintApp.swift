import AppKit
import SwiftUI
import StudySprintCore

@main
struct StudySprintApp: App {
    @StateObject private var app = AppModel()

    init() {
        // Lets the app show a normal window and Dock icon when launched with `swift run`.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("StudySprint", id: "main") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 1040, minHeight: 680)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    app.saveNow()
                    ReminderScheduler.schedule(nextDue: app.nextDueDate, dueNow: app.dueCount)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    ReminderScheduler.schedule(nextDue: app.nextDueDate, dueNow: app.dueCount)
                }
                .onAppear {
                    if ReminderScheduler.isEnabled && !app.guides.isEmpty { ReminderScheduler.requestPermission() }
                }
        }
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Study Sprint") { app.selection = .newGuide }
                    .keyboardShortcut("n")
            }
            CommandMenu("Study") {
                Button("Review Due Cards") { app.selection = .review }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                ForEach(GuideTab.allCases) { tab in
                    Button(tab.rawValue) { app.tab = tab }
                        .keyboardShortcut(KeyEquivalent(Character("\(GuideTab.allCases.firstIndex(of: tab)! + 1)")))
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(app)
        } label: {
            Image(systemName: "brain.head.profile")
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let due = app.dueCount
        let streak = app.log.streak()
        Text(due == 0 ? "All caught up" : "\(due) card\(due == 1 ? "" : "s") due")
        Text(streak > 0 ? "🔥 \(streak)-day streak" : "Start a streak today")
        Divider()
        Button("Review Now") { show(.review) }
            .disabled(due == 0)
        Button("New Study Sprint") { show(.newGuide) }
        if let recent = app.guides.first {
            Button("Continue \(recent.emoji) \(recent.topic)") { show(.guide(recent.id)) }
        }
        Divider()
        Button("Quit StudySprint") { NSApplication.shared.terminate(nil) }
    }

    private func show(_ item: SidebarItem) {
        app.selection = item
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
