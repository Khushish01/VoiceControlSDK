import Foundation

// MARK: - Main Configuration

/// Top-level configuration for VoiceControlEngine. Host app creates this with all
/// commands, languages, vocabulary, and wake word settings.
public struct VoiceControlConfiguration {

    /// All supported languages with their vocabulary and number words.
    public let languages: [LanguageConfig]

    /// Wake word detection settings.
    public let wakeWord: WakeWordConfig

    /// All command definitions the engine should recognize.
    public let commands: [CommandDefinition]

    /// Seconds of silence before active listening stops (default 2.5).
    public let silenceTimeout: TimeInterval

    /// Seconds of inactivity before returning to passive mode (default 10).
    public let autoSleepTimeout: TimeInterval

    /// TTS speech rate (default 0.50).
    public let speechRate: Float

    /// TTS pitch multiplier (default 1.05).
    public let speechPitch: Float

    /// Maximum filler words allowed between keywords in patterns (default 3).
    public let maxFillerWords: Int

    /// Optional TTS voice identifier per language. Key = locale (e.g. "en-US"), Value = voice identifier
    /// (e.g. "com.apple.voice.compact.en-US.Reed"). If nil, uses system default voice.
    public let voiceIdentifiers: [String: String]

    public init(
        languages: [LanguageConfig],
        wakeWord: WakeWordConfig,
        commands: [CommandDefinition],
        silenceTimeout: TimeInterval = 2.5,
        autoSleepTimeout: TimeInterval = 10.0,
        speechRate: Float = 0.50,
        speechPitch: Float = 1.05,
        maxFillerWords: Int = 3,
        voiceIdentifiers: [String: String] = [:]
    ) {
        self.languages = languages
        self.wakeWord = wakeWord
        self.commands = commands
        self.silenceTimeout = silenceTimeout
        self.autoSleepTimeout = autoSleepTimeout
        self.speechRate = speechRate
        self.speechPitch = speechPitch
        self.maxFillerWords = maxFillerWords
        self.voiceIdentifiers = voiceIdentifiers
    }
}

// MARK: - Language Configuration

/// Per-language settings including vocabulary for fuzzy matching and number words.
public struct LanguageConfig {

    /// Locale identifier (e.g., "en-US", "de-DE", "fr-FR").
    public let localeIdentifier: String

    /// Display name for UI (e.g., "English", "Deutsch").
    public let displayName: String

    /// Vocabulary for Levenshtein fuzzy matching. Key = correct word, Value = max allowed edit distance.
    /// Short words should have low tolerance (0-1), longer words can have higher (2-3).
    public let vocabulary: [String: Int]

    /// Phonetic aliases for words that are too far for Levenshtein but are known misrecognitions.
    /// Only used during wake word detection. Key = misrecognition, Value = correct word.
    public let phoneticAliases: [String: String]

    /// Word-to-number mappings for this language (e.g., "seven" → 7, "sieben" → 7).
    public let numberWords: [(String, Int)]

    public init(
        localeIdentifier: String,
        displayName: String,
        vocabulary: [String: Int],
        phoneticAliases: [String: String] = [:],
        numberWords: [(String, Int)] = []
    ) {
        self.localeIdentifier = localeIdentifier
        self.displayName = displayName
        self.vocabulary = vocabulary
        self.phoneticAliases = phoneticAliases
        self.numberWords = numberWords
    }
}

// MARK: - Wake Word Configuration

/// Settings for wake word detection in passive listening mode.
public struct WakeWordConfig {

    /// The brand/trigger words to detect (e.g., ["skandika"]).
    /// Fuzzy matched using vocabulary + phonetic aliases.
    public let triggerWords: [String]

    /// Greeting prefixes per language that must appear before the trigger word.
    /// Key = locale identifier, Value = prefix words.
    /// e.g., ["en-US": ["hi", "hey", "hello"], "de-DE": ["hallo", "hi", "hey"]]
    public let prefixes: [String: [String]]

    /// Wake actions for different wake phrases. If empty, a single "default" action is used.
    public let actions: [WakeAction]

    public init(
        triggerWords: [String],
        prefixes: [String: [String]],
        actions: [WakeAction] = []
    ) {
        self.triggerWords = triggerWords
        self.prefixes = prefixes
        self.actions = actions
    }
}

/// A specific wake action triggered by a particular wake phrase pattern.
public struct WakeAction {

    /// Unique identifier for this wake action (e.g., "default", "connectDevice").
    public let identifier: String

    /// Optional suffix words after the trigger word that identify this action.
    /// If empty, this is the default wake action.
    public let suffixes: [String]

    public init(identifier: String, suffixes: [String] = []) {
        self.identifier = identifier
        self.suffixes = suffixes
    }
}

// MARK: - Command Definition

/// Defines a single voice command the engine should recognize.
public struct CommandDefinition {

    /// Unique identifier (e.g., "startWorkout", "resistanceUp").
    public let identifier: String

    /// Whether this is an emergency command that bypasses the queue.
    public let isEmergency: Bool

    /// Regex patterns per language. Key = locale identifier, Value = array of patterns.
    /// Patterns should use `\(gap)` placeholder where filler words are allowed.
    /// The SDK replaces `\(gap)` with the actual filler word regex at runtime.
    public let patterns: [String: [CommandPattern]]

    public init(
        identifier: String,
        isEmergency: Bool = false,
        patterns: [String: [CommandPattern]]
    ) {
        self.identifier = identifier
        self.isEmergency = isEmergency
        self.patterns = patterns
    }
}

/// A single regex pattern for a command, with optional parameter extraction.
public struct CommandPattern {

    /// Regex pattern string. Use `{gap}` where 0-N filler words are allowed.
    public let regex: String

    /// Optional closure to extract parameters from the matched text.
    /// Return nil if no parameters needed or extraction fails.
    public let parameterExtractor: (@Sendable (String) -> [String: Any]?)?

    /// Optional context guard. If provided, the pattern only matches when this returns true.
    /// Use for context-dependent commands (e.g., "stop" means different things based on workout state).
    public let contextGuard: (@Sendable (VoiceControlContext) -> Bool)?

    public init(
        regex: String,
        parameterExtractor: (@Sendable (String) -> [String: Any]?)? = nil,
        contextGuard: (@Sendable (VoiceControlContext) -> Bool)? = nil
    ) {
        self.regex = regex
        self.parameterExtractor = parameterExtractor
        self.contextGuard = contextGuard
    }
}

/// Context provided to command pattern guards for context-dependent matching.
public final class VoiceControlContext {

    private var values: [String: Any] = [:]

    /// Set a context value (called by host app).
    public func setValue(_ value: Any, forKey key: String) {
        values[key] = value
    }

    /// Get a context value (used by pattern guards).
    public func value(forKey key: String) -> Any? {
        values[key]
    }

    /// Convenience for Bool context values.
    public func boolValue(forKey key: String) -> Bool {
        values[key] as? Bool ?? false
    }
}
