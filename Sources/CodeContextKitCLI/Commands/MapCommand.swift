import ArgumentParser
import Foundation
import CodeContextKitStorage
import CodeContextKitContext
import CodeContextKitRetrieval

struct MapCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "map",
        abstract: "Builds a repo map under a token budget."
    )

    @Option(help: "The token budget for the map.")
    var budget: Int = 4096

    @Option(help: "Focus terms for the map.")
    var focus: String?

    @Flag(help: "Include changed files.")
    var changed: Bool = false

    @Option(help: "The base branch for changed files.")
    var base: String = "main"

    func run() async throws {
        let startTime = Date()
        let dbPath = ".cckit/index.sqlite"
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("Error: Index not found. Run 'cckit index' first.")
            return
        }
        
        let db = try Database(path: dbPath)
        let wax = try await WaxStore(path: ".cckit/repo.wax")
        let actionOrchestrator = ActionOrchestrator(db: db, wax: wax)
        
        let builder = RepoMapBuilder(db: db, counter: { text in await wax.countTokens(text) })
        let map = try await builder.buildMap(budget: budget, focusTerms: focus)
        
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        let tokens = await wax.countTokens(map)
        try await actionOrchestrator.recordCLIAction(command: "map --budget \(budget)", toolName: "Map Builder", durationMs: duration, tokensUsed: tokens)
        
        print(map)
    }
}
