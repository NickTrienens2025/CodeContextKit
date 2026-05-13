import Foundation
import CodeContextKitCore
import CodeContextKitStorage
import CodeContextKitRetrieval

/// Manages the history of actions (CLI commands and agent interactions) and tracks their lifecycle.
public actor ActionOrchestrator {
    private let db: Database
    private let wax: WaxStore
    private var activeActions: [Int64: Date] = [:]
    
    public init(db: Database, wax: WaxStore) {
        self.db = db
        self.wax = wax
    }
    
    /// Registers a new action and returns its unique ID.
    public func startAction(prompt: String, toolName: String? = nil, type: String = "web") throws -> Int64 {
        let record = ActionRecord(prompt: prompt, toolName: toolName, type: type, status: "pending")
        let id = try db.saveActionRecord(record)
        activeActions[id] = Date()
        return id
    }
    
    /// Finalizes an action with its result and usage stats.
    public func finishAction(id: Int64, response: String, status: String = "completed") async throws {
        guard let startTime = activeActions.removeValue(forKey: id) else { return }
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        
        let existing = try? db.getActionHistory().first(where: { $0.id == id })
        let promptTokens = await wax.countTokens("prompt: " + (existing?.prompt ?? ""))
        let responseTokens = await wax.countTokens(response)
        let tokens = promptTokens + responseTokens
        
        try db.updateActionRecord(id: id, status: status, durationMs: duration, tokensUsed: tokens, response: response)
    }
    
    /// Retrieves recent actions for visualization.
    public func getRecentActions(limit: Int = 20) throws -> [ActionRecord] {
        return try db.getActionHistory(limit: limit)
    }

    /// Records a simple CLI action that has already completed.
    public func recordCLIAction(command: String, toolName: String, durationMs: Int, tokensUsed: Int = 0, status: String = "completed") throws {
        let record = ActionRecord(prompt: command, toolName: toolName, type: "cli", tokensUsed: tokensUsed, durationMs: durationMs, status: status)
        _ = try db.saveActionRecord(record)
    }
}
