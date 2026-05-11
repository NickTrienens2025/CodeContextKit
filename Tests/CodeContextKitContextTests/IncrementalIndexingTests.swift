import XCTest
import Foundation
@testable import CodeContextKitContext
@testable import CodeContextKitStorage
@testable import CodeContextKitRetrieval
@testable import CodeContextKitCore

final class IncrementalIndexingTests: XCTestCase {
    var db: CodeContextKitStorage.Database!
    var wax: WaxStore!
    var indexer: Indexer!
    var packer: ContextPacker!
    var tempDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        let uuid = UUID().uuidString
        db = try CodeContextKitStorage.Database(path: NSTemporaryDirectory() + uuid + ".sqlite")
        wax = try await WaxStore(path: NSTemporaryDirectory() + uuid + ".wax")
        indexer = Indexer(db: db, wax: wax)
        
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uuid)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        packer = ContextPacker(db: db, wax: wax, rootPath: tempDir.path)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testFileChangeDetection() async throws {
        let fileURL = tempDir.appendingPathComponent("Feature.swift")
        
        // 1. Initial Index
        try "struct Original { }".write(to: fileURL, atomically: true, encoding: .utf8)
        try await indexer.index(at: tempDir.path)
        
        let originalSymbol = try db.getSymbols(path: "Feature.swift").first
        XCTAssertEqual(originalSymbol?.name, "Original")
        
        // 2. Modify File
        try "struct Modified { }".write(to: fileURL, atomically: true, encoding: .utf8)
        try await indexer.index(at: tempDir.path)
        
        let updatedSymbols = try db.getSymbols(path: "Feature.swift")
        XCTAssertEqual(updatedSymbols.count, 1)
        XCTAssertEqual(updatedSymbols.first?.name, "Modified")
        XCTAssertFalse(updatedSymbols.contains { $0.name == "Original" }, "Stale symbol 'Original' was not removed.")
    }
    
    func testContextPacketFreshness() async throws {
        let fileURL = tempDir.appendingPathComponent("Task.swift")
        
        // 1. Index initial version
        try "func runTask() { print(\"Old\") }".write(to: fileURL, atomically: true, encoding: .utf8)
        try await indexer.index(at: tempDir.path)
        
        // 2. Modify on disk
        try "func runTask() { print(\"New Content\") }".write(to: fileURL, atomically: true, encoding: .utf8)
        
        // 3. Generate packet BEFORE re-indexing
        // Packer uses Wax to find relevant files, then reads from disk for bodies.
        let packetBefore = try await packer.pack(task: "runTask", budget: 1000)
        XCTAssertTrue(packetBefore.contains("New Content"), "Packer should read latest content from disk even if index is stale.")
        
        // 4. Re-index and verify symbols
        try await indexer.index(at: tempDir.path)
        let packetAfter = try await packer.pack(task: "runTask", budget: 1000)
        XCTAssertTrue(packetAfter.contains("New Content"))
    }
    
    func testFileDeletionHandling() async throws {
        let fileURL = tempDir.appendingPathComponent("DeleteMe.swift")
        try "struct Gone { }".write(to: fileURL, atomically: true, encoding: .utf8)
        try await indexer.index(at: tempDir.path)
        
        XCTAssertNotNil(try db.getFile(path: "DeleteMe.swift"))
        
        // Delete file
        try FileManager.default.removeItem(at: fileURL)
        
        // Re-index
        try await indexer.index(at: tempDir.path)
        
        XCTAssertNil(try db.getFile(path: "DeleteMe.swift"), "Deleted file still exists in database.")
    }
}
