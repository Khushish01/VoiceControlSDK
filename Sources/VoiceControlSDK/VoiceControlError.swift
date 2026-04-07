import Foundation

/// Errors that can occur within the voice control engine.
public enum VoiceControlError: LocalizedError {
    /// Speech recognizer is not available on this device.
    case recognizerUnavailable

    /// User denied microphone permission.
    case microphonePermissionDenied

    /// User denied speech recognition permission.
    case speechPermissionDenied

    /// No language configuration found for the requested locale.
    case unsupportedLanguage(String)

    /// Audio engine failed to start.
    case audioEngineFailure(Error)

    /// Speech recognition request failed.
    case recognitionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available on this device."
        case .microphonePermissionDenied:
            return "Microphone permission was denied."
        case .speechPermissionDenied:
            return "Speech recognition permission was denied."
        case .unsupportedLanguage(let locale):
            return "No language configuration found for \(locale)."
        case .audioEngineFailure(let error):
            return "Audio engine failed: \(error.localizedDescription)"
        case .recognitionFailed(let error):
            return "Recognition failed: \(error.localizedDescription)"
        }
    }
}
