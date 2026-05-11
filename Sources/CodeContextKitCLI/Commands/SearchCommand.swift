import ArgumentParser
import Foundation
import CodeContextKitRetrieval
import CodeContextKitStorage
import CodeContextKitCore
import CodeContextKitSwiftIndex

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Unified search tool for symbols, literal text (grep), and semantic meaning."
    )

    @Argument(help: "The search query. Prefix with 'semantic:' for meaning search.")
    var query: String

    @Flag(name: .shortAndLong, help: "Treat the query as a regular expression.")
    var regex: Bool = false

    @Flag(help: "Output in JSON format.")
    var json: Bool = false

    @Option(help: "Limit the number of results.")
    var limit: Int = 10

    func run() async throws {
        let dbPath = ".cckit/index.sqlite"
        let waxPath = ".cckit/repo.wax"
        
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("Error: Index not found. Run 'cckit index' first.")
            return
        }
        
        let db = try Database(path: dbPath)
        let wax = try await WaxStore(path: waxPath)
        
        if json {
            // JSON output is useful for sub-agents
            let results = try await performUnifiedSearch(db: db, wax: wax)
            let data = try JSONSerialization.data(withJSONObject: results, options: .prettyPrinted)
            if let string = String(data: data, encoding: .utf8) { print(string) }
        } else {
            try await runInteractiveSearch(db: db, wax: wax)
        }
    }

    private func performUnifiedSearch(db: Database, wax: WaxStore) async throws -> [String: Any] {
        var results: [String: Any] = [:]
        
        if query.hasPrefix("semantic:") {
            let semanticQuery = String(query.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            let waxResults = try await wax.search(semanticQuery, limit: limit)
            results["semanticMatches"] = waxResults.map { ["symbol": $0.symbol, "score": $0.score, "file": $0.file] }
        } else {
            // 1. File Matches
            let files = try db.getFilesLike(pattern: query)
            results["files"] = files.prefix(limit).map { ["path": $0.path, "language": $0.language] }

            // 2. Symbol Matches
            let symbols = try db.getSymbolsLike(name: query)
            results["symbols"] = symbols.prefix(limit).map { ["name": $0.qualifiedName, "kind": "\($0.kind)", "file": $0.filePath] }
            
            // 3. Text Matches (Grep logic)
            let textResults = try await performGrepSearch(db: db)
            results["textMatches"] = textResults
        }
        
        return results
    }

    private func runInteractiveSearch(db: Database, wax: WaxStore) async throws {
        if query.hasPrefix("semantic:") {
            print("🧠 Performing Semantic Search...")
            let semanticQuery = String(query.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            let waxResults = try await wax.search(semanticQuery, limit: limit)
            
            for res in waxResults {
                if let sym = try db.getSymbols(qualifiedName: res.symbol).first {
                    print("\n--- \(sym.qualifiedName) (\(sym.kind)) ---")
                    print("File: \(sym.filePath)")
                    print("Match: \(res.preview)")
                }
            }
        } else {
            // File Search
            let files = try db.getFilesLike(pattern: query)
            if !files.isEmpty {
                print("📄 Found \(min(files.count, limit)) file matches:")
                for file in files.prefix(limit) {
                    print("  - \(file.path) (\(file.language))")
                }
            }

            // Symbol Search
            let symbols = try db.getSymbolsLike(name: query)
            if !symbols.isEmpty {
                print("\n🔶 Found \(min(symbols.count, limit)) symbol matches:")
                for symbol in symbols.prefix(limit) {
                    print("  - \(symbol.qualifiedName) (\(symbol.kind)) in \(symbol.filePath)")
                }
            }

            // Grep Search
            print("\n🔍 Found text matches:")
            let textResults = try await performGrepSearch(db: db)
            for match in textResults {
                print("\n--- \(match["file"]!) ---")
                if let snippet = match["snippet"] as? String {
                    print(snippet)
                }
            }
        }
    }

    private func performGrepSearch(db: Database) async throws -> [[String: Any]] {
        let pattern = regex ? query : NSRegularExpression.escapedPattern(for: query)
        guard let regexObj = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        
        let files = try db.getAllFiles()
        var matches: [[String: Any]] = []
        
        for file in files {
            guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            
            for (index, line) in lines.enumerated() {
                let range = NSRange(location: 0, length: line.utf16.count)
                if regexObj.firstMatch(in: line, options: [], range: range) != nil {
                    // Snippet with 1 line context
                    let start = max(0, index - 1)
                    let end = min(lines.count - 1, index + 1)
                    var snippet = ""
                    for i in start...end {
                        let prefix = (i == index) ? "> " : "  "
                        snippet += "\(prefix)L\(i+1): \(lines[i].trimmingCharacters(in: .whitespaces))\n"
                    }
                    
                    matches.append([
                        "file": file.path,
                        "line": index + 1,
                        "content": line.trimmingCharacters(in: .whitespaces),
                        "snippet": snippet
                    ])
                    break // One match per file for the summary view
                }
            }
            if matches.count >= limit { break }
        }
        return matches
    }
}
