import Foundation

public struct FileScanner {
    public init() {}
    
    public func scan(at path: String, include: [String], exclude: [String], includeFolders: [String] = []) -> [URL] {
        let rootURL = URL(fileURLWithPath: path)
        var results: [URL] = []
        let rules = IgnoreRules(rootURL: rootURL, exclude: exclude, includeFolders: includeFolders)
        
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                let relativePath = relativePath(for: fileURL, rootURL: rootURL)

                if resourceValues.isDirectory == true {
                    if rules.shouldSkipDirectory(path: relativePath) {
                        enumerator?.skipDescendants()
                    }
                } else if resourceValues.isRegularFile == true {
                    if shouldInclude(path: relativePath, include: include, rules: rules) {
                        results.append(fileURL)
                    }
                }
            } catch {
                continue
            }
        }
        
        return results
    }
    
    private func shouldInclude(path: String, include: [String], rules: IgnoreRules) -> Bool {
        if rules.excludesFile(path: path) { return false }
        if rules.isIncluded(path: path) { return hasSupportedExtension(path) }
        
        if include.isEmpty {
            return hasSupportedExtension(path)
        }
        
        for pattern in include {
            if path.contains(pattern) { return true }
        }
        
        return false
    }

    private func hasSupportedExtension(_ path: String) -> Bool {
        let supportedExtensions = [
            "swift", "h", "m", "mm", "c", "cpp", "hpp", "js", "ts", "json", "md", "yaml", "yml", "skill", "html", "css"
        ]
        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    private func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.resolvingSymlinksInPath().path
        let filePath = url.resolvingSymlinksInPath().path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }

        var relativePath = String(filePath.dropFirst(rootPath.count))
        if relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }
        return relativePath
    }
}

private struct IgnoreRules {
    private let defaultRules: [IgnoreRule]
    private let gitignoreRules: [IgnoreRule]
    private let excludeRules: [IgnoreRule]
    private let includeRules: [IgnoreRule]

    init(rootURL: URL, exclude: [String], includeFolders: [String]) {
        let defaultRules = [".build/", ".git/", "DerivedData/", "node_modules/", ".DS_Store"]
        let gitignoreRules = Self.loadGitignoreRules(rootURL: rootURL)
        self.defaultRules = defaultRules.compactMap(IgnoreRule.init)
        self.gitignoreRules = gitignoreRules.compactMap(IgnoreRule.init)
        self.excludeRules = exclude.compactMap(IgnoreRule.init)
        self.includeRules = includeFolders.compactMap(IgnoreRule.init)
    }

    func shouldSkipDirectory(path: String) -> Bool {
        if defaultRules.contains(where: { $0.matches(path: path, isDirectory: true) }) { return true }
        if excludeRules.contains(where: { $0.matches(path: path, isDirectory: true) }) { return true }
        if isIncluded(path: path) || containsIncludedDescendant(path: path) { return false }
        return gitignoreRules.contains { $0.matches(path: path, isDirectory: true) }
    }

    func excludesFile(path: String) -> Bool {
        if defaultRules.contains(where: { $0.matches(path: path, isDirectory: false) }) { return true }
        if excludeRules.contains(where: { $0.matches(path: path, isDirectory: false) }) { return true }
        if isIncluded(path: path) { return false }
        return gitignoreRules.contains { $0.matches(path: path, isDirectory: false) }
    }

    func isIncluded(path: String) -> Bool {
        includeRules.contains { $0.matches(path: path, isDirectory: false) || $0.matches(path: path, isDirectory: true) }
    }

    private func containsIncludedDescendant(path: String) -> Bool {
        includeRules.contains { $0.isDescendant(of: path) }
    }

    private static func loadGitignoreRules(rootURL: URL) -> [String] {
        let gitignoreURL = rootURL.appendingPathComponent(".gitignore")
        guard let content = try? String(contentsOf: gitignoreURL, encoding: .utf8) else {
            return []
        }

        return content.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("!") else {
                return nil
            }
            return trimmed
        }
    }
}

private struct IgnoreRule {
    private let pattern: String
    private let requiresDirectory: Bool
    private let anchored: Bool

    init?(_ rawPattern: String) {
        var pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }

        self.anchored = pattern.hasPrefix("/")
        if pattern.hasPrefix("/") {
            pattern.removeFirst()
        }

        self.requiresDirectory = pattern.hasSuffix("/")
        if pattern.hasSuffix("/") {
            pattern.removeLast()
        }

        guard !pattern.isEmpty else { return nil }
        self.pattern = pattern
    }

    func matches(path: String, isDirectory: Bool) -> Bool {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedPath.isEmpty else { return false }

        if requiresDirectory && !isDirectory {
            let isDescendantFile = normalizedPath.hasPrefix(pattern + "/") || normalizedPath.contains("/\(pattern)/")
            if !isDescendantFile { return false }
        }

        if pattern.contains("*") {
            return globMatches(path: normalizedPath)
        }

        if anchored || pattern.contains("/") {
            return normalizedPath == pattern || normalizedPath.hasPrefix(pattern + "/")
        }

        let components = normalizedPath.split(separator: "/").map(String.init)
        if components.contains(pattern) { return true }

        return normalizedPath == pattern || normalizedPath.hasSuffix("/" + pattern)
    }

    func isDescendant(of path: String) -> Bool {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedPath.isEmpty else { return false }

        if anchored || pattern.contains("/") {
            return pattern.hasPrefix(normalizedPath + "/")
        }

        return false
    }

    private func globMatches(path: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*\\*", with: ".*")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
        let prefix = anchored || pattern.contains("/") ? "^" : "(^|.*/)"
        let suffix = requiresDirectory ? "(/.*)?$" : "(/.*)?$"
        let regexPattern = prefix + escaped + suffix
        return path.range(of: regexPattern, options: .regularExpression) != nil
    }
}
