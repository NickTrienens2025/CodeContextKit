import Foundation
import CodeContextKitCore
import CodeContextKitStorage
import Wax

/// Robust Actor-based WaxStore that provides semantic search and relationship mapping.
public actor WaxStore {
    private let path: String
    private var memory: Memory?
    
    public init(path: String) async throws {
        self.path = path
        let url = URL(fileURLWithPath: path)
        do {
            self.memory = try await Memory(at: url)
        } catch {
            self.memory = nil
        }
    }
    
    public func countTokens(_ text: String) async -> Int {
        // Use the unified TokenEstimator which now uses a Claude-optimized heuristic
        return TokenEstimator.shared.estimate(text)
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
        let results = try await memory.search(query) { options in
            options.topK = limit
            options.mode = .hybrid
        }
        return results.items.map { res in
            SearchResult(
                symbol: res.metadata["qualifiedName"] ?? "Unknown",
                file: res.metadata["filePath"] ?? "Unknown",
                kind: res.metadata["kind"] ?? "unknown",
                score: Float(res.score),
                preview: res.text,
                estimatedTokens: TokenEstimator.shared.estimate(res.text)
            )
        }
    }

    public func getSemanticLinks(for items: [String: String], threshold: Float = 0.3) async -> SemanticResponse {
        var links: [SemanticLink] = []
        let ids = Array(items.keys)
        var vectors: [String: [Float]] = [:]
        var categories: [String: String] = [:] // id -> Topic
        
        for (id, text) in items {
            vectors[id] = generateProxyVector(for: text)
            categories[id] = extractMainTopic(from: text)
        }
        
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let id1 = ids[i]
                let id2 = ids[j]
                guard let v1 = vectors[id1], let v2 = vectors[id2] else { continue }
                
                let score = cosineSimilarity(v1, v2)
                if score >= threshold {
                    links.append(SemanticLink(source: id1, target: id2, strength: score))
                }
            }
        }
        return SemanticResponse(links: links, topics: categories)
    }

    private func extractMainTopic(from text: String) -> String {
        let stopWords: Set<String> = ["the", "and", "func", "struct", "class", "var", "let", "return", "if", "else", "for", "in", "import", "public", "private", "extension", "case", "enum"]
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }
        
        var counts: [String: Int] = [:]
        for word in words { counts[word, default: 0] += 1 }
        return counts.sorted { $0.value > $1.1 }.first?.key ?? "General"
    }

    public func estimateComplexity(for text: String) async -> Double {
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let uniqueWords = Set(words).count
        let density = Double(uniqueWords) / max(1.0, Double(words.count))
        let score = (density * 10.0) + (Double(text.count) / 5000.0)
        return score
    }
    
    public func flush() async throws { try await memory?.flush() }
    public func close() async throws { try await memory?.close() }

    // Internal Math for Graph forces
    private func generateProxyVector(for text: String) -> [Float] {
        var vector = [Float](repeating: 0.0, count: 128)
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        for word in words {
            let hash = abs(word.hashValue)
            vector[hash % 128] += 1.0
        }
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 { for i in 0..<128 { vector[i] /= magnitude } }
        return vector
    }

    private func cosineSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 0 }
        var dotProduct: Float = 0
        for i in 0..<v1.count { dotProduct += v1[i] * v2[i] }
        return dotProduct
    }
}

public struct SemanticResponse: Codable, Sendable {
    public let links: [SemanticLink]
    public let topics: [String: String]
}

public struct SemanticLink: Codable, Sendable {
    public let source: String
    public let target: String
    public let strength: Float
}

public struct SearchResult: Codable, Sendable {
    public let symbol: String
    public let file: String
    public let kind: String
    public let score: Float
    public let preview: String
    public let estimatedTokens: Int
    
    public init(symbol: String, file: String, kind: String, score: Float, preview: String, estimatedTokens: Int) {
        self.symbol = symbol; self.file = file; self.kind = kind; self.score = score; self.preview = preview; self.estimatedTokens = estimatedTokens
    }
}
