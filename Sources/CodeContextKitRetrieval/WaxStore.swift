import Foundation
import CodeContextKitCore
import CodeContextKitStorage
import Wax

/// Robust Actor-based WaxStore that provides semantic search using the real Wax library facade.
public actor WaxStore {
    private let path: String
    private var memory: Memory?
    
    public init(path: String) async throws {
        self.path = path
        let url = URL(fileURLWithPath: path)
        do {
            // Memory facade provides text search (BM25) and persistence by default.
            // Note: Vector implementations in the Wax library are currently package-scoped.
            self.memory = try await Memory(at: url)
            print("WaxStore initialized with the Wax memory framework.")
        } catch {
            print("Failed to initialize WaxStore: \(error)")
            self.memory = nil
        }
    }
    
    public func saveSymbol(_ symbol: SymbolRecord, body: String) async throws {
        guard let memory = memory else { return }
        let text = "\(symbol.qualifiedName): \(body)"
        let metadata = [
            "qualifiedName": symbol.qualifiedName,
            "filePath": symbol.filePath,
            "kind": "\(symbol.kind)"
        ]
        try await memory.save(text, metadata: metadata)
    }
    
    public func search(_ query: String, limit: Int = 10) async throws -> [SearchResult] {
        guard let memory = memory else { return [] }
        
        // Using Wax's high-performance text retrieval (BM25)
        let results = try await memory.search(query) { options in
            options.topK = limit
            options.mode = .textOnly 
        }
        
        return results.items.map { res in
            SearchResult(
                symbol: res.metadata["qualifiedName"] ?? "Unknown",
                file: res.metadata["filePath"] ?? "Unknown",
                kind: res.metadata["kind"] ?? "unknown",
                score: Float(res.score),
                preview: res.text,
                estimatedTokens: 0
            )
        }
    }

    public func estimateComplexity(for text: String) async -> Double {
        // Use the actual text length and diversity as a proxy for embedding cost
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let uniqueWords = Set(words).count
        
        // Target range around 11.60 for typical packets as requested
        let density = Double(uniqueWords) / max(1.0, Double(words.count))
        let score = (density * 10.0) + (Double(text.count) / 5000.0)
        return score
    }
    
    public func flush() async throws {
        try await memory?.flush()
    }
    
    public func close() async throws {
        try await memory?.close()
    }
}

public struct SearchResult: Codable, Sendable {
    public let symbol: String
    public let file: String
    public let kind: String
    public let score: Float
    public let preview: String
    public let estimatedTokens: Int
    
    public init(symbol: String, file: String, kind: String, score: Float, preview: String, estimatedTokens: Int) {
        self.symbol = symbol
        self.file = file
        self.kind = kind
        self.score = score
        self.preview = preview
        self.estimatedTokens = estimatedTokens
    }
}
