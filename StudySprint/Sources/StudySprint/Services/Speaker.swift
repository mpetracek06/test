import AVFoundation
import Foundation

/// Reads explanations aloud — handy for learning while your eyes rest.
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    @Published private(set) var speakingID: String?
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggle(id: String, text: String) {
        if speakingID == id {
            stop()
            return
        }
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: Self.plain(text))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08
        speakingID = id
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        speakingID = nil
    }

    /// Drops Markdown punctuation so it isn't read out.
    static func plain(_ markdown: String) -> String {
        var s = markdown
        for token in ["**", "__", "`", "#"] { s = s.replacingOccurrences(of: token, with: "") }
        return s
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speakingID = nil }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if !synthesizer.isSpeaking { self.speakingID = nil }
        }
    }
}
