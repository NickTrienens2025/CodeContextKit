# 🚀 CodeContextKit (cckit)

### *The Surgeon’s Scalpel for AI-Assisted Swift Development.*

**CodeContextKit** is a high-performance indexing and context-packing engine designed for developers who want to stop sending entire repositories to LLMs and start sending high-signal, surgical context. Built with **Swift 6**, **Hummingbird 2**, and **SQLite**, it provides an architect-level understanding of your codebase while running entirely on-device.

---

## 🌟 Why CodeContextKit?

Traditional AI tools either know too little about your project structure or overwhelm the LLM with irrelevant tokens. **cckit** solves this by treating your codebase as a queryable semantic graph.

- **💾 Token Efficiency**: Stop wasting millions of tokens. Pack exactly what the AI needs—including skeletons, call sites, and captured terminal errors—into a single, surgical Markdown packet.
- **🏗️ Architect-Level Insight**: Automatically extract symbol hierarchies, protocol conformances, and complex reference maps.
- **🍎 Apple Intelligence Native**: Leverages **Apple Foundation Models** on macOS 15+ to generate documentation and summaries on-device. No data leaves your machine.
- **⚡ High-Performance Indexing**: Incremental, SQLite-backed indexing that keeps up with large-scale projects without the lag.

---

## 📺 The Visualizer (A DocC-Inspired Experience)

Launch a local, interactive portal to your codebase. It’s not just a file browser; it’s an AI-ready command center.

- **Monaco Editor Support**: View your code with the same engine that powers VS Code.
- **Interactive Graph**: See how your modules and files connect in a real-time force-directed graph.
- **🛒 Context Cart**: Stage specific files and symbols into a "cart" and pack them instantly. Perfect for building targeted feature context.
- **🖥️ Integrated Terminal**: Run `swift test` or `build` directly from the browser and append failure logs to your AI context with one click.
- **⚙️ Unused Code Detection**: Instantly identify potentially dead functions and properties across your modules.

---

## 🛠️ Quick Start

### 1. Installation

**Using Mint (Recommended):**
```bash
mint install NickTrienens2025/CodeContextKit
```

**Building from Source:**
```bash
git clone git@github.com:NickTrienens2025/CodeContextKit.git
cd CodeContextKit
swift build -c release
```

### 2. Index Your Project
```bash
# Scan and build your local knowledge base
cckit index .
```

### 3. Launch the Experience
```bash
# Start the server and auto-open the visualizer
cckit serve
```

---

## 🧭 CLI at a Glance

| Command | Purpose |
| :--- | :--- |
| `cckit index` | Build the SQLite & Semantic knowledge base. |
| `cckit pack` | Generate a surgical context packet for an AI task. |
| `cckit search` | Unified discovery: Symbol, Literal (Grep), and Semantic search. |
| `cckit outline` | Get the structural "skeleton" of any Swift file. |
| `cckit symbol` | Retrieve the exact implementation of any named symbol. |

---

## 🔐 Privacy & Security

CodeContextKit is **local-first**. Your code is indexed into a local SQLite database and processed by local Apple Foundation Models. Your intellectual property stays where it belongs: **on your disk.**

---

Built with ❤️ by [Nicholas Trienens](https://github.com/NickTrienens2025)
