import Foundation

public struct Config {
    public static let surgicalAgenticProtocol = """
    # The Surgical Agentic Protocol (v1.0)
    
    ## 1. The "Thin Core" Mandate
    *   **Main Context Limit:** Stay under 10k tokens.
    *   **Offloading:** Task output >500 tokens MUST be offloaded to a Sub-Agent or Background Process.
    *   **Observation Pruning:** Summarize tool outputs; never append raw tool dumps.
    
    ## 2. Bash Tool-Chain Optimization
    *   **Surgical Reads:** NEVER 'cat' files >100 lines. Use 'cckit symbol' or 'cckit outline'.
    *   **Redirection:** Redirect massive tool outputs to '/tmp/output.log' and grep/tail the result.
    *   **Silent Flags:** Use silent/quiet flags to prevent stdout noise.
    
    ## 3. The "Small Fail-Safe" Mechanism
    *   On failure: Run 'cckit map --budget 500 --focus [task]' to recover architectural context.
    
    ## 4. Ephemeral State Management
    *   Use 'MEMORY.md' to track plans and key facts.
    *   Refresh context if tokens >20k by summarizing progress and restarting turn.
    """

    public init() {}
}

public struct ProjectSettings: Codable, Sendable {
    public var excludedFolders: [String]
    public var includedFolders: [String]

    public init(excludedFolders: [String] = [], includedFolders: [String] = []) {
        self.excludedFolders = excludedFolders
        self.includedFolders = includedFolders
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.excludedFolders = try container.decodeIfPresent([String].self, forKey: .excludedFolders) ?? []
        self.includedFolders = try container.decodeIfPresent([String].self, forKey: .includedFolders) ?? []
    }

    public static func load(projectRoot: String = ".") -> ProjectSettings {
        let url = settingsURL(projectRoot: projectRoot)
        guard let data = try? Data(contentsOf: url) else {
            return ProjectSettings()
        }

        return (try? JSONDecoder().decode(ProjectSettings.self, from: data)) ?? ProjectSettings()
    }

    public func save(projectRoot: String = ".") throws {
        let url = Self.settingsURL(projectRoot: projectRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func settingsURL(projectRoot: String = ".") -> URL {
        URL(fileURLWithPath: projectRoot)
            .resolvingSymlinksInPath()
            .appendingPathComponent(".cckit")
            .appendingPathComponent("config.json")
    }
}
