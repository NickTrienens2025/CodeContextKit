import Foundation
import CodeContextKitCore
import CodeContextKitStorage
import CodeContextKitRetrieval
import CodeContextKitSwiftIndex

public final class ContextPacker {
    private let db: Database
    private let wax: WaxStore
    private let rootPath: String
    private let estimator = TokenEstimator()
    private let repoMapBuilder: RepoMapBuilder
    
    public init(db: Database, wax: WaxStore, rootPath: String = ".") {
        self.db = db
        self.wax = wax
        self.rootPath = rootPath
        self.repoMapBuilder = RepoMapBuilder(db: db)
    }
    
    public func pack(task: String, budget: Int, failureLog: String? = nil) async throws -> String {
        var output = "# Context Packet\n\n"
        output += "SYSTEM: cckit can find any file or symbol by short name. Full paths below are for reference only.\n\n"
        output += "## Task\n\(task)\n\n"
        
        // 1. Repo Map (Budget 15%)
        let mapBudget = budget / 7
        let repoMap = try repoMapBuilder.buildMap(budget: mapBudget, focusTerms: task)
        output += "## Repository Map\n\(repoMap)\n\n"
        
        // 2. Failure Summary
        if let failureLog = failureLog {
            let summary = extractFailureSummary(from: failureLog)
            output += "## Failure Summary\n\(summary)\n\n"
        }
        
        // 3. Intelligent Expansion (Dependency Crawl)
        let searchResults = try await wax.search(task, limit: 10)
        var stagedFiles: Set<String> = []
        var associatedFiles: [String: String] = [:] // Path -> Reason
        
        for res in searchResults {
            if let sym = try db.getSymbols(qualifiedName: res.symbol).first {
                stagedFiles.insert(sym.filePath)
                
                // Dependency Crawl for this symbol's file
                let refs = try db.getReferencesInFile(path: sym.filePath)
                for ref in refs {
                    let defs = try db.getSymbols(qualifiedName: ref.name)
                    for def in defs {
                        if def.filePath != sym.filePath {
                            associatedFiles[def.filePath] = "Defines '\(def.name)' used in '\(sym.filePath.split(separator: "/").last!)'"
                        }
                    }
                }
            }
        }
        
        // 4. Surgical Assembly
        output += "## Surgical Context\n\n"
        
        let rootURL = URL(fileURLWithPath: rootPath)
        
        // Full Bodies for Staged Files
        for path in stagedFiles {
            let fullURL = rootURL.appendingPathComponent(path)
            if let content = try? String(contentsOf: fullURL, encoding: .utf8) {
                let fileName = path.split(separator: "/").last!
                output += "### \(fileName) (FULL)\n```swift\n\(content)\n```\n\n"
            }
        }
        
        // Skeletons for Associated Files
        for (path, reason) in associatedFiles where !stagedFiles.contains(path) {
            let symbols = try db.getSymbols(path: path)
            let skeleton = SwiftOutlineRenderer().render(filePath: path, symbols: symbols)
            let fileName = path.split(separator: "/").last!
            output += "### \(fileName) (SKELETON - \(reason))\n\(skeleton)\n\n"
        }
        
        let totalTokens = estimator.estimate(output)
        output += "## Stats\nEstimated total tokens: \(totalTokens)\nBudget: \(budget)\n"
        
        return output
    }
    
    private func extractFailureSummary(from logPath: String) -> String {
        // Deterministic failure extraction logic
        // For v1, just return the last few lines or look for "error:"
        do {
            let content = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            let errorLines = lines.filter { $0.lowercased().contains("error:") || $0.lowercased().contains("failed") }
            if errorLines.isEmpty {
                return "No explicit errors found in log."
            }
            return errorLines.prefix(10).joined(separator: "\n")
        } catch {
            return "Could not read failure log: \(error.localizedDescription)"
        }
    }
}
