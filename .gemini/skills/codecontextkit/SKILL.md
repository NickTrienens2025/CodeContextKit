---
name: codecontextkit
description: Use CodeContextKit to index Swift repositories, extract context packets under a token budget, and semantically search for symbols.
---

# CodeContextKit Skill

This skill provides instructions for using CodeContextKit (`cckit`) to efficiently understand, search, and extract context from Swift repositories. When you need to understand a Swift repository, find relevant symbols, or gather context for a complex task without blowing out your token window, use `cckit`.

## Workflow

When investigating or solving a complex issue in a Swift repository, follow these steps:

### 1. Index the Repository

Before using any other commands, you must index the repository. This extracts all symbols, types, and references and builds the exact SQLite index and semantic Wax index.

```bash
swift run cckit index .
```

If you suspect the index is out of date and incremental indexing isn't picking up changes properly, use the `--clean` flag:

```bash
swift run cckit index . --clean
```

### 2. Search for Symbols

Use the semantic search to find symbols related to your task. This uses hybrid retrieval (exact matches + semantic embedding/text matches via Wax).

```bash
swift run cckit search "authentication retry logic"
```

To limit the results:

```bash
swift run cckit search "authentication retry logic" --limit 5
```

### 3. Generate a Context Packet

When you have a specific task to solve (e.g., fixing a bug or adding a feature), generate a "context packet". This command automatically pulls a high-level repository map, relevant symbols based on your task description, and any provided failure logs, packing them tightly into a single Markdown file under a specified token budget.

```bash
swift run cckit pack --task "Fix token refresh failing tests" --budget 12000 --output .cckit/context.md
```

If you have a failure log (e.g., from a test run or compilation error), include it so `cckit` can extract relevant errors:

```bash
swift run cckit pack --task "Fix token refresh failing tests" --failure build.log --budget 12000 --output .cckit/context.md
```

After packing, **read** the resulting file (e.g., `.cckit/context.md`) to get the concentrated, high-signal context needed for your work without blindly reading dozens of individual files.

### 4. Direct Retrieval

If you already know the exact symbol or file you need structural details on:

**To get an exact symbol and its body:**
```bash
swift run cckit symbol "APIClient.send"
```

**To get the structural outline of a file:**
```bash
swift run cckit outline Sources/Auth/APIClient.swift
```

## Best Practices

- Always prefer `cckit pack` for getting the initial lay of the land for a task, as it respects token budgets and pulls only what's necessary.
- If you run into token limits or your context gets too large, utilize `swift run cckit map --budget 4000` to get a bird's eye view instead of reading full files.
- `cckit` caches file hashes, so `swift run cckit index .` is extremely fast on subsequent runs. Run it frequently after making substantial code changes.
