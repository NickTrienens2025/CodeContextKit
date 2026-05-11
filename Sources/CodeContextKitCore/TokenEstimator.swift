import Foundation

public struct TokenEstimator {
    public init() {}
    
    public func estimate(_ text: String) -> Int {
        // Simple approximation: ~4 chars per token
        max(1, Int(Double(text.utf8.count) / 3.8))
    }
}
