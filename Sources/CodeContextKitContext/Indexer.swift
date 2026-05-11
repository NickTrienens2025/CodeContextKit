import Foundation
import CodeContextKitCore
import CodeContextKitSwiftIndex
import CodeContextKitStorage
import CodeContextKitRetrieval

public protocol IndexerProgressDelegate: Sendable {
    func indexerDidStart(totalFiles: Int)
    func indexerDidProgress(completedFiles: Int, totalFiles: Int, currentFile: String)
    func indexerDidFinish(updated: Int, skipped: Int, totalSymbols: Int)
    func indexerDidFail(error: Error)
}

public final class Indexer: Sendable {
    private let db: Database
    private let wax: WaxStore
    
    public init(db: Database, wax: WaxStore) {
        self.db = db
        self.wax = wax
    }
    
    public func index(
        at path: String,
        include: [String] = [],
        exclude: [String] = [],
        delegate: IndexerProgressDelegate? = nil
    ) async throws {
        let absolutePath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let scanner = FileScanner()
        let hasher = FileHasher()
        
        let files = scanner.scan(at: absolutePath, include: include, exclude: exclude)
        delegate?.indexerDidStart(totalFiles: files.count)
        
        var updatedCount = 0
        var skippedCount = 0
        var totalSymbols = 0
        
        for (index, fileURL) in files.enumerated() {
            let resolvedFileURL = fileURL.resolvingSymlinksInPath()
            let resolvedRootURL = URL(fileURLWithPath: absolutePath).resolvingSymlinksInPath()
            
            var relativePath = resolvedFileURL.path
            if relativePath.hasPrefix(resolvedRootURL.path) {
                relativePath = String(relativePath.dropFirst(resolvedRootURL.path.count))
                if relativePath.hasPrefix("/") {
                    relativePath = String(relativePath.dropFirst())
                }
            }
            
            delegate?.indexerDidProgress(completedFiles: index, totalFiles: files.count, currentFile: relativePath)
            
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let currentHash = hasher.hash(content: content)
                
                if let existingFile = try db.getFile(path: relativePath) {
                    if existingFile.sha256 == currentHash {
                        skippedCount += 1
                        continue
                    }
                    try db.deleteFile(path: relativePath)
                }
                
                let lines = content.components(separatedBy: .newlines)
                var docLines = 0
                var codeLines = 0
                
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { continue }
                    if trimmed.hasPrefix("///") || trimmed.hasPrefix("//") {
                        docLines += 1
                    } else {
                        codeLines += 1
                    }
                }
                
                let ext = (relativePath as NSString).pathExtension.lowercased()
                let isSwift = ext == "swift"
                
                var symbols: [SymbolRecord] = []
                var references: [SymbolRecord.Reference] = []
                
                if isSwift {
                    let swiftFile = SwiftSourceFile(filePath: relativePath, content: content)
                    let extracted = swiftFile.extractSymbols()
                    symbols = extracted.0
                    references = extracted.1
                } else {
                    // For non-Swift files, create a single 'file' symbol
                    symbols = [SymbolRecord(
                        kind: .file,
                        name: relativePath,
                        qualifiedName: relativePath,
                        signature: "File: \(relativePath)",
                        filePath: relativePath,
                        startLine: 1,
                        endLine: lines.count
                    )]
                }
                
                let fileId = try db.saveFile(
                    path: relativePath,
                    language: isSwift ? "swift" : ext,
                    sha256: currentHash,
                    sizeBytes: content.utf8.count,
                    modifiedAt: try fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                    docLines: docLines,
                    codeLines: codeLines
                )
                
                try db.saveSymbols(symbols, references: references, fileId: fileId)
                
                if isSwift {
                    let swiftFile = SwiftSourceFile(filePath: relativePath, content: content)
                    for symbol in symbols {
                        let body = swiftFile.body(for: symbol)
                        try await wax.saveSymbol(symbol, body: body)
                    }
                } else {
                    // For non-Swift files, index the entire file as a single searchable entity in Wax
                    if let fileSymbol = symbols.first {
                        try await wax.saveSymbol(fileSymbol, body: content)
                    }
                }
                
                updatedCount += 1
                totalSymbols += symbols.count
            } catch {
                print("Failed to index \(relativePath): \(error)")
            }
        }
        
        try await wax.flush()
        
        // Cleanup Phase: Remove files from DB that are no longer on disk
        let allIndexedFiles = try db.getAllFiles()
        for indexedFile in allIndexedFiles {
            let fullURL = URL(fileURLWithPath: absolutePath).appendingPathComponent(indexedFile.path)
            if !FileManager.default.fileExists(atPath: fullURL.path) {
                try db.deleteFile(path: indexedFile.path)
                print("Removed stale file from index: \(indexedFile.path)")
            }
        }
        
        delegate?.indexerDidFinish(updated: updatedCount, skipped: skippedCount, totalSymbols: totalSymbols)
    }
}
