import ArgumentParser
import CodeContextKitCore
import CodeContextKitSwiftIndex
import CodeContextKitStorage
import CodeContextKitRetrieval
import CodeContextKitContext

@main
struct CCKit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cckit",
        abstract: "A Swift-first context-packing tool for repository understanding.",
        version: "0.1.0",
        subcommands: [
            IndexCommand.self,
            OutlineCommand.self,
            SymbolCommand.self,
            SearchCommand.self,
            MapCommand.self,
            PackCommand.self,
            EstimateCommand.self,
            ExplainCommand.self,
            SummarizeCommand.self,
            ServeCommand.self
        ],
        defaultSubcommand: IndexCommand.self
    )
}
