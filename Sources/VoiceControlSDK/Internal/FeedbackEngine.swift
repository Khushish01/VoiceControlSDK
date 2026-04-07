import Foundation
import AVFoundation

/// Feedback engine that plays pre-recorded audio files or falls back to TTS.
/// Notifies when playback starts/stops so speech recognition can be paused/resumed.
final class FeedbackEngine: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {

    var onSpeakingStateChanged: ((Bool) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var completionHandler: (() -> Void)?
    private let speechRate: Float
    private let speechPitch: Float
    private let voiceIdentifiers: [String: String]

    init(speechRate: Float, speechPitch: Float, voiceIdentifiers: [String: String] = [:]) {
        self.speechRate = speechRate
        self.speechPitch = speechPitch
        self.voiceIdentifiers = voiceIdentifiers
        super.init()
        synthesizer.delegate = self
    }

    /// Plays a pre-recorded audio file. Async — returns after playback completes.
    func playAudio(url: URL) async {
        onSpeakingStateChanged?(true)
        try? await Task.sleep(nanoseconds: 600_000_000)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                self.audioPlayer = player
                player.delegate = self
                self.completionHandler = { continuation.resume() }
                player.play()
            } catch {
                print("[FeedbackEngine] Audio playback failed: \(error)")
                continuation.resume()
            }
        }

        try? await Task.sleep(nanoseconds: 800_000_000)
        onSpeakingStateChanged?(false)
    }

    /// Speaks the given text in the specified locale. Async — returns after speech completes.
    func speak(_ text: String, locale: String) async {
        onSpeakingStateChanged?(true)
        try? await Task.sleep(nanoseconds: 600_000_000)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let utterance = AVSpeechUtterance(string: text)
            if let voiceId = voiceIdentifiers[locale],
               let customVoice = AVSpeechSynthesisVoice(identifier: voiceId) {
                utterance.voice = customVoice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: locale)
            }
            utterance.rate = speechRate
            utterance.pitchMultiplier = speechPitch
            utterance.postUtteranceDelay = 0.3
            self.completionHandler = { continuation.resume() }
            synthesizer.speak(utterance)
        }

        try? await Task.sleep(nanoseconds: 800_000_000)
        onSpeakingStateChanged?(false)
    }

    /// Immediately stops any ongoing speech or audio playback.
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completionHandler?()
        completionHandler = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completionHandler?()
        completionHandler = nil
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayer = nil
        completionHandler?()
        completionHandler = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        audioPlayer = nil
        completionHandler?()
        completionHandler = nil
    }
}
