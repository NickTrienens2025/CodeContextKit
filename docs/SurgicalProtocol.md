# The Surgical Agentic Protocol (v1.0)

This protocol mandates **Extreme Context Efficiency** for all tool-calling cycles. To avoid "State Bloat" and the "Context Window Wall," the following architectural mandates are enforced:

## 1. The "Thin Core" Mandate
*   **Main Context Limit:** The primary agent context MUST stay under 10k tokens for the duration of the task.
*   **Offloading:** Any task expected to return >500 tokens of output (e.g., `grep`, `ls -R`, `swift build`) MUST be offloaded to a **Sub-Agent** or a **Background Process**.
*   **Observation Pruning:** Never append raw tool outputs directly to the main history. Instead, summarize the high-signal result (e.g., "Grep found 15 matches; relevant ones are in Database.swift:12 and User.swift:45").

## 2. Bash Tool-Chain Optimization
*   **Surgical Reads:** NEVER use `cat` or `read_file` on files >100 lines. Use `cckit symbol` or `cckit outline` to understand structure first.
*   **Redirection:** Redirect massive tool outputs to temporary files (`> /tmp/output.log`) and use `grep` or `tail` to extract only the error or relevant line.
*   **Silent Flags:** Always use silent/quiet flags (e.g., `npm install --silent`, `curl -s`) to prevent stdout noise from polluting the context.

## 3. The "Small Fail-Safe" Mechanism
When a tool call fails or a "cold start" occurs (e.g., context truncation), use this minimal recovery packet:
1.  **Run `cckit map --budget 500 --focus [task]`**: This provides a 500-token high-level skeleton of the relevant architecture.
2.  **Locate "Anchors"**: Identify the 2-3 core types involved in the failure.
3.  **Expand Surgically**: Use `cckit symbol` only for the specific failing functions.

## 4. Ephemeral State Management (The Working Memory)
*   **Memory Files:** Use `MEMORY.md` to track the *current plan* and *key facts*.
*   **State Reset:** If the context exceeds 20k tokens, the agent MUST summarize the `MEMORY.md`, record the current progress, and trigger a "Context Refresh" (starting a new turn with only the summary and the surgical map).

## 5. Decision Tree for Context Elevation
*   **Level 0 (File Name only):** For non-matching dependencies.
*   **Level 1 (Signatures only):** For understanding "What can this module do?"
*   **Level 2 (Full Body):** ONLY for the specific lines of code being modified.

---
*INJECT THIS INTO CCKit CLI START COMMAND:*
`"mandate": "Operate under the Surgical Agentic Protocol. Prioritize subagent offloading for all noisy bash toolchains. Keep primary context thin (<10k)."`
