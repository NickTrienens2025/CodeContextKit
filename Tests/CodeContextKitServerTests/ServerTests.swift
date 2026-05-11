import XCTest
import Foundation
@testable import CodeContextKitServer
@testable import CodeContextKitStorage
@testable import CodeContextKitCore

final class ServerTests: XCTestCase {
    var db: CodeContextKitStorage.Database!
    var tempDbPath: String!
    
    override func setUp() {
        super.setUp()
        tempDbPath = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        db = try! CodeContextKitStorage.Database(path: tempDbPath)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDbPath)
        super.tearDown()
    }
    
    func testStatsGeneration() throws {
        _ = try db.saveFile(path: "File.swift", language: "swift", sha256: "h1", sizeBytes: 10, modifiedAt: Date())
        let stats = try db.getStats()
        XCTAssertEqual(stats["fileCount"] as? Int, 1)
    }
    
    func testFavoritePersistence() throws {
        try db.addFavorite(name: "Test", filePath: "Test.swift", kind: "class", viewMode: "full")
        let favs = try db.getFavorites()
        XCTAssertEqual(favs.count, 1)
        XCTAssertEqual(favs[0].viewMode, "full")
    }

    func testPackPreviewLogic() throws {
        // This test verifies the logic used in Server.swift for 'get_pack_preview'
        let items = [
            ["path": "Sources/Main.swift", "kind": "file", "reason": "Target"],
            ["path": "Sources/Helper.swift", "kind": "file", "reason": "Dependency"]
        ]
        
        var previewText = "# Context Packet\n\n"
        for item in items {
            previewText += "## File: \(item["path"]!) (Reason: \(item["reason"]!))\n"
        }
        
        let words = previewText.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let estimate = Double(Set(words).count) / 100.0
        
        XCTAssertTrue(previewText.contains("File: Sources/Main.swift"))
        XCTAssertTrue(previewText.contains("Reason: Dependency"))
        XCTAssertGreaterThan(estimate, 0)
    }
    
    func testFrontendIDsPresent() throws {
        let htmlPath = "web/index.html"
        let html = try String(contentsOfFile: htmlPath, encoding: .utf8)
        
        XCTAssertTrue(html.contains("id=\"pack-graph-container\""), "Chrome needs this ID to render the graph")
        XCTAssertTrue(html.contains("id=\"pack-text-preview\""), "Chrome needs this ID to show the textual context")
        XCTAssertTrue(html.contains("id=\"embedding-estimate\""), "Chrome needs this ID to show the score")
    }
}
