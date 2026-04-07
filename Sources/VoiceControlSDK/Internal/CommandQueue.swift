import Foundation

/// FIFO command queue with emergency bypass. Executes commands sequentially
/// via delegate callbacks — the SDK never executes domain logic directly.
final class CommandQueue {

    /// Called to execute a command. The closure receives `(command, completion)`.
    /// Host app calls completion(true/false) when done.
    var onExecuteCommand: ((VoiceCommandResult, @escaping (Bool) -> Void) -> Void)?

    /// Called to get an audio file URL for feedback. Checked before text.
    var onGetFeedbackAudioURL: ((VoiceCommandResult, Bool) -> URL?)?

    /// Called to get feedback text after execution (fallback if no audio URL).
    var onGetFeedbackText: ((VoiceCommandResult, Bool) -> String?)?

    /// Called when processing state changes.
    var onProcessingStateChanged: ((Bool) -> Void)?

    private let feedbackEngine: FeedbackEngine
    private var currentLocale: () -> String

    private var queue: [VoiceCommandResult] = []
    private var isProcessing = false

    init(feedbackEngine: FeedbackEngine, currentLocale: @escaping () -> String) {
        self.feedbackEngine = feedbackEngine
        self.currentLocale = currentLocale
    }

    func updateLocaleProvider(_ provider: @escaping () -> String) {
        currentLocale = provider
    }

    func enqueue(_ command: VoiceCommandResult) {
        if command.isEmergency {
            handleEmergency(command)
            return
        }
        queue.append(command)
        if !isProcessing {
            Task { await processQueue() }
        }
    }

    func clearQueue() {
        queue.removeAll()
    }

    // MARK: - Private

    private func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        onProcessingStateChanged?(true)

        while !queue.isEmpty {
            let command = queue.removeFirst()
            await processCommand(command)
        }

        isProcessing = false
        onProcessingStateChanged?(false)
    }

    private func processCommand(_ command: VoiceCommandResult) async {
        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            onExecuteCommand?(command) { success in
                continuation.resume(returning: success)
            }
        }

        // Prefer audio file feedback over TTS text
        if let audioURL = onGetFeedbackAudioURL?(command, succeeded) {
            await feedbackEngine.playAudio(url: audioURL)
        } else if let feedbackText = onGetFeedbackText?(command, succeeded) {
            await feedbackEngine.speak(feedbackText, locale: currentLocale())
        }
    }

    private func handleEmergency(_ command: VoiceCommandResult) {
        queue.removeAll()
        isProcessing = false
        feedbackEngine.stopSpeaking()

        Task {
            onProcessingStateChanged?(true)
            await processCommand(command)
            onProcessingStateChanged?(false)
        }
    }
}
