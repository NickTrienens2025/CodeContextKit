import ArgumentParser
import Hummingbird
import HummingbirdRouter
import Foundation
import NIOCore
import NIOPosix
import Logging

struct BenchmarkServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark-serve",
        abstract: "Starts a small server to host the benchmark viewer and results."
    )
    
    @Option(name: .shortAndLong, help: "Port to run the server on.")
    var port: Int = 8081
    
    @Option(name: .shortAndLong, help: "Path to the directory to serve.")
    var dir: String = "Benchmarks"
    
    func run() async throws {
        let router = Router()
        
        // Serve static files from the Benchmarks directory
        router.addMiddleware { 
            FileMiddleware(dir, searchForIndexHtml: true) 
        }
        
        let logger = Logger(label: "BenchmarkServer")
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port)),
            logger: logger
        )
        
        print("🚀 Benchmark server starting on http://127.0.0.1:\(port)...")
        print("Serving files from: \(dir)")
        print("Open your browser and navigate to the link above to view your graphs.")
        
        try await app.runService()
    }
}
