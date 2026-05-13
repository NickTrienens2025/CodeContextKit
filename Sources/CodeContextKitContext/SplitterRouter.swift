import Foundation
import CodeContextKitCore
import CodeContextKitSwiftIndex

/// Directs source files to the appropriate `CodeSplitter` based on file extension.
///
/// Supported languages include:
/// - **Swift**: Uses `SwiftSourceFile` for advanced structural splitting and body extraction.
/// - **JavaScript/TypeScript**: Uses `RegexSplitter` to identify functions, classes, and properties.
/// - **CSS/SCSS/Less**: Uses `RegexSplitter` to identify style selectors.
/// - **Python, Java, Kotlin**: Supported via standard regex patterns.
/// - **Generic**: Fallback support for other text files.
public struct SplitterRouter {
    public init() {}
    
    public func splitter(for filePath: String) -> CodeSplitter {
        let ext = (filePath as NSString).pathExtension.lowercased()
        
        switch ext {
        case "swift":
            return SwiftSourceFile()
        case "js", "ts", "jsx", "tsx":
            return RegexSplitter(language: "js")
        case "css", "scss", "less":
            return RegexSplitter(language: "css")
        case "py":
            return RegexSplitter(language: "python")
        case "java":
            return RegexSplitter(language: "java")
        case "kt", "kts":
            return RegexSplitter(language: "kotlin")
        default:
            return RegexSplitter(language: "generic")
        }
    }
}
