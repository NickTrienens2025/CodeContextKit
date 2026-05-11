import ArgumentParser
import Foundation
import CodeContextKitStorage
import CodeContextKitContext

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
        let dbPath = ".cckit/index.sqlite"
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("Error: Index not found. Run 'cckit index' first.")
            return
        }
        
        let db = try Database(path: dbPath)
        let builder = RepoMapBuilder(db: db)
        let map = try builder.buildMap(budget: budget, focusTerms: focus)
        
        print(map)
    }
}
