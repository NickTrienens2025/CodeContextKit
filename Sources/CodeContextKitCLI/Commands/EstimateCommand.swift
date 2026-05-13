import ArgumentParser
import Foundation
import CodeContextKitCore
import CodeContextKitRetrieval

struct EstimateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "estimate",
        abstract: "Estimates token count for a file or text."
    )

    @Argument(help: "The file path or text to estimate.")
    var input: String

    @Option(help: "The model to use for pricing/estimation.")
    var model: String?

    @Flag(help: "Interpret input as raw text instead of a file path.")
    var text: Bool = false

    func run() async throws {
        let estimator = TokenEstimator()
        let content: String
        
        if text {
            content = input
        } else {
            let url = URL(fileURLWithPath: input)
            content = try String(contentsOf: url, encoding: .utf8)
        }
        
        let tokens = estimator.estimate(content)
        print("Estimated tokens: \(tokens)")
        
        if let model = model {
            print("Model-specific estimation for '\(model)' is not yet implemented.")
        }
    }
}
