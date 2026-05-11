# CodeContextKit Swift CLI — Codex Implementation Plan

## Goal

Build **CodeContextKit**, exposed as the short CLI executable `cckit`, a Swift Package Manager CLI intended to be installable with Mint. The first version focuses on token-efficient repository understanding for Swift codebases, using function/type names as primary retrieval atoms and Wax as a local RAG/memory layer.

The CLI should help a coding agent or developer answer:

- What is this repo?
- Which symbols matter for this task?
- What is the cheapest sufficient context packet for an LLM?
- What expensive files/logs/generated sources were avoided?

This is not a coding agent in v1. It is a repo-understanding, context-packing, and token-estimation tool that can later wrap Aider, Claude Code, Codex, OpenCode, or other agents.

This plan explicitly borrows useful product ideas from CodeGraphContext while keeping CodeContextKit Swift-first and local-first: graph indexing, caller/callee analysis, dead-code/complexity inspection, MCP readiness, and visual graph exploration. CodeGraphContext is Python/tree-sitter/multi-language; CodeContextKit starts with SwiftSyntax and Swift repositories, then can broaden later.

---

## Non-goals for v1

Do not build these initially:

- A full chat agent.
- Automatic code editing.
- Multi-provider LLM gateway.
- Full semantic code analysis/type checking.
- Perfect cross-language support.
- Shell command execution policy.
- Real-time provider token interception.

The first milestone should work fully offline on a Swift repo and produce useful Markdown/JSON context packets.

---

## Core Product Thesis

Agentic coding often wastes tokens because the agent reads too much source, repeats file reads, sends raw build logs, and lacks a compact structural view of the repo.

`cckit` should index the repo cheaply, retrieve by exact symbols and semantic queries, and emit context packets under a token budget.

The main output should always make savings visible:

```text
Context packet: 9,820 tokens

Included:
- repo map excerpt: 3,200 tokens
- failing test summary: 500 tokens
- APIClient.send: 2,800 tokens
- TokenProvider protocol: 900 tokens

Excluded:
- full build log: 82,000 tokens
- generated API models: 44,000 tokens
- unrelated UI module: 18,000 tokens

Estimated savings vs naive inclusion: 91%
```

---

## External Libraries

Use Swift Package Manager.

Required dependencies:

- `swift-argument-parser` for the CLI command tree.
- `swift-syntax` / `SwiftParser` for Swift source parsing.
- `Wax` for local RAG/search/memory.
- `GRDB.swift` or SQLite wrapper for exact symbol metadata and cache state.
- `CryptoKit` from Foundation stack for content hashing.

Optional later dependencies:

- tokenizer library or local token estimator.
- OpenTelemetry/OpenInference exporter.
- tree-sitter for non-Swift language support.

---

## Target Package Layout

```text
Package.swift
Sources/
  CodeContextKitCLI/
    main.swift
    Commands/
      IndexCommand.swift
      OutlineCommand.swift
      SymbolCommand.swift
      SearchCommand.swift
      MapCommand.swift
      PackCommand.swift
      EstimateCommand.swift
      ExplainCommand.swift

  CodeContextKitCore/
    Config.swift
    FileHasher.swift
    FileScanner.swift
    PathFilters.swift
    TokenEstimator.swift
    TextFile.swift
    Diagnostics.swift

  CodeContextKitSwiftIndex/
    SwiftSymbolVisitor.swift
    SwiftOutlineRenderer.swift
    SwiftSourceFile.swift
    SwiftChunker.swift
    LineMap.swift

  CodeContextKitStorage/
    Database.swift
    Migrations.swift
    FileRecord.swift
    SymbolRecord.swift
    ChunkRecord.swift
    SearchRecord.swift

  CodeContextKitRetrieval/
    WaxStore.swift
    HybridSearch.swift
    SearchRanker.swift
    QueryPlanner.swift

  CodeContextKitContext/
    RepoMapBuilder.swift
    ContextPacker.swift
    ContextPacket.swift
    ContextAttribution.swift
    MarkdownRenderer.swift
    JSONRenderer.swift

Tests/
  CodeContextKitSwiftIndexTests/
  CodeContextKitContextTests/
  CodeContextKitStorageTests/
```

