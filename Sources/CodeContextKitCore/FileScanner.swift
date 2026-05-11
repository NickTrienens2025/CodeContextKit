import Foundation

public struct FileScanner {
    public init() {}
    
    public func scan(at path: String, include: [String], exclude: [String]) -> [URL] {
        let rootURL = URL(fileURLWithPath: path)
        var results: [URL] = []
        
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                    
                    if shouldInclude(path: relativePath, include: include, exclude: exclude) {
                        results.append(fileURL)
                    }
                }
            } catch {
                continue
            }
        }
        
        return results
    }
    
    private func shouldInclude(path: String, include: [String], exclude: [String]) -> Bool {
        // Default excludes
        let defaultExcludes = [".build/", ".git/", "DerivedData/", "node_modules/", ".DS_Store"]
        for pattern in defaultExcludes {
            if path.contains(pattern) { return false }
        }
        
        for pattern in exclude {
            if path.contains(pattern) { return false }
        }
        
        if include.isEmpty {
            let supportedExtensions = [
                "swift", "h", "m", "mm", "c", "cpp", "hpp", "js", "ts", "json", "md", "yaml", "yml", "skill", "html", "css"
            ]
            let ext = (path as NSString).pathExtension.lowercased()
            return supportedExtensions.contains(ext)
        }
        
        for pattern in include {
            if path.contains(pattern) { return true }
        }
        
        return false
    }
}
