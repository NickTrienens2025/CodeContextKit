import Foundation
import CodeContextKitCore
import CodeContextKitStorage
import CodeContextKitSwiftIndex

/// Constructs a high-level architectural overview of the repository within a token budget.
///
/// `RepoMapBuilder` focuses on providing "just enough" information for an AI model or developer to understand 
/// the overall structure, modules, and key symbols of a project without overwhelming the context window.
public final class RepoMapBuilder {
    private let db: Database
    private let counter: @Sendable (String) async -> Int
    private let renderer = SwiftOutlineRenderer()
    
    public init(db: Database, counter: @escaping @Sendable (String) async -> Int) {
        self.db = db
        self.counter = counter
    }
    
    public func buildMap(budget: Int, focusTerms: String? = nil) async throws -> String {
        let terms = focusTerms?.lowercased().split(separator: " ").map(String.init) ?? []
        
        let allFiles = try db.getAllFiles()
        var scoredFiles: [(file: FileRecord, symbols: [SymbolRecord], score: Int)] = []
        
        for file in allFiles {
            let symbols = try db.getSymbols(fileId: file.id!)
            var score = 0
            
            // Priority 1: Direct focus match (Filename or Symbol name)
            let pathLower = file.path.lowercased()
            if terms.contains(where: { pathLower.contains($0) }) { score += 100 }
            
            let symbolMatches = symbols.filter { sym in
                terms.contains { term in
                    sym.name.lowercased().contains(term) || (sym.docComment?.lowercased().contains(term) ?? false)
                }
            }
            score += symbolMatches.count * 50
            
            // Priority 2: Architectural importance (Types vs Helpers)
            let typeCount = symbols.filter { [.class, .struct, .enum, .protocol, .actor].contains($0.kind) }.count
            score += typeCount * 10
            
            // Priority 3: Public API surface
            let publicCount = symbols.filter { $0.accessLevel == "public" || $0.accessLevel == "open" }.count
            score += publicCount * 2
            
            scoredFiles.append((file, symbols, score))
        }
        
        // Sort by score (descending), then path
        scoredFiles.sort { 
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.file.path < $1.file.path
        }
        
        // Surgical strategy:
        // Try Level 2 for high score, Level 1 for medium, Level 0 for low.
        // Omit if 0 score AND focus is provided.
        
        var currentMap = ""
        var attempts = 3
        var levelThresholds = [75, 25, 0] // Level 2 score min, Level 1 score min, Level 0 score min
        
        while attempts > 0 {
            currentMap = ""
            var currentTokens = 0
            
            for item in scoredFiles {
                if !terms.isEmpty && item.score == 0 { continue } // Skip noise if focusing
                
                var level = 0
                if item.score >= levelThresholds[0] { level = 2 }
                else if item.score >= levelThresholds[1] { level = 1 }
                else if item.score >= levelThresholds[2] { level = 0 }
                else { continue } 
                
                // ELEVATION: If any symbol matches focus exactly, force at least Level 1 for this file
                if !terms.isEmpty && item.score > 0 && level < 1 { level = 1 }
                
                let outline = renderAtLevel(level, filePath: item.file.path, symbols: item.symbols, focusTerms: terms)
                let tokens = await counter(outline + "\n---\n")
                
                if currentTokens + tokens < budget {
                    currentMap += outline + "\n---\n"
                    currentTokens += tokens
                } else {
                    // Out of budget, try one lower level before giving up on this file
                    if level > 0 {
                        let lowerOutline = renderAtLevel(level - 1, filePath: item.file.path, symbols: item.symbols, focusTerms: terms)
                        let lowerTokens = await counter(lowerOutline + "\n---\n")
                        if currentTokens + lowerTokens < budget {
                            currentMap += lowerOutline + "\n---\n"
                            currentTokens += lowerTokens
                        }
                    }
                }
            }
            
            if currentTokens <= budget { break }
            
            // Tighten thresholds for next attempt
            levelThresholds = levelThresholds.map { $0 * 2 }
            attempts -= 1
        }
        
        var header = "# Repository Map (Tokens: \(await counter(currentMap))/\(budget))\n\n"
        header += "SYSTEM: CCKit mapping engine identifies high-level structure. Use short names (e.g., 'APIClient') for term-based search. Full paths are hidden to save tokens.\n\n"
        
        return header + currentMap
    }
    