---

## SwiftPM Manifest Requirements

The package must define an executable product named `cckit` so Mint can install/run it.

Initial `Package.swift` shape:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodeContextKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "cckit", targets: ["CodeContextKitCLI"]),
        .library(name: "CodeContextKitCore", targets: ["CodeContextKitCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.1"),
        .package(url: "https://github.com/christopherkarani/Wax.git", branch: "main"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "CodeContextKitCLI",
            dependencies: [
                "CodeContextKitCore",
                "CodeContextKitSwiftIndex",
                "CodeContextKitStorage",
                "CodeContextKitRetrieval",
                "CodeContextKitContext",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "CodeContextKitCore"
        ),
        .target(
            name: "CodeContextKitSwiftIndex",
            dependencies: [
                "CodeContextKitCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .target(
            name: "CodeContextKitStorage",
            dependencies: [
                "CodeContextKitCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "CodeContextKitRetrieval",
            dependencies: [
                "CodeContextKitCore",
                "CodeContextKitStorage",
                .product(name: "Wax", package: "Wax")
            ]
        ),
        .target(
            name: "CodeContextKitContext",
            dependencies: [
                "CodeContextKitCore",
                "CodeContextKitSwiftIndex",
                "CodeContextKitStorage",
                "CodeContextKitRetrieval"
            ]
        ),
        .testTarget(
            name: "CodeContextKitSwiftIndexTests",
            dependencies: ["CodeContextKitSwiftIndex"]
        ),
        .testTarget(
            name: "CodeContextKitContextTests",
            dependencies: ["CodeContextKitContext"]
        )
    ]
)
```

If Wax product names differ, inspect Wax’s `Package.swift` and adjust the product references.

---

## CLI Command Surface

### `cckit index`

Indexes a repository.

Examples:

```bash
cckit index .
cckit index --clean
cckit index --include "Sources/**/*.swift" --exclude "**/*.generated.swift"
cckit index --stats
```

Responsibilities:

1. Scan files.
2. Filter ignored/generated/binary files.
3. Hash files.
4. Parse Swift files.
5. Extract symbol records.
6. Generate file outlines.
7. Write exact metadata to SQLite.
8. Write searchable symbol/outline documents to Wax.
9. Print summary stats.

Acceptance criteria:

- Can index a small Swift package.
- Skips `.build`, `.git`, `DerivedData`, `node_modules`, generated files, and binary files.
- Re-running index only updates changed files.
- Prints number of files, Swift files, symbols, functions, types, tests, skipped files.

---

### `cckit outline`

Prints a structural outline of a Swift file.

Example:

```bash
cckit outline Sources/Auth/APIClient.swift
```

Expected output:

```text
Sources/Auth/APIClient.swift

import Foundation

struct APIClient
  let baseURL: URL
  let tokenProvider: TokenProvider

  init(baseURL: URL, tokenProvider: TokenProvider)
  func send<T: Decodable>(_ request: APIRequest) async throws -> T
  private func refreshAndRetry<T: Decodable>(_ request: APIRequest) async throws -> T
```

Acceptance criteria:

- Shows imports.
- Shows types and members.
- Shows function signatures without full bodies.
- Preserves nesting enough to distinguish type members.

---

### `cckit symbol`

Retrieves a symbol by exact or fuzzy name.

Examples:

```bash
cckit symbol APIClient.send
cckit symbol "AuthRefreshTests.testRetriesAfter401"
cckit symbol --json APIClient.send
```

Output should include:

- qualified symbol name
- kind
- file path
- line range
- signature
- enclosing type
- body text
- estimated tokens

Acceptance criteria:

- Exact match works.
- If multiple symbols match, show candidates and exit with non-zero unless `--first` is passed.
- JSON mode returns machine-readable records.

---

### `cckit search`

Hybrid retrieval over exact symbol names and Wax semantic/text search.

Examples:

```bash
cckit search "401 retry auth token refresh"
cckit search --kind function "refresh token"
cckit search --json "where is playback state updated"
```

Ranking signals:

1. exact symbol/name match
2. file/path match
3. lexical text match
4. Wax retrieval score
5. test-name boost
6. changed-file boost when `--changed` is provided
7. proximity to matching type/function names

Acceptance criteria:

- Returns top results with file, symbol, kind, short preview, score, token estimate.
- Supports `--limit`.
- Supports `--json`.

---

### `cckit map`

Builds an Aider-style repo map under a token budget.

Examples:

```bash
cckit map --budget 4096
cckit map --focus "auth token refresh" --budget 6000
cckit map --changed --base main
```

The map should prefer:

- symbols matching task/focus terms
- changed files
- test files related to focus terms
- public protocols/types
- entrypoint files
- files with many references/callers

Acceptance criteria:

- Produces a compact text map.
- Stays within approximate token budget.
- Prints estimated token count.
- Output is deterministic given the same index and arguments.

---

### `cckit pack`

Creates a model-ready context packet.

Examples:

```bash
cckit pack --task "fix AuthRefreshTests.testRetriesAfter401" --budget 12000 --output context.md
cckit pack --task "understand auth module" --budget 8000 --format json
cckit pack --task "fix failing tests" --failure build.log --budget 12000
```

Context packet sections:

1. Task
2. Token budget and estimated size
3. Included context summary
4. Optional failure summary
5. Repo map excerpt
6. Selected symbols/functions/types
7. Selected file outlines
8. Excluded expensive context
9. Suggested next retrieval commands

Acceptance criteria:

- Generates Markdown by default.
- Supports JSON output.
- Explains why each included item was selected.
- Shows token estimate per included section.
- Shows excluded high-cost sources.

---

### `cckit estimate`

Estimates token count and optionally cost for a file/context packet.

Examples:

```bash
cckit estimate context.md
cckit estimate context.md --model claude-sonnet
cckit estimate --text "hello world"
```

Acceptance criteria:

- Provides approximate token count.
- Supports configurable model pricing via `.cckit.yaml`.
- Does not require network access.

---

### `cckit explain`

Explains stored index/context state.

Examples:

```bash
cckit explain index
cckit explain pack context.md
cckit explain symbol APIClient.send
```

Acceptance criteria:

- Useful debugging for why context was included/excluded.
- Shows ranking factors when possible.

---

### `cckit visualize`

Starts a local web visualizer or exports a standalone graph HTML file. This is inspired by CodeGraphContext's interactive web-based graph explorers, but the v1 design should favor a live local server with WebSocket updates so indexing changes can stream into the browser.

Examples:

```bash
cckit visualize
cckit visualize --port 8787
cckit visualize --focus "auth token refresh"
cckit visualize --export graph.html
cckit visualize --watch
```

Initial UI requirements:

1. Serve a local HTML app from the CLI.
2. Open browser automatically unless `--no-open` is passed.
3. Provide WebSocket endpoint `/ws` for graph updates.
4. Show nodes for files, types, functions, protocols, tests, and modules.
5. Show edges for contains, imports, calls, conforms-to, extends, tests, and references.
6. Include a side panel for selected node metadata: symbol name, kind, file path, line range, signature, token estimate, and related `cckit` commands.
7. Include live search by symbol, file path, and free-text query.
8. Include layout modes: force-directed, hierarchical, dependency tree, and call-chain view.
9. Include filters: node kind, test-only, changed-only, public API only, complexity threshold, and token-cost threshold.
10. Include “context pack preview” mode showing which graph nodes would be included for a given task/budget.

Recommended implementation:

- `CodeContextKitServer` target using `Hummingbird` or `Vapor` later; v1 can start with a small custom HTTP server if dependency minimization is preferred.
- Static HTML/JS/CSS embedded as package resources.
- Graph JSON endpoint: `GET /graph.json`.
- Node detail endpoint: `GET /node/:id`.
- Context preview endpoint: `POST /pack/preview`.
- WebSocket endpoint: `/ws` streaming index progress, file-change events, graph-diff events, and selected-node updates.

Example graph JSON shape:

```json
{
  "nodes": [
    {
      "id": "symbol:APIClient.send",
      "kind": "function",
      "label": "APIClient.send",
      "file": "Sources/Auth/APIClient.swift",
      "lineStart": 42,
      "lineEnd": 118,
      "tokens": 2800
    }
  ],
  "edges": [
    {
      "source": "symbol:AuthRefreshTests.testRetriesAfter401",
      "target": "symbol:APIClient.send",
      "kind": "tests"
    }
  ]
}
```

Acceptance criteria:

- `cckit visualize` starts a local server and prints the URL.
- `cckit visualize --export graph.html` writes a standalone HTML file.
- Selecting a node shows symbol details and copyable `cckit symbol ...` / `cckit pack ...` commands.
- `cckit index --watch` can notify the visualizer through WebSocket updates.
- The visualizer must work without network access and must not load remote JS/CSS by default.

---

## Configuration File

Look for `.cckit.yaml` in repo root.

Initial config:

```yaml
index:
  include:
    - "**/*.swift"
  exclude:
    - ".git/**"
    - ".build/**"
    - "DerivedData/**"
    - "**/*.generated.swift"
    - "**/Package.resolved"
    - "**/*.pb.swift"

context:
  default_budget_tokens: 12000
  repo_map_budget_tokens: 4096
  max_symbol_body_tokens: 3000
  max_file_outline_tokens: 1200
  max_failure_summary_tokens: 1200

ranking:
  boost_changed_files: true
  boost_tests: true
  boost_exact_symbol_names: true
  boost_type_names: true

pricing:
  models:
    default:
      input_per_mtok: 1.00
      output_per_mtok: 8.00
```

Acceptance criteria:

- If config is absent, sane defaults are used.
- Config errors are clear and actionable.

---

## Storage Design

### Directory layout

```text
.cckit/
  repo.wax
  index.sqlite
  cache/
    outlines/
    packs/
```

### SQLite schema draft

```sql
CREATE TABLE files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL UNIQUE,
  language TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  modified_at TEXT,
  indexed_at TEXT NOT NULL
);

CREATE TABLE symbols (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  qualified_name TEXT NOT NULL,
  signature TEXT,
  enclosing_type TEXT,
  access_level TEXT,
  start_line INTEGER NOT NULL,
  end_line INTEGER NOT NULL,
  doc_comment TEXT,
  estimated_tokens INTEGER,
  UNIQUE(file_id, qualified_name, start_line, end_line)
);

CREATE INDEX idx_symbols_name ON symbols(name);
CREATE INDEX idx_symbols_qualified_name ON symbols(qualified_name);
CREATE INDEX idx_symbols_kind ON symbols(kind);

CREATE TABLE chunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  symbol_id INTEGER REFERENCES symbols(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  text TEXT NOT NULL,
  start_line INTEGER,
  end_line INTEGER,
  estimated_tokens INTEGER
);
```

---

## Symbol Extraction Model

Define:

```swift
public struct SymbolRecord: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case `struct`
        case `class`
        case actor
        case `enum`
        case `protocol`
        case `extension`
        case function
        case initializer
        case property
        case test
    }

    public var kind: Kind
    public var name: String
    public var qualifiedName: String
    public var signature: String
    public var filePath: String
    public var startLine: Int
    public var endLine: Int
    public var enclosingType: String?
    public var accessLevel: String?
    public var docComment: String?
    public var estimatedTokens: Int
}
```

SwiftSyntax visitor should collect:

- `StructDeclSyntax`
- `ClassDeclSyntax`
- `ActorDeclSyntax`
- `EnumDeclSyntax`
- `ProtocolDeclSyntax`
- `ExtensionDeclSyntax`
- `FunctionDeclSyntax`
- `InitializerDeclSyntax`
- `VariableDeclSyntax`

Test heuristic:

- function name starts with `test`
- or enclosing type name ends with `Tests`
- or file path contains `Tests/`

Do not attempt full type resolution in v1.

---

## Wax Document Design

Store searchable docs in Wax for semantic/local retrieval.

Use multiple document kinds:

```swift
enum MemoryDocumentKind: String, Codable, Sendable {
    case fileOutline
    case symbol
    case test
    case fileSummary
    case moduleSummary
}
```

Text for a symbol document:

```text
kind: function
symbol: APIClient.send
file: Sources/Auth/APIClient.swift
enclosing_type: APIClient
signature: func send<T: Decodable>(_ request: APIRequest) async throws -> T
summary: Sends an authenticated API request and decodes the response.
body:
...
```

Metadata:

```json
{
  "kind": "function",
  "language": "swift",
  "file": "Sources/Auth/APIClient.swift",
  "symbol": "APIClient.send",
  "enclosingType": "APIClient",
  "hash": "sha256...",
  "startLine": 42,
  "endLine": 118
}
```

Important: Wax is for fuzzy retrieval. SQLite remains the exact index.

---

## Token Estimation

Implement a simple approximation first:

```swift
public struct TokenEstimator {
    public func estimate(_ text: String) -> Int {
        max(1, Int(Double(text.utf8.count) / 3.8))
    }
}
```

Then later add model-specific tokenizers.

Every context-producing command should output estimated tokens.

---

## Context Packing Algorithm

Input:

- task string
- token budget
- optional failure log
- optional changed files/base branch
- optional include/exclude globs

Process:

1. Extract query terms from task.
2. Search exact symbol index.
3. Search Wax.
4. Add test/failure related symbols.
5. Add repo map excerpt.
6. Deduplicate by symbol/file/range.
7. Rank candidates.
8. Pack until token budget is reached.
9. Record excluded candidates with token estimates and reasons.
10. Render Markdown/JSON.

Candidate scoring rough formula:

```text
score =
  exactSymbolMatch * 5.0
