import Hummingbird
import HummingbirdRouter
import HummingbirdWebSocket
import Logging
import NIOCore
import NIOPosix
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import CodeContextKitCore
import CodeContextKitStorage
import CodeContextKitRetrieval
import CodeContextKitSwiftIndex
import CodeContextKitContext

public struct ServerContext: RequestContext, WebSocketRequestContext {
    public var coreContext: Hummingbird.CoreRequestContextStorage
    public let webSocket: WebSocketHandlerReference<ServerContext>

    public init(source: Hummingbird.ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
        self.webSocket = .init()
    }
}

public actor IndexingState {
    public var isIndexing: Bool = false
    public var completed: Int = 0
    public var total: Int = 0
    public var currentFile: String = ""
    public var sockets: [WebSocketOutboundWriter] = []
    
    public func addSocket(_ socket: WebSocketOutboundWriter) { sockets.append(socket) }
    public func start(total: Int) { self.isIndexing = true; self.total = total; self.completed = 0; self.currentFile = "" }
    public func update(completed: Int, currentFile: String) { self.completed = completed; self.currentFile = currentFile }
    public func finish() { self.isIndexing = false }
    public func broadcast(_ message: [String: Any]) { guard let data = try? JSONSerialization.data(withJSONObject: message), let jsonString = String(data: data, encoding: .utf8) else { return }; for socket in sockets { let s = socket; Task { try? await s.write(.text(jsonString)) } } }
}

public struct CodeContextServer: Sendable {
    public let port: Int
    let dbPath: String
    let logger: Logger
    let indexingState = IndexingState()

    public init(port: Int, dbPath: String = ".cckit/index.sqlite") { self.port = port; self.dbPath = dbPath; self.logger = Logger(label: "CodeContextKitServer") }

