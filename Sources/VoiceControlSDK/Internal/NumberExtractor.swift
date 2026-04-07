import Foundation

struct NumberExtractor {

    private let numberWords: [(String, Int)]

    init(numberWords: [(String, Int)]) {
        self.numberWords = numberWords
    }

    /// Extracts the first number found in the text, trying digits first then word numbers.
    func extract(from text: String) -> Int? {
        // Try digits first
        if let regex = try? NSRegularExpression(pattern: "\\d+"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text),
           let num = Int(text[range]) {
            return num
        }
        // Try word numbers (check longer words first to avoid partial matches)
        let lowered = text.lowercased()
        for (word, value) in numberWords {
            if lowered.contains(word) { return value }
        }
        return nil
    }
}