+ typeNameMatch * 4.0
+ functionNameMatch * 4.0
+ waxScore * 2.0
+ lexicalScore * 2.0
+ changedFileBoost * 1.5
+ testBoost * 1.5
- tokenCostPenalty
```

---

## Failure Log Summary

For v1, implement deterministic failure extraction, not LLM summarization.

Support patterns for:

- XCTest failures
- Swift compiler errors
- generic `error:` lines
- stack trace-ish lines

Command:

```bash
cckit pack --failure build.log --task "fix failing tests" --budget 12000
```

Output section:

```text
## Failure Summary

Detected XCTest failures:
- AuthRefreshTests.testRetriesAfter401
  Expected refreshCount == 1, got 2
  Sources/Auth/APIClient.swift:88
```

---

## Integration With Aider Later

Do not depend on Aider internals in v1.

Provide handoff output:

```bash
cckit pack --task "fix auth retry" --budget 12000 --output .cckit/context.md
```

Then user can run:

```bash
aider --read .cckit/context.md
```

Later add:

```bash
cckit run --agent aider --budget 1.00 -- "fix auth retry"
```

This wrapper should:

1. create context pack
2. start Aider with the pack
3. record basic run metadata
4. optionally parse Aider output/logs

---

## Milestones

### Milestone 1 — CLI skeleton

Tasks:

- Create Swift package.
- Add executable product `cckit`.
- Add ArgumentParser command tree.
- Add placeholder commands: `index`, `outline`, `symbol`, `search`, `map`, `pack`, `estimate`, `explain`.
- Add basic tests.

Acceptance:

```bash
swift run cckit --help
swift run cckit index --help
swift test
```

all succeed.

---

### Milestone 2 — Swift symbol extraction

Tasks:

- Parse Swift files with SwiftParser.
- Build line map from source positions.
- Extract type/function/property/test records.
- Render file outline.

Acceptance:

- Unit test fixture Swift file produces expected symbols.
- `cckit outline Fixture.swift` prints expected outline.

---

### Milestone 3 — SQLite index

Tasks:

- Add database migrations.
- Store file and symbol records.
- Implement incremental indexing by file hash.
- Implement exact symbol lookup.

Acceptance:

- `cckit index .` creates `.cckit/index.sqlite`.
- Re-running without changes reports no changed files.
- `cckit symbol SomeType.someFunction` works.

---

### Milestone 4 — Wax search

Tasks:

- Add Wax store wrapper.
- Insert symbol and outline documents into Wax during indexing.
- Implement `cckit search` with hybrid exact + Wax retrieval.

Acceptance:

- Search returns relevant symbols for conceptual query.
- Search output includes score, file, symbol, preview, token estimate.

---

### Milestone 5 — Repo map

Tasks:

- Build simple repo map from indexed symbols.
- Rank by exact task/focus terms and symbol kind.
- Pack under token budget.

Acceptance:

- `cckit map --budget 4096` produces compact map.
- `cckit map --focus "auth token"` prioritizes matching symbols.

---

### Milestone 6 — Context packet

Tasks:

- Implement `ContextPacker`.
- Include task, selected symbols, outlines, repo map excerpt.
- Add deterministic failure log extraction.
- Render Markdown and JSON.
- Include attribution and exclusions.

Acceptance:

- `cckit pack --task "..." --budget 12000 --output context.md` creates useful packet.
- Packet includes estimated token counts.
- Packet lists included and excluded context.

---

### Milestone 7 — Mint readiness

Tasks:

- Ensure executable product is correct.
- Add README install instructions.
- Add `Mintfile` if useful.
- Tag release.

Acceptance:

```bash
mint run owner/cckit --help
mint install owner/cckit
cckit --help
```

works after publishing.

---

## Testing Strategy

Use fixtures:

```text
Tests/Fixtures/SimplePackage/
  Package.swift
  Sources/Auth/APIClient.swift
  Sources/Auth/TokenProvider.swift
  Tests/AuthRefreshTests.swift
  build.log
