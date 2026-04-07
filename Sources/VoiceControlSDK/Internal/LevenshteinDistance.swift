import Foundation

enum LevenshteinDistance {

    /// Computes the minimum number of single-character edits (insertions, deletions, substitutions)
    /// required to change `source` into `target`.
    static func distance(_ source: String, _ target: String) -> Int {
        let s = Array(source)
        let t = Array(target)
        let sLen = s.count
        let tLen = t.count

        if sLen == 0 { return tLen }
        if tLen == 0 { return sLen }

        var prev = Array(0...tLen)
        var curr = [Int](repeating: 0, count: tLen + 1)

        for i in 1...sLen {
            curr[0] = i
            for j in 1...tLen {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[tLen]
    }
}
