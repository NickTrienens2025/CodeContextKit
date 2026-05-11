import XCTest
import Foundation
@testable import CodeContextKitStorage
@testable import CodeContextKitCore

final class StorageTests: XCTestCase {
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
    
    func testContextPacks() throws {
        let items = [
            ["path": "File.swift", "kind": "file", "reason": "Base class"],
            ["path": "Func::File.swift", "kind": "symbol", "reason": "Target logic"]
        ]
        
        try db.saveContextPack(name: "Feature-A", description: "Test Pack", items: items)
        
        let packs = try db.getContextPacks()
        XCTAssertEqual(packs.count, 1)
        XCTAssertEqual(packs[0].name, "Feature-A")
        
        let packItems = try db.getContextPackItems(packId: packs[0].id!)
        XCTAssertEqual(packItems.count, 2)
        XCTAssertEqual(packItems[0].reason, "Base class")
        XCTAssertEqual(packItems[1].reason, "Target logic")
    }
    
    func testFavoritesWithViewMode() throws {
        try db.addFavorite(name: "MyFunc", filePath: "Source.swift", kind: "function", viewMode: "full")
        let favs = try db.getFavorites()
        XCTAssertEqual(favs.count, 1)
        XCTAssertEqual(favs[0].viewMode, "full")
    }
}
