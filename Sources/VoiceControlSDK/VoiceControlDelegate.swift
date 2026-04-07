import Foundation

/// Protocol the host app implements to receive events and execute commands from the SDK.
public protocol VoiceControlDelegate: AnyObject {

    // MARK: - Command Execution

    /// Called when a command is recognized and should be executed.
    /// Host app performs the actual action (BLE command, state change, etc.)
    /// and calls `completion(true)` on success or `completion(false)` on failure.
    func voiceControl(
        _ engine: VoiceControlEngine,
        didRecognizeCommand command: VoiceCommandResult,
        completion: @escaping (Bool) -> Void
    )

    /// Called to get an audio file URL for feedback after a command executes.
    /// Return a URL to a pre-recorded audio file, or nil to fall back to TTS text.
    /// This is checked first — if it returns a URL, `feedbackTextFor` is not called.
    func voiceControl(
        _ engine: VoiceControlEngine,
        feedbackAudioURLFor command: VoiceCommandResult,
        language: String,
        succeeded: Bool
    ) -> URL?

    /// Called to get the feedback text to speak after a command executes.
    /// Only called if `feedbackAudioURLFor` returns nil.
    /// Return the text to speak, or nil to skip voice feedback for this command.
    func voiceControl(
        _ engine: VoiceControlEngine,
        feedbackTextFor command: VoiceCommandResult,
        language: String,
        succeeded: Bool
    ) -> String?

    // MARK: - Wake Word

    /// Called when the wake word is detected. `actionId` identifies which wake action
    /// was triggered (e.g., "default", "connectDevice"). Nil if no specific action matched.
    func voiceControlDidDetectWakeWord(
        _ engine: VoiceControlEngine,
        actionId: String?
    )

    // MARK: - State & Transcript

    /// Called when the engine state changes (idle, passive, active, processing).
    func voiceControl(
        _ engine: VoiceControlEngine,
        didChangeState state: VoiceControlState
    )

    /// Called with partial (real-time) transcript updates as the user speaks.
    func voiceControl(
        _ engine: VoiceControlEngine,
        didTranscribePartial text: String
    )

    // MARK: - Unrecognized & Errors

    /// Called when speech was heard but no command matched (only in active mode).
    /// Return a URL to a pre-recorded audio file, or nil to fall back to text feedback.
    func voiceControl(
        _ engine: VoiceControlEngine,
        unrecognizedSpeechAudioURLFor transcript: String,
        language: String
    ) -> URL?

    /// Called when speech was heard but no command matched (only in active mode).
    /// Only called if `unrecognizedSpeechAudioURLFor` returns nil.
    /// Host app can provide feedback text to speak, or return nil to stay silent.
    func voiceControl(
        _ engine: VoiceControlEngine,
        didReceiveUnrecognizedSpeech transcript: String,
        language: String
    ) -> String?

    /// Called when an error occurs in the engine.
    func voiceControl(
        _ engine: VoiceControlEngine,
        didEncounterError error: VoiceControlError
    )
}

// MARK: - Default Implementations (all optional except command execution)

public extension VoiceControlDelegate {
    func voiceControl(_ engine: VoiceControlEngine, feedbackAudioURLFor command: VoiceCommandResult, language: String, succeeded: Bool) -> URL? { nil }
    func voiceControlDidDetectWakeWord(_ engine: VoiceControlEngine, actionId: String?) {}
    func voiceControl(_ engine: VoiceControlEngine, didChangeState state: VoiceControlState) {}
    func voiceControl(_ engine: VoiceControlEngine, didTranscribePartial text: String) {}
    func voiceControl(_ engine: VoiceControlEngine, unrecognizedSpeechAudioURLFor transcript: String, language: String) -> URL? { nil }
    func voiceControl(_ engine: VoiceControlEngine, didReceiveUnrecognizedSpeech transcript: String, language: String) -> String? { nil }
    func voiceControl(_ engine: VoiceControlEngine, didEncounterError error: VoiceControlError) {}
}
