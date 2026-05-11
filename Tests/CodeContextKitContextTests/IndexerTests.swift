import XCTest
import Foundation
@testable import CodeContextKitContext
@testable import CodeContextKitStorage
@testable import CodeContextKitRetrieval

final class IndexerTests: XCTestCase {
    var db: CodeContextKitStorage.Database!
    var wax: WaxStore!
    var indexer: Indexer!
    var tempDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        let uuid = UUID().uuidString
        let tempDbPath = NSTemporaryDirectory() + uuid + ".sqlite"
        db = try CodeContextKitStorage.Database(path: tempDbPath)
        wax = try await WaxStore(path: NSTemporaryDirectory() + uuid + ".wax")
        indexer = Indexer(db: db, wax: wax)
        
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uuid)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testIncrementalIndexing() async throws {
        let fileURL = tempDir.appendingPathComponent("Test.swift")
        try "struct A {}".write(to: fileURL, atomically: true, encoding: .utf8)
        
        // First run
        try await indexer.index(at: tempDir.path)
        let files1 = try db.getAllFiles()
        XCTAssertEqual(files1.count, 1)
        
        // Second run (no changes)
        try await indexer.index(at: tempDir.path)
        let files2 = try db.getAllFiles()
        XCTAssertEqual(files2.count, 1)
        XCTAssertEqual(files2[0].sha256, files1[0].sha256)
        
        // Change file
        try "struct B {}".write(to: fileURL, atomically: true, encoding: .utf8)
        try await indexer.index(at: tempDir.path)
        
        let symbols = try db.getSymbols(path: "Test.swift")
        XCTAssertTrue(symbols.contains { $0.name == "B" })
    }

    func testMultiLanguageIndexing() async throws {
        // Create a JSON file in the root of the test directory
        let jsonURL = tempDir.appendingPathComponent("config.json")
        try "{ \"key\": \"value\" }".write(to: jsonURL, atomically: true, encoding: .utf8)
        
        try await indexer.index(at: tempDir.path)
        
        let files = try db.getAllFiles()
        XCTAssertTrue(files.contains { $0.path == "config.json" })
        XCTAssertEqual(files.first { $0.path == "config.json" }?.language, "json")
        
        // Non-Swift files should be indexed as a single 'file' symbol for search
        let symbols = try db.getSymbols(path: "config.json")
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].kind, .file)
    }
}
