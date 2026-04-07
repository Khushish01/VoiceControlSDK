import Foundation

/// Config-driven command interpreter. Uses Levenshtein fuzzy matching + regex patterns
/// provided via VoiceControlConfiguration.
final class CommandInterpreterEngine {

    private let configuration: VoiceControlConfiguration
    private let gapPattern: String

    init(configuration: VoiceControlConfiguration) {
        self.configuration = configuration
        // Build gap pattern: allows 0 to N filler words between keywords
        let n = configuration.maxFillerWords
        self.gapPattern = "(\\s+\\w+){0,\(n)}\\s+"
    }

    // MARK: - Public

    /// Checks if the transcript contains a wake word for the given locale.
    /// Uses phonetic aliases during normalization.
    func isWakeWord(_ transcript: String, locale: String) -> (detected: Bool, actionId: String?) {
        guard let langConfig = languageConfig(for: locale) else { return (false, nil) }

        let raw = transcript.lowercased()
        let text = normalizeTranscript(raw, langConfig: langConfig, usePhoneticAliases: true)
        let words = text.components(separatedBy: .whitespacesAndNewlines)

        let prefixes = configuration.wakeWord.prefixes[locale] ?? []
        guard words.contains(where: { prefixes.contains($0) }) else { return (false, nil) }

        let triggerFound = configuration.wakeWord.triggerWords.contains(where: { trigger in
            words.contains(where: { $0 == trigger })
        })
        guard triggerFound else { return (false, nil) }

        // Check for specific wake actions
        for action in configuration.wakeWord.actions {
            if action.suffixes.isEmpty { continue }
            let matched = action.suffixes.contains(where: { suffix in
                text.contains(suffix.lowercased())
            })
            if matched { return (true, action.identifier) }
        }

        // Default wake action
        let defaultAction = configuration.wakeWord.actions.first(where: { $0.suffixes.isEmpty })
        return (true, defaultAction?.identifier)
    }

    /// Interprets a transcript into a VoiceCommandResult, or nil if no command matched.
    func interpret(_ transcript: String, locale: String, context: VoiceControlContext) -> VoiceCommandResult? {
        guard let langConfig = languageConfig(for: locale) else { return nil }

        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }

        let text = normalizeTranscript(raw, langConfig: langConfig, usePhoneticAliases: false)
        let numberExtractor = NumberExtractor(numberWords: langConfig.numberWords)

        for command in configuration.commands {
            guard let patterns = command.patterns[locale] else { continue }
            for pattern in patterns {
                // Check context guard
                if let guard_ = pattern.contextGuard, !guard_(context) { continue }

                // Replace {gap} placeholder with actual filler regex
                let regexStr = pattern.regex.replacingOccurrences(of: "{gap}", with: gapPattern)

                guard let regex = try? NSRegularExpression(pattern: regexStr, options: .caseInsensitive),
                      regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
                else { continue }

                // Extract parameters
                var params: [String: Any] = [:]
                if let extractor = pattern.parameterExtractor {
                    if let extracted = extractor(text) {
                        params = extracted
                    }
                } else {
                    // Auto-extract number if present (convenience)
                    if let num = numberExtractor.extract(from: text) {
                        params["number"] = num
                    }
                }

                return VoiceCommandResult(
                    identifier: command.identifier,
                    rawTranscript: transcript,
                    normalizedTranscript: text,
                    parameters: params,
                    isEmergency: command.isEmergency
                )
            }
        }
        return nil
    }

    // MARK: - Normalization

    private func normalizeTranscript(_ text: String, langConfig: LanguageConfig, usePhoneticAliases: Bool) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        let corrected = words.map { word -> String in
            // Phonetic aliases only for wake word detection
            if usePhoneticAliases, let alias = langConfig.phoneticAliases[word] {
                return alias
            }

            // Exact vocabulary match
            if langConfig.vocabulary[word] != nil { return word }

            // Levenshtein fuzzy match against vocabulary
            var bestMatch: String?
            var bestDistance = Int.max
            for (vocabWord, maxDist) in langConfig.vocabulary {
                let dist = LevenshteinDistance.distance(word, vocabWord)
                if dist <= maxDist && dist < bestDistance {
                    bestDistance = dist
                    bestMatch = vocabWord
                }
            }
            return bestMatch ?? word
        }
        return corrected.joined(separator: " ")
    }

    // MARK: - Helpers

    private func languageConfig(for locale: String) -> LanguageConfig? {
        configuration.languages.first(where: { $0.localeIdentifier == locale })
    }
}
