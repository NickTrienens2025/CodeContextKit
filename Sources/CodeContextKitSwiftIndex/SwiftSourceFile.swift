import Foundation
import SwiftSyntax
import SwiftParser
import CodeContextKitCore

public struct SwiftSourceFile: CodeSplitter {
    public let filePath: String
    public let content: String
    
    public init(filePath: String = "", content: String = "") {
        self.filePath = filePath
        self.content = content
    }
    
    public func extractSymbols(content: String, filePath: String) -> ([SymbolRecord], [SymbolRecord.Reference]) {
        let sourceFile = Parser.parse(source: content)
        let locationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        let visitor = SwiftSymbolVisitor(filePath: filePath, locationConverter: locationConverter, content: content)
        visitor.walk(sourceFile)
        return (visitor.symbols, visitor.references)
    }
    
    // Kept for backward compatibility and internal use
    public func extractSymbols() -> ([SymbolRecord], [SymbolRecord.Reference]) {
        return extractSymbols(content: content, filePath: filePath)
    }
    
    public func body(for symbol: SymbolRecord) -> String {
        let lines = content.components(separatedBy: .newlines)
        let start = max(0, symbol.startLine - 1)
        let end = min(lines.count, symbol.endLine)
        
        guard start < lines.count, start < end else {
            return ""
        }
        
        return lines[start..<end].joined(separator: "\n")
    }
}
