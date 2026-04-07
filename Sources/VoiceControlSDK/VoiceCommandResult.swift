import Foundation

/// The result of a successfully recognized voice command.
/// Contains the command identifier, raw transcript, and any extracted parameters.
public struct VoiceCommandResult {

    /// The command definition identifier (e.g., "startWorkout", "resistanceSet").
    public let identifier: String

    /// The raw speech transcript before normalization.
    public let rawTranscript: String

    /// The normalized transcript after fuzzy matching.
    public let normalizedTranscript: String

    /// Extracted parameters (e.g., ["level": 5] for "resistance set to 5").
    public let parameters: [String: Any]

    /// Whether this is an emergency command that bypassed the queue.
    public let isEmergency: Bool

    public init(
        identifier: String,
        rawTranscript: String,
        normalizedTranscript: String,
        parameters: [String: Any] = [:],
        isEmergency: Bool = false
    ) {
        self.identifier = identifier
        self.rawTranscript = rawTranscript
        self.normalizedTranscript = normalizedTranscript
        self.parameters = parameters
        self.isEmergency = isEmergency
    }
}
