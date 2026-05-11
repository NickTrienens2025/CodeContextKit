import ArgumentParser
import Foundation
import CodeContextKitCore
import CodeContextKitSwiftIndex
import CodeContextKitStorage
import CodeContextKitRetrieval
import CodeContextKitContext

struct IndexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Indexes a repository."
    )

    @Argument(help: "The directory to index.")
    var path: String = "."

    @Flag(help: "Clean the index before indexing.")
    var clean: Bool = false

    @Option(help: "Glob patterns to include.")
    var include: [String] = []

    @Option(help: "Glob patterns to exclude.")
    var exclude: [String] = []

    @Flag(help: "Print index statistics.")
    var stats: Bool = false

    func run() async throws {
        let dbPath = ".cckit/index.sqlite"
        let waxPath = ".cckit/repo.wax"
        
        if clean {
            if FileManager.default.fileExists(atPath: dbPath) {
                try FileManager.default.removeItem(atPath: dbPath)
            }
            if FileManager.default.fileExists(atPath: waxPath) {
                try FileManager.default.removeItem(atPath: waxPath)
            }
        }
        
        let db = try Database(path: dbPath)
        let wax = try await WaxStore(path: waxPath)
        let indexer = Indexer(db: db, wax: wax)
        
        print("Indexing \(path)...")
        try await indexer.index(at: path, include: include, exclude: exclude, delegate: CommandLineProgressDelegate())
        
        try await wax.close()
    }
}

struct CommandLineProgressDelegate: IndexerProgressDelegate {
    func indexerDidStart(totalFiles: Int) {
        print("Starting indexing of \(totalFiles) files...")
    }
    
    func indexerDidProgress(completedFiles: Int, totalFiles: Int, currentFile: String) {
        let percent = totalFiles > 0 ? (completedFiles * 100 / totalFiles) : 0
        print("[\(percent)%] \(currentFile)")
    }
    
    func indexerDidFinish(updated: Int, skipped: Int, totalSymbols: Int) {
        print("Indexing complete. Updated: \(updated), Skipped: \(skipped), Symbols: \(totalSymbols)")
    }
    
    func indexerDidFail(error: Error) {
        print("Indexing failed: \(error.localizedDescription)")
    }
}