    public static func findFreePort(in range: ClosedRange<Int> = 6060...6999) -> Int? { for port in range { if isPortFree(port) { return port } }; return nil }
    private static func isPortFree(_ port: Int) -> Bool { let serverBootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton); do { let channel = try serverBootstrap.bind(host: "0.0.0.0", port: port).wait(); try channel.close().wait(); return true } catch { return false } }

    public func run() async throws {
        let router = Router(context: ServerContext.self)
        router.addMiddleware { FileMiddleware("web", searchForIndexHtml: true) }
        let db = try Database(path: dbPath)
        let wax = try await WaxStore(path: ".cckit/repo.wax")
        let indexer = Indexer(db: db, wax: wax)

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let projectName = currentDirectory.lastPathComponent
        let readmePath = currentDirectory.appendingPathComponent("README.md").path
        let readmeContent = (try? String(contentsOfFile: readmePath, encoding: .utf8)) ?? ""

        router.get("health") { _, _ in return "OK" }
        router.get("**") { request, context in
            let path = request.uri.path
            if path.contains(".") || path.hasPrefix("/ws") || path == "/health" { throw HTTPError(.notFound) }
            let indexContent = try String(contentsOfFile: "web/index.html", encoding: .utf8)
            return Response(status: .ok, headers: [.contentType: "text/html"], body: .init(byteBuffer: ByteBuffer(string: indexContent)))
        }

        router.ws("/ws") { inbound, outbound, context in
            print("WebSocket connected")
            await indexingState.addSocket(outbound)
            let config = ["type": "config", "data": ["projectName": projectName, "readme": readmeContent]]
            if let configData = try? JSONSerialization.data(withJSONObject: config) { try? await outbound.write(.text(String(data: configData, encoding: .utf8)!)) }

            if let files = try? db.getAllFiles() {
                let response = ["type": "map", "data": files.map { ["path": $0.path] }]
                let responseData = try JSONSerialization.data(withJSONObject: response); try? await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
            }

            if let stats = try? db.getStats() {
                var statsWithData = stats
                let favs = (try? db.getFavorites()) ?? []
                statsWithData["favorites"] = favs.map { ["name": $0.name, "filePath": $0.filePath, "kind": $0.kind, "viewMode": $0.viewMode] }
                let packs = (try? db.getContextPacks()) ?? []
                statsWithData["contextPacks"] = packs.map { ["id": $0.id!, "name": $0.name, "description": $0.description ?? ""] }
                let response = ["type": "stats", "data": statsWithData]
                if let responseData = try? JSONSerialization.data(withJSONObject: response) { try? await outbound.write(.text(String(data: responseData, encoding: .utf8)!)) }
            }

            for try await packet in inbound {
                guard packet.opcode == .text else { continue }
                let string = packet.data.getString(at: packet.data.readerIndex, length: packet.data.readableBytes) ?? ""
                guard let data = string.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = json["type"] as? String else { continue }
                
                do {
                    switch type {
                    case "get_map":
                        let files = try db.getAllFiles()
                        let response = ["type": "map", "data": files.map { ["path": $0.path] }]
                        let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))

                    case "get_stats":
                        var stats = try db.getStats()
                        let favs = try db.getFavorites()
                        let packs = try db.getContextPacks()
                        stats["favorites"] = favs.map { ["name": $0.name, "filePath": $0.filePath, "kind": $0.kind, "viewMode": $0.viewMode] }
                        stats["contextPacks"] = packs.map { ["id": $0.id!, "name": $0.name, "description": $0.description ?? ""] }
                        let response = ["type": "stats", "data": stats]
                        let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))

                    case "reindex": Task { try? await indexer.index(at: ".", delegate: ServerProgressDelegate(state: indexingState)) }

                    case "get_associated_context":
                        if let items = json["items"] as? [[String: String]] {
                            var expandedItems = items, reasons: [String] = []
                            for item in items {
                                let path = item["path"] ?? ""
                                if item["kind"] == "file" {
                                    let internalRefs = try db.getReferencesInFile(path: path)
                                    for ref in internalRefs {
                                        let definitions = try db.getSymbols(qualifiedName: ref.name)
                                        for def in definitions {
                                            if !expandedItems.contains(where: { $0["path"] == def.filePath }) {
                                                expandedItems.append(["path": def.filePath, "kind": "file", "reason": "Defines '\(def.name)' used in staged files"])
                                                reasons.append("Included '\(def.filePath.split(separator: "/").last!)' because it defines '\(def.name)'.")
                                            }
                                        }
                                    }
                                }
                            }
                            let reasoning = reasons.isEmpty ? "No additional associated files found." : Array(Set(reasons)).joined(separator: " ")
                            let response = ["type": "expanded_context", "data": expandedItems, "reasoning": reasoning]
                            let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "get_pack_preview":
                        if let items = json["items"] as? [[String: String]] {
                            let surgicalMode = json["surgicalMode"] as? Bool ?? true
                            var contextText = "# Context Packet\n\n"
                            contextText += "SYSTEM: cckit can find any file or symbol by short name. Full paths below are for reference only.\n\n"
                            
                            for item in items {
                                let path = item["path"] ?? "", kind = item["kind"] ?? "", reason = item["reason"] ?? "Directly Added"
                                let fileName = path.split(separator: "/").last!
                                
                                // Trim to skeletons if in surgical mode OR if it's an associated dependency
                                let isAssociated = reason.contains("Defines") || reason.contains("Included")
                                let shouldTrim = surgicalMode || isAssociated
                                
                                if kind == "file" {
                                    if shouldTrim {
                                        let symbols = try db.getSymbols(path: path)
                                        let skeleton = SwiftOutlineRenderer().render(filePath: path, symbols: symbols)
                                        contextText += "### \(fileName) (SKELETON - \(reason))\n\(skeleton)\n\n"
                                    } else {
                                        if let content = try? String(contentsOfFile: path, encoding: .utf8) { 
                                            contextText += "### \(fileName) (FULL - \(reason))\n```swift\n\(content)\n```\n\n" 
                                        }
                                    }
                                } else if kind == "terminal" {
                                    contextText += "### Terminal Output\n```\n\(item["content"] ?? "")\n```\n\n"
                                } else {
                                    let parts = path.split(separator: "::")
                                    if parts.count == 2 {
                                        let symName = String(parts[0]), symPath = String(parts[1])
                                        if let symbols = try? db.getSymbols(path: symPath), let symbol = symbols.first(where: { $0.qualifiedName == symName }) {
                                            if let content = try? String(contentsOfFile: symbol.filePath, encoding: .utf8) {
                                                let swiftFile = SwiftSourceFile(filePath: symbol.filePath, content: content)
                                                let body = swiftFile.body(for: symbol)
                                                contextText += "### Symbol: \(symName) (\(shouldTrim ? "SKELETON" : "FULL") - \(reason))\n```swift\n\(shouldTrim ? symbol.signature : body)\n```\n\n"
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Use Wax for Estimate
                            let estimate = await wax.estimateComplexity(for: contextText)
                            let response = ["type": "pack_text_preview", "data": contextText, "estimate": estimate]
                            let responseData = try JSONSerialization.data(withJSONObject: response)
                            try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "add_favorite":
                        if let name = json["name"] as? String, let path = json["filePath"] as? String, let kind = json["kind"] as? String, let viewMode = json["viewMode"] as? String {
                            try db.addFavorite(name: name, filePath: path, kind: kind, viewMode: viewMode)
                            let favs = try db.getFavorites(), response = ["type": "favorites_updated", "data": favs.map { ["name": $0.name, "filePath": $0.filePath, "kind": $0.kind, "viewMode": $0.viewMode] }]
                            let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "remove_favorite":
                        if let name = json["name"] as? String, let path = json["filePath"] as? String {
                            try db.removeFavorite(name: name, filePath: path)
                            let favs = try db.getFavorites(), response = ["type": "favorites_updated", "data": favs.map { ["name": $0.name, "filePath": $0.filePath, "kind": $0.kind, "viewMode": $0.viewMode] }]
                            let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "save_context_pack":
                        if let name = json["name"] as? String, let items = json["items"] as? [[String: String]] {
                            let description = json["description"] as? String; try db.saveContextPack(name: name, description: description, items: items)
                            let packs = try db.getContextPacks(), response = ["type": "packs_updated", "data": packs.map { ["id": $0.id!, "name": $0.name, "description": $0.description ?? ""] }]
                            let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }
                    
                    case "get_pack_details":
                        if let id = json["id"] as? Int64 {
                            let items = try db.getContextPackItems(packId: id), response = ["type": "pack_details", "data": items.map { ["path": $0.path, "kind": $0.kind, "reason": $0.reason ?? "Directly Added"] }]
                            let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "delete_context_pack":
                        if let name = json["name"] as? String {
                            try db.deleteContextPack(name: name)
                            let packs = try db.getContextPacks()
                            let response = ["type": "packs_updated", "data": packs.map { ["id": $0.id!, "name": $0.name, "description": $0.description ?? ""] }]
                            let responseData = try JSONSerialization.data(withJSONObject: response)
                            try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "open_file": if let path = json["path"] as? String { let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = [path]; try? process.run() }

                    case "get_file_content": if let path = json["path"] as? String { let content = try String(contentsOfFile: path, encoding: .utf8), response = ["type": "file_content", "data": ["path": path, "content": content]]; let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!)) }

                    case "get_skeleton":
                        if let path = json["path"] as? String {
                            let symbols = try db.getSymbols(path: path), renderer = SwiftOutlineRenderer(), skeleton = renderer.render(filePath: path, symbols: symbols)
                            let response = ["type": "skeleton_content", "data": ["path": path, "content": skeleton]]
                            let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "pack_cart":
                        if let items = json["items"] as? [[String: String]] {
                            var contextText = "# Context Packet\n\n"
                            for item in items {
                                let path = item["path"] ?? "", kind = item["kind"] ?? "", reason = item["reason"] ?? "Directly Added"
                                if kind == "file" { if let content = try? String(contentsOfFile: path, encoding: .utf8) { contextText += "## File: \(path) (Reason: \(reason))\n```swift\n\(content)\n```\n\n" } }
                                else if kind == "terminal" { contextText += "## Terminal Output\n```\n\(item["content"] ?? "")\n```\n\n" }
                                else {
                                    let parts = path.split(separator: "::")
                                    if parts.count == 2 {
                                        let symName = String(parts[0]), symPath = String(parts[1])
                                        if let symbols = try? db.getSymbols(path: symPath), let symbol = symbols.first(where: { $0.qualifiedName == symName }) {
                                            if let content = try? String(contentsOfFile: symbol.filePath, encoding: .utf8) {
                                                let swiftFile = SwiftSourceFile(filePath: symbol.filePath, content: content), body = swiftFile.body(for: symbol)
                                                contextText += "## Symbol: \(symName) (Reason: \(reason))\n```swift\n\(body)\n```\n\n"
                                            }
                                        }
                                    }
                                }
                            }
                            try? contextText.write(toFile: ".cckit/context.md", atomically: true, encoding: .utf8)
                        }

                    case "run_command":
                        if let command = json["command"] as? String {
                            let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = ["-c", command]; process.standardOutput = pipe; process.standardError = pipe
                            do { try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(), output = String(data: data, encoding: .utf8) ?? "No output", response = ["type": "command_output", "data": output]
                                let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!)) }
                            catch { let response = ["type": "command_output", "data": "Failed: \(error.localizedDescription)"]
                                let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!)) }
                        }

                    case "chat_ask":
                        if let text = json["text"] as? String, let contextItems = json["context"] as? [[String: String]] {
                            var contextText = ""
                            for item in contextItems {
                                let path = item["path"] ?? "", kind = item["kind"] ?? ""
                                if kind == "file" { if let content = try? String(contentsOfFile: path, encoding: .utf8) { contextText += "## \(path)\n```swift\n\(content)\n```\n\n" } }
                                else if kind == "terminal" { contextText += "## Terminal Output\n```\n\(item["content"] ?? "")\n```\n\n" }
                                else {
                                    let parts = path.split(separator: "::")
                                    if parts.count == 2 {
                                        let symName = String(parts[0]), symPath = String(parts[1])
                                        if let symbols = try? db.getSymbols(path: symPath), let symbol = symbols.first(where: { $0.qualifiedName == symName }) {
                                            if let content = try? String(contentsOfFile: symbol.filePath, encoding: .utf8) {
                                                let swiftFile = SwiftSourceFile(filePath: symbol.filePath, content: content), body = swiftFile.body(for: symbol)
                                                contextText += "## Symbol: \(symName)\n```swift\n\(body)\n```\n\n"
                                            }
                                        }
                                    }
                                }
                            }
                            let prompt = "You are a helpful AI coding assistant examining the user's provided context.\n\nCONTEXT:\n\(contextText)\n\nUSER QUESTION:\n\(text)", reply: String
                            if #available(macOS 26.0, *) {
                                #if canImport(FoundationModels)
                                do { let session = LanguageModelSession(), modelResponse = try await session.respond(to: prompt); reply = modelResponse.content.trimmingCharacters(in: .whitespacesAndNewlines) } catch { reply = "Model failed: \(error)" }
                                #else
                                reply = "FoundationModels framework not imported."
                                #endif
                            } else { reply = "On-device AI summarization requires macOS 26.0+." }
                            let response = ["type": "chat_reply", "data": reply], responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "generate_summary":
                        if let name = json["name"] as? String, let signature = json["signature"] as? String, let filePath = json["file"] as? String {
                            let symbols = try db.getSymbols(path: filePath), symbol = symbols.first(where: { $0.qualifiedName == name }) ?? symbols.first
                            var body = ""
                            if let found = symbol { if let content = try? String(contentsOfFile: found.filePath, encoding: .utf8) { let swiftFile = SwiftSourceFile(filePath: found.filePath, content: content); body = swiftFile.body(for: found) } }
                            let renderer = SwiftOutlineRenderer(), skeleton = renderer.render(filePath: filePath, symbols: symbols), summary: String
                            if #available(macOS 26.0, *) { summary = try await self.generateAISummary(name: name, signature: signature, body: body, skeleton: skeleton, packageGoal: readmeContent.prefix(1000).description, projectName: projectName, file: filePath) }
                            else { summary = "On-device AI summarization requires macOS 26.0 or newer." }
                            let response = ["type": "generated_summary", "data": ["name": name, "summary": summary]], responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "grep":
                        if let patterns = json["patterns"] as? [String] {
                            let indexedFiles = try db.getAllFiles()
                            var results: [[String: Any]] = []
                            for file in indexedFiles {
                                guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else { continue }
                                let lines = content.components(separatedBy: .newlines)
                                for pattern in patterns {
                                    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                                    for (index, line) in lines.enumerated() {
                                        let range = NSRange(location: 0, length: line.utf16.count)
                                        if regex.firstMatch(in: line, options: [], range: range) != nil { results.append(["file": file.path, "line": index + 1, "content": line.trimmingCharacters(in: .whitespaces), "pattern": pattern]) }
                                    }
                                }
                                if results.count > 500 { break }
                            }
                            let response = ["type": "grep_results", "data": results], responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }

                    case "search":
                        if let query = json["query"] as? String {
                            var results: [String: Any] = [:]
                            
                            // 1. Semantic Matches
                            let semanticQuery = query.hasPrefix("semantic:") ? String(query.dropFirst(9)) : query
                            let waxResults = try await wax.search(semanticQuery, limit: 8)
                            var semanticMatches: [[String: Any]] = []
                            for res in waxResults {
                                if let sym = try db.getSymbols(qualifiedName: res.symbol).first {
                                    semanticMatches.append([
                                        "symbol": sym.qualifiedName,
                                        "file": sym.filePath,
                                        "kind": "\(sym.kind)",
                                        "score": Double(res.score),
                                        "refCount": (try? db.getReferenceCount(forSymbolName: sym.name)) ?? 0
                                    ])
                                }
                            }
                            results["semanticMatches"] = semanticMatches
                            
                            // 2. File Matches
                            let files = try db.getFilesLike(pattern: query.replacingOccurrences(of: "semantic:", with: ""))
                            results["files"] = files.prefix(10).map { ["path": $0.path, "language": $0.language] }

                            // 3. Exact/Symbol Matches
                            let symbols = try db.getSymbolsLike(name: query.replacingOccurrences(of: "semantic:", with: ""))
                            results["symbols"] = symbols.prefix(10).map { [
                                "symbol": $0.qualifiedName,
                                "file": $0.filePath,
                                "kind": "\($0.kind)",
                                "refCount": (try? db.getReferenceCount(forSymbolName: $0.name)) ?? 0
                            ] }
                            
                            // 4. Literal Text Matches (Grep logic)
                            let indexedFiles = try db.getAllFiles()
                            var textMatches: [[String: Any]] = []
                            let pattern = NSRegularExpression.escapedPattern(for: query.replacingOccurrences(of: "semantic:", with: ""))
                            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                                for file in indexedFiles {
                                    guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else { continue }
                                    let lines = content.components(separatedBy: .newlines)
                                    for (index, line) in lines.enumerated() {
                                        let range = NSRange(location: 0, length: line.utf16.count)
                                        if regex.firstMatch(in: line, options: [], range: range) != nil {
                                            textMatches.append(["file": file.path, "line": index + 1, "content": line.trimmingCharacters(in: .whitespaces)])
                                            break // One per file for summary
                                        }
                                    }
                                    if textMatches.count > 10 { break }
                                }
                            }
                            results["textMatches"] = textMatches
                            
                            let response = ["type": "search_results", "data": results]
                            let responseData = try JSONSerialization.data(withJSONObject: response)
                            try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                        }
                        
                    case "get_symbol":
                        if let name = json["name"] as? String {
                            let filePath = json["filePath"] as? String, symbols = try db.getSymbols(qualifiedName: name), symbol = filePath != nil && !filePath!.isEmpty ? symbols.first(where: { $0.filePath == filePath }) : symbols.first
                            if let found = symbol {
                                let content = try String(contentsOfFile: found.filePath, encoding: .utf8), swiftFile = SwiftSourceFile(filePath: found.filePath, content: content)
                                let body = swiftFile.body(for: found), refs = try db.getReferences(forSymbolName: found.name)
                                let response: [String: Any] = ["type": "symbol_detail", "data": ["name": found.name, "qualifiedName": found.qualifiedName, "kind": "\(found.kind)", "signature": found.signature, "filePath": found.filePath, "docComment": found.docComment ?? "", "body": body, "references": refs.map { ["name": $0.name, "startLine": $0.startLine, "context": $0.context ?? "", "file": $0.file ?? found.filePath] }]]
                                let responseData = try JSONSerialization.data(withJSONObject: response); try await outbound.write(.text(String(data: responseData, encoding: .utf8)!))
                            }
                        }
                    default: break
                    }
                } catch { print("Error handling message type \(type): \(error)") }
            }
            print("WebSocket disconnected")
        }
        let app = Application(router: router, server: .http1WebSocketUpgrade(webSocketRouter: router), configuration: .init(address: .hostname("127.0.0.1", port: self.port)), logger: self.logger)
        try await app.runService()
    }

    @available(macOS 26.0, *)
    private func generateAISummary(name: String, signature: String, body: String, skeleton: String, packageGoal: String, projectName: String, file: String) async throws -> String {
        #if canImport(FoundationModels)
        let prompt = "You are an expert Swift software architect. Analyze the following symbol from project '\(projectName)'.\n\nPROJECT GOAL:\n\(packageGoal)\n\nFILE CONTEXT (SKELETON):\n\(skeleton)\n\nTARGET SYMBOL:\nNAME: \(name)\nSIGNATURE: \(signature)\n\nIMPLEMENTATION:\n\(body)\n\nWrite a concise, professional 2-3 sentence documentation summary for this symbol. Focus on how it contributes to the file's architecture and the overall project goals. Do not use preambles like \"This function is\". Start directly with the description."
        do { let session = LanguageModelSession(), response = try await session.respond(to: prompt); return response.content.trimmingCharacters(in: .whitespacesAndNewlines) }
        catch { print("Apple Foundation Model failed: \(error)"); return fallbackSummary(name: name, signature: signature, file: file, projectName: projectName) }
        #else
        return fallbackSummary(name: name, signature: signature, file: file, projectName: projectName)
        #endif
    }
    private func fallbackSummary(name: String, signature: String, file: String, projectName: String) -> String { return "Provides core functionality for '\(name)' within the \(projectName) project. Handles logic related to \(signature.contains("func") ? "the implementation of this function" : "this type definition") in the context of \(file)." }
}

struct ServerProgressDelegate: IndexerProgressDelegate {
    let state: IndexingState
    func indexerDidStart(totalFiles: Int) { Task { await state.start(total: totalFiles); await state.broadcast(["type": "indexing_start", "total": totalFiles]) } }
    func indexerDidProgress(completedFiles: Int, totalFiles: Int, currentFile: String) { Task { await state.update(completed: completedFiles, currentFile: currentFile); await state.broadcast(["type": "indexing_progress", "completed": completedFiles, "total": totalFiles, "file": currentFile]) } }
    func indexerDidFinish(updated: Int, skipped: Int, totalSymbols: Int) { Task { await state.finish(); await state.broadcast(["type": "indexing_finish", "updated": updated, "skipped": skipped, "symbols": totalSymbols]) } }
    func indexerDidFail(error: Error) { Task { await state.finish(); await state.broadcast(["type": "indexing_error", "error": error.localizedDescription]) } }
}