```

Tests:

- symbol extraction
- outline rendering
- database indexing
- incremental indexing
- exact symbol lookup
- search ranking with fake Wax adapter if needed
- repo map budget packing
- context packet rendering
- failure log extraction

Avoid network-dependent tests.

---

## README Sections To Create

- What is CodeContextKit?
- Install with Mint
- Quick start
- Commands
- Example: create a context packet for Aider
- Configuration
- Design principles
- Why symbol-first retrieval?
- Roadmap

Quick start example:

```bash
mint run owner/cckit index .
mint run owner/cckit map --focus "auth retry" --budget 4096
mint run owner/cckit pack --task "fix AuthRefreshTests.testRetriesAfter401" --budget 12000 --output context.md
aider --read context.md
```

---

## Design Principles

1. Prefer exact symbols over raw files.
2. Prefer outlines before bodies.
3. Prefer deterministic parsing before LLM calls.
4. Prefer file hashes for cache correctness.
5. Prefer transparent token estimates everywhere.
6. Prefer useful Markdown output by default and JSON for automation.
7. Keep v1 fully local and offline.
8. Use Wax for semantic recall, not as the exact source of truth.
9. Every context packet should explain what was included and what was avoided.

---

## Future Work

- Aider wrapper mode.
- Claude Code / Codex / OpenCode wrapper modes.
- Real token accounting from provider logs.
- Run ledger and per-task cost reports.
- OpenInference trace export.
- MCP server exposing `cckit` context tools.
- Swift LSP integration for references/callers/callees.
- Tree-sitter support for TypeScript/Python/Kotlin/etc.
- Codemod/script recommendation mode.
- Test-loop and repeated-file-read detection.
