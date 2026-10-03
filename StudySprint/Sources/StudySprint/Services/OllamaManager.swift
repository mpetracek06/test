import AppKit
import Foundation
import StudySprintCore

/// Watches the local Ollama install and manages the free models.
final class OllamaManager: ObservableObject {
    enum Status: Equatable {
        case checking
        case notInstalled
        case notRunning
        case running(version: String)
    }

    struct ModelOption: Identifiable, Hashable {
        let name: String
        let title: String
        let size: String
        let note: String
        var id: String { name }
    }

    /// Good free models for studying, smallest first. Gemma 3 can also read photos of notes.
    static let options: [ModelOption] = [
        ModelOption(name: "llama3.2:3b", title: "Llama 3.2 3B", size: "2.0 GB", note: "Fastest · text only"),
        ModelOption(name: "gemma3:4b", title: "Gemma 3 4B", size: "3.3 GB", note: "Great for 8 GB Macs · reads photos"),
        ModelOption(name: "gemma3:12b", title: "Gemma 3 12B", size: "8.1 GB", note: "Best quality · needs 16 GB+ memory · reads photos"),
    ]

    /// The best model this Mac can comfortably run.
    static var recommended: ModelOption {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return gb >= 15 ? options[2] : options[1]
    }

    static let modelKey = "localModel"

    @Published private(set) var status: Status = .checking
    @Published private(set) var installed: [OllamaClient.InstalledModel] = []
    @Published private(set) var pulling: String?
    @Published private(set) var pullProgress: OllamaClient.PullProgress?
    @Published var pullError: String?
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: Self.modelKey) }
    }

    private var timer: Timer?
    private var watchers = 0
    private var pullTask: Task<Void, Never>?

    init() {
        selectedModel = UserDefaults.standard.string(forKey: Self.modelKey) ?? Self.recommended.name
        refresh()
    }

    var client: OllamaClient { OllamaClient(model: selectedModel) }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    /// Ollama is running and the chosen model is downloaded.
    var isReady: Bool { isRunning && has(selectedModel) }

    func has(_ name: String) -> Bool {
        installed.contains { $0.name == name || $0.name == name + ":latest" }
    }

    var appURL: URL? {
        let paths = ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
        return paths.map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Status

    func refresh() {
        let client = OllamaClient(model: selectedModel)
        Task { @MainActor [weak self] in
            do {
                let version = try await client.version()
                let models = try await client.installedModels()
                guard let self else { return }
                self.installed = models
                self.status = .running(version: version)
                // If the chosen model isn't there but another one is, use what's installed.
                if !self.has(self.selectedModel), self.pulling == nil, let first = models.first {
                    self.selectedModel = first.name
                }
            } catch {
                guard let self else { return }
                self.status = self.appURL == nil ? .notInstalled : .notRunning
                self.installed = []
            }
        }
    }

    /// Views that show setup call this on appear (and `stopWatching` on disappear) so the
    /// status updates the moment someone installs or opens Ollama.
    func startWatching() {
        watchers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        if watchers == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: Actions

    func openDownloadPage() {
        NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
    }

    func launchOllama() {
        guard let url = appURL else { return openDownloadPage() }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refresh() }
        }
    }

    func download(_ name: String) {
        guard pulling == nil else { return }
        pulling = name
        pullError = nil
        pullProgress = OllamaClient.PullProgress(status: "Starting…", completed: 0, total: 0)
        let client = OllamaClient(model: name)
        pullTask = Task { @MainActor [weak self] in
            do {
                try await client.pull(name) { progress in self?.pullProgress = progress }
                self?.selectedModel = name
            } catch is CancellationError {
            } catch {
                self?.pullError = error.localizedDescription
            }
            self?.pulling = nil
            self?.pullProgress = nil
            self?.refresh()
        }
    }

    func cancelDownload() {
        pullTask?.cancel()
        pullTask = nil
        pulling = nil
        pullProgress = nil
    }
}
