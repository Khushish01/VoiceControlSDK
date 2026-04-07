import Foundation

/// The current state of the voice control engine.
public enum VoiceControlState: Sendable {
    /// Engine is not active. Call `start()` to begin.
    case idle

    /// Passively listening for wake word only.
    case passiveListening

    /// Actively listening for commands after wake word detected.
    case activeListening

    /// Processing a recognized command (executing + giving feedback).
    case processing
}
