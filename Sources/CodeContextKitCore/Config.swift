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
