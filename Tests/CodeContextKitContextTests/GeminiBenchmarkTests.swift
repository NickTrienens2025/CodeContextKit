import XCTest
import Foundation
@testable import CodeContextKitContext
@testable import CodeContextKitStorage
@testable import CodeContextKitRetrieval
@testable import CodeContextKitSwiftIndex
@testable import CodeContextKitCore

final class GeminiBenchmarkTests: XCTestCase {
    var db: CodeContextKitStorage.Database!
    var wax: WaxStore!
    var indexer: Indexer!
    var tempDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        let uuid = UUID().uuidString
        db = try CodeContextKitStorage.Database(path: NSTemporaryDirectory() + uuid + ".sqlite")
        wax = try await WaxStore(path: NSTemporaryDirectory() + uuid + ".wax")
        indexer = Indexer(db: db, wax: wax)
        
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uuid)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 1. Create a "Defining" file (Dependency)
        let serviceURL = tempDir.appendingPathComponent("StorageService.swift")
        try """
        public class StorageService {
            public func saveData(_ data: String) {
                print("Saving")
            }
        }
        """.write(to: serviceURL, atomically: true, encoding: .utf8)
        
        // 2. Create a "Consumer" file (Target)
        let cmdURL = tempDir.appendingPathComponent("SaveCommand.swift")
        try """
        struct SaveCommand {
            let service = StorageService()
            func run() {
                service.saveData("test")
            }
        }
        """.write(to: cmdURL, atomically: true, encoding: .utf8)
        
        try await indexer.index(at: tempDir.path)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testSurgicalContextExpansion() throws {
        // SCENARIO: User stages 'SaveCommand.swift' for a bug fix.
        // GEMINI GOAL: The system should automatically find 'StorageService.swift' 
        // because it defines the 'StorageService' used in the command.
        
        let initialItems = [
            ["path": "SaveCommand.swift", "kind": "file", "reason": "Target for modification"]
        ]
        
        // Simulating the server's expansion logic
        var expandedItems = initialItems
        
        // Gemini's Best Approach: 
        // 1. Look for internal references in the staged files
        let refs = try db.getReferencesInFile(path: "SaveCommand.swift")
        XCTAssertTrue(refs.contains { $0.name == "StorageService" })
        
        // 2. Find defining files
        for ref in refs {
            let defs = try db.getSymbols(qualifiedName: ref.name)
            for def in defs {
                if !expandedItems.contains(where: { $0["path"] == def.filePath }) {
                    expandedItems.append(["path": def.filePath, "kind": "file", "reason": "Defines '\(def.name)'"])
                }
            }
        }
        
        // VERIFICATION
        XCTAssertTrue(expandedItems.contains { $0["path"] == "StorageService.swift" }, "System failed to find the tightly coupled dependency StorageService.swift")
        XCTAssertEqual(expandedItems.count, 2)
        
        // 3. Packaging Efficiency
        // Gemini recommends: Staged files get Body, Associated files get Skeleton
        var contextOutput = ""
        for item in expandedItems {
            let path = item["path"]!
            let reason = item["reason"]!
            
            if reason == "Target for modification" {
                // FULL BODY - Mocking content reading for test
                let content = try String(contentsOf: tempDir.appendingPathComponent(path), encoding: .utf8)
                contextOutput += "## File: \(path) (FULL)\n\(content)\n"
            } else {
                // SKELETON ONLY
                let symbols = try db.getSymbols(path: path)
                let skeleton = SwiftOutlineRenderer().render(filePath: path, symbols: symbols)
                contextOutput += "## File: \(path) (SKELETON)\n\(skeleton)\n"
            }
        }
        
        print("GENERATED CONTEXT:\n\(contextOutput)")
        XCTAssertTrue(contextOutput.contains("struct SaveCommand"), "Should contain target symbols from SaveCommand.swift")
        XCTAssertTrue(contextOutput.contains("class StorageService"), "Should contain dependency symbols from StorageService.swift")
        XCTAssertFalse(contextOutput.contains("print(\"Saving\")"), "StorageService should be a skeleton, it should NOT contain implementation details like print statements.")
    }
}
