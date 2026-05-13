import Foundation

public protocol CodeSplitter: Sendable {
    func extractSymbols(content: String, filePath: String) -> ([SymbolRecord], [SymbolRecord.Reference])
}
