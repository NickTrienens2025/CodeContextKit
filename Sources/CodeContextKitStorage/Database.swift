import Foundation
import GRDB
import CodeContextKitCore

public final class Database: @unchecked Sendable {
    private let writer: DatabaseWriter
    
    public init(path: String) throws {
        // Create directory if it doesn't exist
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        self.writer = try DatabaseQueue(path: path)
        try migrator.migrate(writer)
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: "fileRecord") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull().unique()
                t.column("language", .text).notNull()
                t.column("sha256", .text).notNull()
                t.column("sizeBytes", .integer).notNull()
                t.column("modifiedAt", .datetime)
                t.column("indexedAt", .datetime).notNull()
            }
            
            try db.create(table: "symbolRecordInternal") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("fileId", .integer)
                    .notNull()
                    .references("fileRecord", column: "id", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("qualifiedName", .text).notNull()
                t.column("signature", .text)
                t.column("enclosingType", .text)
                t.column("accessLevel", .text)
                t.column("startLine", .integer).notNull()
                t.column("endLine", .integer).notNull()
                t.column("docComment", .text)
                t.column("estimatedTokens", .integer)
                
                t.uniqueKey(["fileId", "qualifiedName", "startLine", "endLine"])
            }
            
            try db.create(index: "idx_symbols_name", on: "symbolRecordInternal", columns: ["name"])
            try db.create(index: "idx_symbols_qualifiedName", on: "symbolRecordInternal", columns: ["qualifiedName"])
            try db.create(index: "idx_symbols_kind", on: "symbolRecordInternal", columns: ["kind"])
        }

        migrator.registerMigration("addReferences") { db in
            try db.create(table: "symbolReferenceInternal") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("fileId", .integer)
                    .notNull()
                    .references("fileRecord", column: "id", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("startLine", .integer).notNull()
                t.column("endLine", .integer).notNull()
                t.column("context", .text)
            }
            try db.create(index: "idx_references_name", on: "symbolReferenceInternal", columns: ["name"])
        }

        migrator.registerMigration("addLineMetrics") { db in
            try db.alter(table: "fileRecord") { t in
                t.add(column: "docLineCount", .integer).defaults(to: 0)
                t.add(column: "codeLineCount", .integer).defaults(to: 0)
            }
        }

        migrator.registerMigration("addFavorites") { db in
            try db.create(table: "favoriteRecord") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["name", "filePath"])
            }
        }
        
        migrator.registerMigration("fixFavoritesTableName") { db in
            if try db.tableExists("favorite") {
                try db.drop(table: "favorite")
            }
            let exists = try db.tableExists("favoriteRecord")
            if !exists {
                try db.create(table: "favoriteRecord") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("name", .text).notNull()
                    t.column("filePath", .text).notNull()
                    t.column("kind", .text).notNull()
                    t.column("createdAt", .datetime).notNull()
                    t.uniqueKey(["name", "filePath"])
                }
            }
        }

        migrator.registerMigration("addFavoriteViewMode") { db in
            try db.alter(table: "favoriteRecord") { t in
                t.add(column: "viewMode", .text).defaults(to: "symbols")
            }
        }

        migrator.registerMigration("addContextPacks") { db in
            try db.create(table: "contextPack") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("description", .text)
                t.column("createdAt", .datetime).notNull()
            }
            
            try db.create(table: "contextPackItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("packId", .integer)
                    .notNull()
                    .references("contextPack", column: "id", onDelete: .cascade)
                t.column("path", .text).notNull()
                t.column("kind", .text).notNull() // 'file' or 'symbol'
                t.column("reason", .text) // Why this was added
            }
        }
        
        return migrator
    }
    
    public func saveFile(path: String, language: String, sha256: String, sizeBytes: Int, modifiedAt: Date?, docLines: Int = 0, codeLines: Int = 0) throws -> Int64 {
        try writer.write { db in
            var file = FileRecord(
                id: nil,
                path: path,
                language: language,
                sha256: sha256,
                sizeBytes: sizeBytes,
                modifiedAt: modifiedAt,
                indexedAt: Date(),
                docLineCount: docLines,
                codeLineCount: codeLines
            )
            try file.save(db)
            return file.id!
        }
    }
    
    public func deleteFile(path: String) throws {
        _ = try writer.write { db in
            try FileRecord.filter(Column("path") == path).deleteAll(db)
        }
    }
    
    public func getFile(path: String) throws -> FileRecord? {
        try writer.read { db in
            try FileRecord.filter(Column("path") == path).fetchOne(db)
        }
    }
    
    public func saveSymbols(_ symbols: [SymbolRecord], references: [SymbolRecord.Reference], fileId: Int64) throws {
        try writer.write { db in
            for symbol in symbols {
                var record = SymbolRecordInternal(
                    id: nil,
                    fileId: fileId,
                    kind: symbol.kind.rawValue,
                    name: symbol.name,
                    qualifiedName: symbol.qualifiedName,
                    signature: symbol.signature,
                    enclosingType: symbol.enclosingType,
                    accessLevel: symbol.accessLevel,
                    startLine: symbol.startLine,
                    endLine: symbol.endLine,
                    docComment: symbol.docComment,
                    estimatedTokens: symbol.estimatedTokens
                )
                try record.save(db)
            }

            for ref in references {
                var record = SymbolReferenceInternal(
                    id: nil,
                    fileId: fileId,
                    name: ref.name,
                    startLine: ref.startLine,
                    endLine: ref.endLine,
                    context: ref.context
                )
                try record.save(db)
            }
        }
    }
    
    public func getAllFiles() throws -> [FileRecord] {
        try writer.read { db in
            try FileRecord.fetchAll(db)
        }
    }

    public func getFilesLike(pattern: String) throws -> [FileRecord] {
        try writer.read { db in
            try FileRecord.filter(Column("path").like("%\(pattern)%")).fetchAll(db)
        }
    }
    
    public func getSymbols(fileId: Int64) throws -> [SymbolRecord] {
        try writer.read { db in
            try _getSymbols(db, fileId: fileId)
        }
    }

    private func _getSymbols(_ db: GRDB.Database, fileId: Int64) throws -> [SymbolRecord] {
        let file = try FileRecord.filter(Column("id") == fileId).fetchOne(db)
        let records = try SymbolRecordInternal
            .filter(Column("fileId") == fileId)
            .fetchAll(db)
        
        return records.map { record in
            SymbolRecord(
                kind: SymbolRecord.Kind(rawValue: record.kind) ?? .function,
                name: record.name,
                qualifiedName: record.qualifiedName,
                signature: record.signature ?? "",
                filePath: file?.path ?? "",
                startLine: record.startLine,
                endLine: record.endLine,
                enclosingType: record.enclosingType,
                accessLevel: record.accessLevel,
                docComment: record.docComment,
                estimatedTokens: record.estimatedTokens ?? 0
            )
        }
    }
    
    public func getSymbols(path: String) throws -> [SymbolRecord] {
        try writer.read { db in
            guard let file = try FileRecord.filter(Column("path") == path).fetchOne(db) else {
                return []
            }
            return try _getSymbols(db, fileId: file.id!)
        }
    }

    public func getSymbolsLike(name: String) throws -> [SymbolRecord] {
        try writer.read { db in
            let records = try SymbolRecordInternal
                .filter(Column("name").like("%\(name)%") || Column("qualifiedName").like("%\(name)%"))
                .order(Column("qualifiedName").asc)
                .fetchAll(db)
            
            return try records.map { record in
                let file = try FileRecord.filter(Column("id") == record.fileId).fetchOne(db)
                return SymbolRecord(
                    kind: SymbolRecord.Kind(rawValue: record.kind) ?? .function,
                    name: record.name,
                    qualifiedName: record.qualifiedName,
                    signature: record.signature ?? "",
                    filePath: file?.path ?? "",
                    startLine: record.startLine,
                    endLine: record.endLine,
                    enclosingType: record.enclosingType,
                    accessLevel: record.accessLevel,
                    docComment: record.docComment,
                    estimatedTokens: record.estimatedTokens ?? 0
                )
            }
        }
    }

    public func getSymbols(qualifiedName: String) throws -> [SymbolRecord] {
        try writer.read { db in
            let records = try SymbolRecordInternal
                .filter(Column("qualifiedName") == qualifiedName)
                .fetchAll(db)
            
            return try records.map { record in
                let file = try FileRecord.filter(Column("id") == record.fileId).fetchOne(db)
                return SymbolRecord(
                    kind: SymbolRecord.Kind(rawValue: record.kind) ?? .function,
                    name: record.name,
                    qualifiedName: record.qualifiedName,
                    signature: record.signature ?? "",
                    filePath: file?.path ?? "",
                    startLine: record.startLine,
                    endLine: record.endLine,
                    enclosingType: record.enclosingType,
                    accessLevel: record.accessLevel,
                    docComment: record.docComment,
                    estimatedTokens: record.estimatedTokens ?? 0
                )
            }
        }
    }

    public func getReferences(forSymbolName name: String) throws -> [SymbolRecord.Reference] {
        try writer.read { db in
            let records = try SymbolReferenceInternal
                .filter(Column("name") == name)
                .fetchAll(db)
            return try records.map {
                let file = try FileRecord.filter(Column("id") == $0.fileId).fetchOne(db)
                return SymbolRecord.Reference(name: $0.name, startLine: $0.startLine, endLine: $0.endLine, context: $0.context, file: file?.path ?? "")
            }
        }
    }

    public func getReferencesInFile(path: String) throws -> [SymbolRecord.Reference] {
        try writer.read { db in
            guard let file = try FileRecord.filter(Column("path") == path).fetchOne(db) else { return [] }
            let records = try SymbolReferenceInternal
                .filter(Column("fileId") == file.id!)
                .fetchAll(db)
            return records.map {
                SymbolRecord.Reference(name: $0.name, startLine: $0.startLine, endLine: $0.endLine, context: $0.context, file: path)
            }
        }
    }

    public func getReferenceCount(forSymbolName name: String) throws -> Int {
        try writer.read { db in
            try SymbolReferenceInternal
                .filter(Column("name") == name)
                .fetchCount(db)
        }
    }

    public func getStats(pathPrefix: String? = nil) throws -> [String: Any] {
        try writer.read { db in
            let fileFilter = pathPrefix != nil ? "WHERE path LIKE '\(pathPrefix!)%'" : ""
            let symbolFilter = pathPrefix != nil ? "WHERE fileId IN (SELECT id FROM fileRecord WHERE path LIKE '\(pathPrefix!)%')" : ""

            let fileCountRow = try Row.fetchOne(db, sql: "SELECT count(*) FROM fileRecord \(fileFilter)")
            let fileCount: Int = fileCountRow?[0] ?? 0

            let symbolCountRow = try Row.fetchOne(db, sql: "SELECT count(*) FROM symbolRecordInternal \(symbolFilter)")
            let symbolCount: Int = symbolCountRow?[0] ?? 0
            
            let kindCounts = try Row.fetchAll(db, sql: "SELECT kind, count(*) FROM symbolRecordInternal \(symbolFilter) GROUP BY kind")
            
            var kindDict: [String: Int] = [:]
            for row in kindCounts {
                let kind: String = row[0]
                let count: Int = row[1]
                kindDict[kind] = count
            }
            
            let totalBytesRow = try Row.fetchOne(db, sql: "SELECT sum(sizeBytes) FROM fileRecord \(fileFilter)")
            let totalBytes: Int64 = totalBytesRow?[0] ?? 0
            
            let totalDocLinesRow = try Row.fetchOne(db, sql: "SELECT sum(docLineCount) FROM fileRecord \(fileFilter)")
            let totalDocLines: Int64 = totalDocLinesRow?[0] ?? 0

            let totalCodeLinesRow = try Row.fetchOne(db, sql: "SELECT sum(codeLineCount) FROM fileRecord \(fileFilter)")
            let totalCodeLines: Int64 = totalCodeLinesRow?[0] ?? 0

            return [
                "fileCount": fileCount,
                "symbolCount": symbolCount,
                "kindCounts": kindDict,
                "totalBytes": totalBytes,
                "totalDocLines": totalDocLines,
                "totalCodeLines": totalCodeLines
            ]
        }
    }

    public func addFavorite(name: String, filePath: String, kind: String, viewMode: String = "symbols") throws {
        try writer.write { db in
            var favorite = FavoriteRecord(id: nil, name: name, filePath: filePath, kind: kind, viewMode: viewMode, createdAt: Date())
            try favorite.insert(db)
        }
    }

    public func removeFavorite(name: String, filePath: String) throws {
        _ = try writer.write { db in
            try FavoriteRecord.filter(Column("name") == name && Column("filePath") == filePath).deleteAll(db)
        }
    }

    public func getFavorites() throws -> [FavoriteRecord] {
        try writer.read { db in
            try FavoriteRecord.order(Column("createdAt").desc).fetchAll(db)
        }
    }
    
    // Context Pack Methods
    public func saveContextPack(name: String, description: String?, items: [[String: String]]) throws {
        try writer.write { db in
            // Delete existing pack with same name if any
            try ContextPack.filter(Column("name") == name).deleteAll(db)
            
            var pack = ContextPack(id: nil, name: name, description: description, createdAt: Date())
            try pack.insert(db)
            
            for item in items {
                var packItem = ContextPackItem(
                    id: nil,
                    packId: pack.id!,
                    path: item["path"] ?? "",
                    kind: item["kind"] ?? "",
                    reason: item["reason"]
                )
                try packItem.insert(db)
            }
        }
    }
    
    public func getContextPacks() throws -> [ContextPack] {
        try writer.read { db in
            try ContextPack.order(Column("createdAt").desc).fetchAll(db)
        }
    }
    
    public func getContextPackItems(packId: Int64) throws -> [ContextPackItem] {
        try writer.read { db in
            try ContextPackItem.filter(Column("packId") == packId).fetchAll(db)
        }
    }
    
    public func deleteContextPack(name: String) throws {
        _ = try writer.write { db in
            try ContextPack.filter(Column("name") == name).deleteAll(db)
        }
    }
}

// Public GRDB models
public struct FileRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var path: String
    public var language: String
    public var sha256: String
    public var sizeBytes: Int
    public var modifiedAt: Date?
    public var indexedAt: Date
    public var docLineCount: Int
    public var codeLineCount: Int
    
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct SymbolRecordInternal: Codable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var fileId: Int64
    public var kind: String
    public var name: String
    public var qualifiedName: String
    public var signature: String?
    public var enclosingType: String?
    public var accessLevel: String?
    public var startLine: Int
    public var endLine: Int
    public var docComment: String?
    public var estimatedTokens: Int?
    
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct SymbolReferenceInternal: Codable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var fileId: Int64
    public var name: String
    public var startLine: Int
    public var endLine: Int
    public var context: String?
    
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct FavoriteRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public var filePath: String
    public var kind: String
    public var viewMode: String
    public var createdAt: Date
    
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ContextPack: Codable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public var description: String?
    public var createdAt: Date
    
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ContextPackItem: Codable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var packId: Int64
    public var path: String
    public var kind: String
    public var reason: String?
    
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
