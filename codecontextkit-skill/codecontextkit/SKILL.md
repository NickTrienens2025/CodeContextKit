---
name: codecontextkit
description: Use CodeContextKit to index Swift repositories, perform semantic search, manage staging carts, and extract surgical context packets under a token budget.
---

# CodeContextKit Skill

This skill provides instructions for using CodeContextKit (`cckit`) to efficiently understand, search, and extract context from Swift repositories. When you need to understand a Swift repository, find relevant symbols, or gather context for a complex task without blowing out your token window, use `cckit`.

## Workflow

When investigating or solving a complex issue in a Swift repository, follow these steps:

### 1. Index the Repository

Before using any other commands, you must index the repository. This extracts symbols, types, and references and builds both the SQLite index and the Semantic (Wax) vector store.

```bash
swift run cckit index .
```

### 2. Unified Discovery (Search)

Use `cckit search` for all your discovery needs. It intelligently combines symbol lookups, literal text matching (grep), and semantic meaning.

**Keyword/Symbol Search:**
```bash
swift run cckit search "APIClient"
```

**Regex Search:**
```bash
swift run cckit search --regex "func .*Init"
```

**Semantic (Meaning) Search:**
Prefix with `semantic:` to use the Wax vector engine.
```bash
swift run cckit search "semantic: user authentication and token refresh logic"
```

### 3. Generate a Surgical Context Packet

When you have a specific task, generate a "context packet". This command automatically pulls a high-level repository map and relevant symbols under a specified token budget.

```bash
swift run cckit pack --task "Fix database deadlocks in GRDB writer" --budget 12000
```

### 4. Interactive Visualizer & Context Staging

Launch the web-based visualizer to use the **Context Cart** for fine-grained staging of code for AI.

```bash
swift run cckit serve
```

**Key Visualizer Features:**
- **🛒 Context Cart**: Manually add files and symbols to a staging area.
- **🧠 Auto-Expand**: Automatically pull in defining files for symbols used in your staged context.
- **💬 Local AI Chat**: Ask questions about your staged files using Apple's on-device Foundation Models.
- **🖥️ Terminal Runner**: Run tests directly and append failure logs to your context packet with one click.
- **💾 Context Packs**: Save and reload specific staging states for long-running tasks.

### 5. Direct Retrieval

**To get an exact symbol and its body:**
```bash
swift run cckit symbol "CodeContextServer.run"
```

**To get the structural outline (skeleton) of a file:**
```bash
swift run cckit outline Sources/CodeContextKitServer/Server.swift
```

## Best Practices

- **Surgical Retrieval**: Use `cckit outline` to understand structure before requesting the full body with `cckit symbol`.
- **Cart-First Staging**: When using the visualizer, build a "Context Pack" first to ensure the AI isn't overwhelmed by irrelevant files.
- **Grounding Chat**: Use the "Ask AI" tab after staging your relevant files in the cart for more grounded answers.
- **Privacy**: No code ever leaves your machine; indexing and AI summarization happen locally.
