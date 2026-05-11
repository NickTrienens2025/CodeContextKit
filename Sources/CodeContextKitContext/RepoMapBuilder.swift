import Foundation
import CodeContextKitCore
import CodeContextKitStorage
import CodeContextKitSwiftIndex

public final class RepoMapBuilder {
    private let db: Database
    private let estimator = TokenEstimator()
    private let renderer = SwiftOutlineRenderer()
    
    public init(db: Database) {
        self.db = db
    }
    
    public func buildMap(budget: Int, focusTerms: String? = nil) throws -> String {
        var output = "# Repository Map\n\n"
        
        let files = try db.getAllFiles()
        
        // Simple strategy: Sort files by path and add their outlines until budget is reached
        for file in files.sorted(by: { $0.path < $1.path }) {
            let symbols = try db.getSymbols(fileId: file.id!)
            let outline = renderer.render(filePath: file.path, symbols: symbols)
            
            let nextTokens = estimator.estimate(output + outline + "\n---\n")
            if nextTokens > budget {
                output += "\n... (remaining files omitted to stay within budget)\n"
                break
            }
            
            output += outline + "\n---\n"
        }
        
        return output
    }
}
