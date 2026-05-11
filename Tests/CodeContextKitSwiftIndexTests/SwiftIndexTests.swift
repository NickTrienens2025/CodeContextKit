import XCTest
import SwiftSyntax
import SwiftParser
@testable import CodeContextKitSwiftIndex
@testable import CodeContextKitCore

final class SwiftIndexTests: XCTestCase {
    func testSymbolExtractionAndReferences() {
        let content = """
        struct MyStruct {
            let myProp: Int
            func myFunc() {
                print(myProp)
            }
        }
        
        class MyClass {
            let instance = MyStruct()
            init() {}
        }
        """
        
        let swiftFile = SwiftSourceFile(filePath: "test.swift", content: content)
        let (symbols, references) = swiftFile.extractSymbols()
        
        // Symbols check
        XCTAssertTrue(symbols.contains { $0.name == "MyStruct" })
        XCTAssertTrue(symbols.contains { $0.name == "myProp" })
        XCTAssertTrue(symbols.contains { $0.name == "myFunc" })
        
        // References check
        XCTAssertTrue(references.contains { $0.name == "myProp" })
        XCTAssertTrue(references.contains { $0.name == "MyStruct" })
        
        // Context check
        let propRef = references.first { $0.name == "myProp" }
        XCTAssertEqual(propRef?.context, "MyStruct.myFunc")
    }
    
    func testTestDetection() {
        let content = """
        class MyTests {
            func testSomething() {}
        }
        """
        
        let swiftFile = SwiftSourceFile(filePath: "MyTests.swift", content: content)
        let (symbols, _) = swiftFile.extractSymbols()
        
        let testSymbol = symbols.first { $0.name == "testSomething" }
        XCTAssertEqual(testSymbol?.kind, .test)
    }

    func testFileHasherExtraction() {
        let content = """
        public struct FileHasher {
            public init() {}
            
            public func hash(content: String) -> String {
                let data = Data(content.utf8)
                let hash = SHA256.hash(data: data)
                return hash.compactMap { String(format: "%02x", $0) }.joined()
            }
            
            public func hash(url: URL) throws -> String {
                let data = try Data(contentsOf: url)
                let hash = SHA256.hash(data: data)
                return hash.compactMap { String(format: "%02x", $0) }.joined()
            }
        }
        """
        
        let swiftFile = SwiftSourceFile(filePath: "FileHasher.swift", content: content)
        let (symbols, _) = swiftFile.extractSymbols()
        
        // Should have: FileHasher (struct), init, hash(content:), hash(url:)
        // Total symbols should be 4
        XCTAssertEqual(symbols.count, 4)
        
        XCTAssertTrue(symbols.contains { $0.name == "FileHasher" && $0.kind == .struct })
        XCTAssertTrue(symbols.contains { $0.name == "init" && $0.kind == .initializer })
        XCTAssertEqual(symbols.filter { $0.name == "hash" && $0.kind == .function }.count, 2)
        
        // Ensure local vars are NOT symbols
        XCTAssertFalse(symbols.contains { $0.name == "data" })
        XCTAssertFalse(symbols.contains { $0.name == "hash" && $0.kind == .property })
    }
}
