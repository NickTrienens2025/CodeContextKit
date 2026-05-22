# ``CodeContextKitContext``

The high-level orchestrator for generating surgical code context and architectural repo maps.

## Overview

CodeContextKitContext integrates with `ContextCore` and `Wax` to provide advanced ranking, compression, and dependency crawling. It is the primary entry point for agentic workflows looking to understand large codebases with minimal token overhead.

## Topics

### Mapping and Packing
- ``RepoMapBuilder``
- ``ContextPacker``

### Orchestration
- ``ActionOrchestrator``
- ``Indexer``
