import ArgumentParser
import Foundation
import CodeContextKitSwiftIndex

struct OutlineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "outline",
        abstract: "Prints a structural outline of a Swift file."
    )

    @Argument(help: "The Swift file to outline.")
    var filePath: String

    func run() async throws {
        let url = URL(fileURLWithPath: filePath)
        let content = try String(contentsOf: url, encoding: .utf8)
        
        let swiftFile = SwiftSourceFile(filePath: filePath, content: content)
        let (symbols, _) = swiftFile.extractSymbols()
        
        let renderer = SwiftOutlineRenderer()
        let outline = renderer.render(filePath: filePath, symbols: symbols)
        
        print(outline)
    }
}
