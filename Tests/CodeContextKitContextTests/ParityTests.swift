import XCTest
import Foundation
@testable import CodeContextKitContext
@testable import CodeContextKitStorage
@testable import CodeContextKitRetrieval
@testable import CodeContextKitSwiftIndex
@testable import CodeContextKitCore

final class ParityTests: XCTestCase {
    var db: CodeContextKitStorage.Database!
    var indexer: Indexer!
    var tempDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        let uuid = UUID().uuidString
        db = try CodeContextKitStorage.Database(path: NSTemporaryDirectory() + uuid + ".sqlite")
        // Stubbed WaxStore for now to avoid Sig11
        let wax = try await WaxStore(path: NSTemporaryDirectory() + uuid + ".wax")
        indexer = Indexer(db: db, wax: wax)
        
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uuid)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        try """
        public class Dependency {
            public func execute() {}
        }
        """.write(to: tempDir.appendingPathComponent("Dependency.swift"), atomically: true, encoding: .utf8)
        
        try """
        struct Main {
            let dep = Dependency()
            func run() { dep.execute() }
        }
        """.write(to: tempDir.appendingPathComponent("Main.swift"), atomically: true, encoding: .utf8)
        
        try await indexer.index(at: tempDir.path)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(atDir: tempDir)
        super.tearDown()
    }
    
    func testAutoExpandParity() throws {
        let stagedItems = [["path": "Main.swift", "kind": "file"]]
        let refs = try db.getReferencesInFile(path: "Main.swift")
        var expanded = stagedItems
        
        for ref in refs {
            let defs = try db.getSymbols(qualifiedName: ref.name)
            for def in defs {
                if !expanded.contains(where: { $0["path"] == def.filePath }) {
                    expanded.append(["path": def.filePath, "kind": "file", "reason": "Associated"])
                }
            }
        }
        XCTAssertTrue(expanded.contains { $0["path"] == "Dependency.swift" })
    }
    
    func testOutlineParity() throws {
        let symbols = try db.getSymbols(path: "Main.swift")
        let outline = SwiftOutlineRenderer().render(filePath: "Main.swift", symbols: symbols)
        XCTAssertTrue(outline.contains("struct Main"))
    }
}

extension FileManager {
    func removeItem(atDir url: URL) {
        try? removeItem(at: url)
    }
}
