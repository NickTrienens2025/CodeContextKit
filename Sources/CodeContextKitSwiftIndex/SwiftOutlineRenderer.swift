import Foundation
import CodeContextKitCore

public struct SwiftOutlineRenderer {
    public init() {}
    
    public func render(filePath: String, symbols: [SymbolRecord]) -> String {
        let fileName = (filePath as NSString).lastPathComponent
        var output = "### \(fileName)\n\n"
        
        let sortedSymbols = symbols.sorted { $0.startLine < $1.startLine }
        
        for symbol in sortedSymbols {
            let components = symbol.qualifiedName.split(separator: ".")
            let indentationCount = max(0, components.count - 1)
            let indentation = String(repeating: "  ", count: indentationCount)
            
            if let doc = symbol.docComment, !doc.isEmpty {
                let docLines = doc.components(separatedBy: .newlines)
                for line in docLines {
                    output += "\(indentation)/// \(line)\n"
                }
            }
            
            output += "\(indentation)\(symbol.signature) [L\(symbol.startLine)-L\(symbol.endLine)]\n"
        }
        
        return output
    }
}