    private func renderAtLevel(_ level: Int, filePath: String, symbols: [SymbolRecord], focusTerms: [String] = []) -> String {
        let fileName = (filePath as NSString).lastPathComponent
        let fileBase = (fileName as NSString).deletingPathExtension
        
        if level == 0 { return "### \(fileName) (\(symbols.count) symbols)" }
        
        let sortedSymbols = symbols.sorted { $0.startLine < $1.startLine }
        var renderedContent = ""
        var renderedCount = 0
        var lastSignature = ""
        
        for symbol in sortedSymbols {
            let matchesFocus = focusTerms.contains { term in
                symbol.name.lowercased().contains(term) || (symbol.docComment?.lowercased().contains(term) ?? false)
            }

            // Level 2: Skeleton with docs
            // Level 1: Skeleton only
            // CRITICAL: If symbol matches focus, ignore filtering and show it.
            if !matchesFocus {
                let importantKinds: Set<SymbolRecord.Kind> = [.class, .struct, .protocol, .actor, .enum, .interface, .case]
                let isLikelyPublic = symbol.accessLevel == "public" || symbol.accessLevel == "open" || symbol.accessLevel == nil
                
                // If we have focus terms, aggressively filter out non-important, non-matching symbols even in Level 2
                if !focusTerms.isEmpty {
                    if !importantKinds.contains(symbol.kind) && !isLikelyPublic {
                        continue
                    }
                    
                    // Additional filter: if it's public but NOT a type and NOT focused, skip it if we are focusing
                    if !importantKinds.contains(symbol.kind) && isLikelyPublic {
                        continue
                    }
                } else {
                    // Standard Level 1: Include types and public members
                    if level == 1 && !importantKinds.contains(symbol.kind) && !isLikelyPublic && !symbol.name.hasPrefix("test") {
                        continue
                    }
                }
            }

            renderedCount += 1
            let components = symbol.qualifiedName.split(separator: ".")
            let indentationCount = max(0, components.count - 1)
            let indentation = String(repeating: "  ", count: indentationCount)
            
            // ELEVATION: If symbol matches focus, always show doc comment if available
            if (level >= 2 || matchesFocus), let doc = symbol.docComment, !doc.isEmpty {
                let docLines = doc.components(separatedBy: .newlines)
                for line in docLines {
                    renderedContent += "\(indentation)/// \(line)\n"
                }
            }
            
            let lineInfo = " [L\(symbol.startLine)-L\(symbol.endLine)]"
            renderedContent += "\(indentation)\(symbol.signature)\(lineInfo)\n"
            lastSignature = "\(symbol.signature)\(lineInfo)"
            
            // If the symbol matches the filename base, we might be able to simplify
            if renderedCount == 1 && symbol.name.lowercased() == fileBase.lowercased() {
                 // Keep track of this potential optimization
            }
        }
        
        if renderedCount == 0 { return "" }
        
        // SINGLE STRUCT OPTIMIZATION
        if renderedCount == 1 {
            let firstSymbolName = sortedSymbols.first(where: { _ in true })?.name ?? ""
            if firstSymbolName.lowercased() == fileBase.lowercased() {
                return renderedContent.trimmingCharacters(in: .newlines)
            } else {
                return "\(fileName): \(renderedContent.trimmingCharacters(in: .newlines))"
            }
        }
        
        return "### \(fileName)\n\n\(renderedContent.trimmingCharacters(in: .newlines))"
    }
}
