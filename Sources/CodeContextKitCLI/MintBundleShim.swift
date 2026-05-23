import Foundation

/// Resolves a Mint/symlink install layout where the `cckit` binary lives in
/// `~/.mint/bin/` as a symlink to a real binary that sits next to its SwiftPM
/// resource bundles. SwiftPM's auto-generated `Bundle.module` accessor reads
/// `Bundle.main.bundleURL` without resolving symlinks, so dependencies (Wax)
/// fatal-error when they look for `Wax_Wax.bundle` next to the symlink.
///
/// This shim runs before any `Bundle.module` access and symlinks every
/// `*.bundle` sibling of the real binary into the directory containing the
/// launched (possibly-symlinked) binary. It is a no-op on non-Mint installs.
enum MintBundleShim {
    static func ensureResourceBundlesVisible() {
        guard let executablePath = Bundle.main.executablePath else { return }
        let launchedURL = URL(fileURLWithPath: executablePath)
        let resolvedURL = launchedURL.resolvingSymlinksInPath()
        guard launchedURL.path != resolvedURL.path else { return }

        let launchedDir = launchedURL.deletingLastPathComponent()
        let resolvedDir = resolvedURL.deletingLastPathComponent()
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: resolvedDir.path) else { return }
        for name in entries where name.hasSuffix(".bundle") {
            let source = resolvedDir.appendingPathComponent(name)
            let link = launchedDir.appendingPathComponent(name)
            if fm.fileExists(atPath: link.path) { continue }
            try? fm.createSymbolicLink(at: link, withDestinationURL: source)
        }
    }
}
