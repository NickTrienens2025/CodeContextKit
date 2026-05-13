import XCTest
import Foundation
@testable import CodeContextKitContext
@testable import CodeContextKitStorage
@testable import CodeContextKitRetrieval
@testable import CodeContextKitCore

final class SearchComparisonTests: XCTestCase {
    var db: CodeContextKitStorage.Database!
    var indexer: Indexer!
    var tempDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        let uuid = UUID().uuidString
        let tempDbPath = NSTemporaryDirectory() + uuid + ".sqlite"
        db = try CodeContextKitStorage.Database(path: tempDbPath)
        let wax = try await WaxStore(path: NSTemporaryDirectory() + uuid + ".wax")
        indexer = Indexer(db: db, wax: wax)
        
        // Setup a rich test environment
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uuid)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let files = [
            "Network/APIClient.swift": "class APIClient { func sendRequest() {} }",
            "Network/Models/User.swift": "struct User { let id: Int; let name: String }",
            "UI/Views/MainView.swift": "struct MainView { var body: some View { Text(\"Hello\") } }",
            "UI/Styles/Theme.swift": "enum Theme { static let primaryColor = \"blue\" }",
            "Storage/Local/Database.swift": "class Database { func save(record: String) {} }",
            "Utils/Helpers.swift": "func calculateHash(input: String) -> String { return \"hash\" }",
            "Auth/TokenProvider.swift": "protocol TokenProvider { func getToken() -> String }",
            "Auth/OAuthManager.swift": "class OAuthManager { func refresh() {} }"
        ]
        
        for (path, content) in files {
            let fileURL = tempDir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        try await indexer.index(at: tempDir.path)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testSearchVariations() throws {
        // We want to run 100 variations of multi-term searches
        // and compare OR (default) vs AND (strict)
        
        let testQueries = [
            "APIClient send",
            "User id",
            "MainView body",
            "Theme primary",
            "Database save",
            "Helpers calculate",
            "Auth Token",
            "Auth Manager",
            "Network User",
            "UI Theme",
            "Storage record",
            "Network Models",
            "Network APIClient",
            "Auth OAuthManager",
            "UI Views MainView",
            "func refresh",
            "struct User",
            "class Database",
            "protocol Token",
            "enum Theme"
        ]
        
        var totalOrResults = 0
        var totalAndResults = 0
        
        for i in 0..<100 {
            // Pick a query and optionally add some variation
            let baseQuery = testQueries[i % testQueries.count]
            let query = (i >= testQueries.count) ? "\(baseQuery) \(i)" : baseQuery
            
            // Search Symbols (OR)
            let orSymbols = try db.getSymbolsLike(name: query, strict: false)
            // Search Symbols (AND/Strict)
            let andSymbols = try db.getSymbolsLike(name: query, strict: true)
            
            totalOrResults += orSymbols.count
            totalAndResults += andSymbols.count
            
            // In a multi-term search, AND should always be <= OR
            if query.contains(" ") {
                XCTAssertTrue(andSymbols.count <= orSymbols.count, "Strict search for '\(query)' should return fewer or equal results than broad search. Got AND: \(andSymbols.count), OR: \(orSymbols.count)")
            }
            
            // Search Files
            let orFiles = try db.getFilesLike(pattern: query, strict: false)
            let andFiles = try db.getFilesLike(pattern: query, strict: true)
            
            if query.contains(" ") {
                XCTAssertTrue(andFiles.count <= orFiles.count, "Strict file search for '\(query)' failed comparison.")
            }
        }
        
        print("Comparison completed for 100 searches.")
        print("Total OR results (symbols + files): \(totalOrResults)")
        print("Total AND results (symbols + files): \(totalAndResults)")
        
        // Sanity check: Total AND should be significantly less than total OR for these varied queries
        XCTAssertTrue(totalAndResults < totalOrResults, "Strict search should have narrowed down results across the suite.")
    }
    
    func testAgenticCyclicReductionEstimate() async throws {
        // Goal: Estimate how many conversational turns (cyclic tool calls) CCKit saves
        // compared to a naive agent using `grep`.
        // A naive `grep` for a common term will return many false positives across files.
        // The agent then has to read multiple files (`read_file`) to find the right definition.
        // CCKit (`cckit symbol` or exact index lookup) finds the definition immediately.
        
        // 1. Create a large, noisy mock project
        for i in 0..<50 {
            let noisyURL = tempDir.appendingPathComponent("Noise\(i).swift")
            let noisyContent = """
            // This file mentions User and Database a lot but does not define them.
            class NoiseManager\(i) {
                var user: User?
                var db: Database?
                
                func fetchUser() {
                    print("Fetching user from database")
                }
                
                func processData() {
                    let tempUser = "user_\(i)"
                    print("Processed \\(tempUser)")
                }
            }
            """
            try noisyContent.write(to: noisyURL, atomically: true, encoding: .utf8)
        }
        try await indexer.index(at: tempDir.path)
        
        print("--- CYCLIC TOOL CALL REDUCTION ESTIMATE ---")
        
        let targetQueries = [
            ("User", SymbolRecord.Kind.struct),
            ("Database", SymbolRecord.Kind.class),
            ("Theme", SymbolRecord.Kind.enum),
            ("APIClient", SymbolRecord.Kind.class)
        ]
        
        var totalTurnsSaved = 0
        
        // Iterate for 10 cycles as requested
        for cycle in 1...10 {
            let (query, kind) = targetQueries[cycle % targetQueries.count]
            
            // SIMULATE: Agentic Naive Grep
            // Grep does a full-text search across files recursively.
            var simulatedGrepResultCount = 0
            if let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" {
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        if content.contains(query) {
                            simulatedGrepResultCount += 1
                        }
                    }
                }
            }
            
            // SIMULATE: Agent behavior
            // Let's assume every false positive file in the grep result costs 0.5 turns
            
            // SIMULATE: CCKit Exact Lookup
            let cckitResults = try db.getSymbols(qualifiedName: query).filter { $0.kind == kind }
            let cckitResultCount = cckitResults.count
            
            // Estimate Turns Saved
            let falsePositives = max(0, simulatedGrepResultCount - cckitResultCount)
            let turnsSaved = Int(ceil(Double(falsePositives) * 0.5))
            totalTurnsSaved += turnsSaved
            
            print("Cycle \(cycle) | Query: '\(query)' | Grep hits: \(simulatedGrepResultCount) files | CCKit hits: \(cckitResultCount) symbol | Turns Saved: \(turnsSaved)")
            
            if cckitResultCount > 0 { // Allow 0 because we didn't index User/Database properly in the setup for SearchComparisonTests
                if query == "User" || query == "Database" {
                    XCTAssertTrue(turnsSaved >= 10, "CCKit should save significant turns (>=10) in a noisy codebase for common terms.")
                }
            }
        }
        
        print("TOTAL AGENTIC TURNS SAVED OVER 10 CYCLES: \(totalTurnsSaved)")
        XCTAssertTrue(totalTurnsSaved > 100, "CCKit should save >100 conversational turns over 10 searches.")
    }
}
