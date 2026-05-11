import ArgumentParser
import Foundation

struct ExplainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explain",
        abstract: "Explains stored index or context state."
    )

    @Argument(help: "The topic to explain (index, pack, symbol).")
    var topic: String

    @Argument(help: "Additional context for the explanation.")
    var context: String?

    func run() async throws {
        switch topic {
        case "index":
            print("The index is stored in .cckit/index.sqlite (metadata) and .cckit/repo.wax (semantic search).")
        case "pack":
            print("Context packing combines repo map, failure summaries, and semantic search results.")
        case "symbol":
            print("Symbols are extracted using SwiftSyntax and include types, functions, and properties.")
        default:
            print("No explanation available for '\(topic)'.")
        }
    }
}
