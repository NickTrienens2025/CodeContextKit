import Foundation

public final class TokenEstimator: Sendable {
    public static let shared = TokenEstimator()
    
    private let accurateCounter: (@Sendable (String) -> Int)?
    
    public init(accurateCounter: (@Sendable (String) -> Int)? = nil) {
        self.accurateCounter = accurateCounter
    }
    
    public func estimate(_ text: String) -> Int {
        if let accurateCounter = accurateCounter {
            return accurateCounter(text)
        }
        
        // Claude (and GPT-4) use BPE tokenizers (like cl100k_base).
        // A better heuristic than simple character division:
        // 1. Split by words, punctuation, and whitespace
        // 2. Average token length is ~3.5-4 chars for text, ~2.5-3 for code.
        
        if text.isEmpty { return 0 }
        
        // This regex attempts to find "token-like" chunks:
        // - Words and numbers
        // - Punctuation marks (each usually a token)
        // - Multiple spaces (often collapsed into tokens)
        // - Newlines
        let pattern = #"[a-zA-Z0-9]+|[\p{P}\p{S}]|\n|\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return max(1, Int(Double(text.utf8.count) / 3.7))
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.numberOfMatches(in: text, options: [], range: range)
        
        // Adjust for long words/blocks that might be split into multiple tokens
        // Heuristic: +1 token for every 4 chars in long continuous alphanumeric strings
        var adjustment = 0
        let longWordRegex = try? NSRegularExpression(pattern: #"[a-zA-Z0-9]{8,}"#)
        longWordRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                adjustment += (matchRange.length / 4)
            }
        }
        
        return max(1, matches + adjustment)
    }
}
