import AppKit
import Foundation
import StudySprintCore

/// Finds Claude Code on this Mac and checks it's logged in with a Claude account (not an API key).
final class ClaudeCodeManager: ObservableObject {
    static let modelKey = "claudeCodeModel"
    static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    @Published private(set) var install: ClaudeCodeRunner.Installation?
    @Published private(set) var auth: ClaudeCodeRunner.AuthStatus?
    @Published private(set) var checking = false
    @Published var model: ClaudeCodeRunner.Model {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey) }
    }

    private var timer: Timer?
    private var watchers = 0

    init() {
        model = UserDefaults.standard.string(forKey: Self.modelKey).flatMap(ClaudeCodeRunner.Model.init(rawValue:)) ?? .sonnet
    }

    var isInstalled: Bool { install != nil }
    var isLoggedIn: Bool { auth?.loggedIn == true }
    /// Installed and logged in with a Claude subscription, so runs use plan usage, never money.
    var isReady: Bool { isInstalled && auth?.usesSubscription == true }

    var runner: ClaudeCodeRunner? {
        install.map { ClaudeCodeRunner(executable: $0.executable, searchPath: $0.searchPath, model: model) }
    }

    /// Checks for the CLI and its login (runs the shell off the main thread).
    @discardableResult
    func refresh() async -> Bool {
        await MainActor.run { checking = true }
        let found = await Task.detached(priority: .utility) { () -> (ClaudeCodeRunner.Installation?, ClaudeCodeRunner.AuthStatus?) in
            guard let install = ClaudeCodeRunner.locate() else { return (nil, nil) }
            return (install, ClaudeCodeRunner.authStatus(install))
        }.value
        return await MainActor.run {
            install = found.0
            auth = found.1
            checking = false
            return isReady
        }
    }

    func startWatching() {
        watchers += 1
        Task { await refresh() }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self, !self.checking, !self.isReady else { return }
            Task { await self.refresh() }
        }
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        if watchers == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: Setup actions (run in Terminal so the person sees exactly what happens)

    func installInTerminal() {
        runInTerminal(Self.installCommand)
    }

    func loginInTerminal() {
        let path = install?.executable.path ?? "claude"
        runInTerminal("'\(path)' auth login")
    }

    func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.installCommand, forType: .string)
    }

    private func runInTerminal(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error != nil {
            // Automation not allowed: open Terminal and put the command on the clipboard instead.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }
}
