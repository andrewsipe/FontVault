import Foundation

struct OrphanScanResult: Sendable {
    var orphanFiles: [URL] = []
    var missingCatalogPaths: [String] = []
}

/// Vault filesystem hygiene (empty folders, integrity helpers).
enum VaultMaintenance {
    static func relativeVaultPath(file: URL, vaultRoot: URL) -> String {
        let root = vaultRoot.standardizedFileURL.path
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return "" }
        return String(path.dropFirst(root.count + 1))
    }

    /// Font files on disk under `vaultRoot` that are not listed in `catalogPaths`.
    static func scanVaultIntegrity(vaultRoot: URL, catalogPaths: Set<String>) -> OrphanScanResult {
        var result = OrphanScanResult()
        let fm = FileManager.default
        let root = vaultRoot.standardizedFileURL

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        while let url = enumerator.nextObject() as? URL {
            if url.path.contains("/.fontvault/") { continue }
            guard FontMetadataReader.isFontFile(url) else { continue }

            let relative = relativeVaultPath(file: url, vaultRoot: root)
            guard !relative.isEmpty else { continue }

            if catalogPaths.contains(relative) {
                continue
            }
            result.orphanFiles.append(url)
        }

        for path in catalogPaths {
            let file = root.appendingPathComponent(path)
            if !fm.fileExists(atPath: file.path) {
                result.missingCatalogPaths.append(path)
            }
        }

        return result
    }

    static func uniqueFileName(base: String, in directory: URL) -> String {
        let fm = FileManager.default
        var candidate = base
        var suffix = 2
        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            let stem = (base as NSString).deletingPathExtension
            let ext = (base as NSString).pathExtension
            if ext.isEmpty {
                candidate = "\(stem) \(suffix)"
            } else {
                candidate = "\(stem) \(suffix).\(ext)"
            }
            suffix += 1
        }
        return candidate
    }
    /// Removes empty directories from `startingAt` upward, stopping before `stopBefore` (not deleted).
    static func pruneEmptyDirectories(from startingAt: URL, stopBefore: URL) {
        let stopBefore = stopBefore.standardizedFileURL
        var current = startingAt.standardizedFileURL
        let fm = FileManager.default

        while current.path != stopBefore.path {
            guard let items = try? fm.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { break }

            if !items.isEmpty { break }

            do {
                try fm.removeItem(at: current)
            } catch {
                break
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
    }

    /// Walk the vault bottom-up and remove every empty directory (except `.fontvault` and vault root).
    static func pruneAllEmptyDirectories(vaultRoot: URL) -> Int {
        let fm = FileManager.default
        let root = vaultRoot.standardizedFileURL
        var removed = 0
        var changed = true

        while changed {
            changed = false
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { break }

            var directories: [URL] = []
            while let url = enumerator.nextObject() as? URL {
                if url.path.contains("/.fontvault") { continue }
                if url.standardizedFileURL.path == root.path { continue }
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                directories.append(url.standardizedFileURL)
            }

            directories.sort { $0.path.count > $1.path.count }

            for dir in directories {
                guard let items = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ), items.isEmpty else { continue }

                if (try? fm.removeItem(at: dir)) != nil {
                    removed += 1
                    changed = true
                }
            }
        }

        return removed
    }

    /// All font file URLs under the vault (excluding `.fontvault`).
    static func allFontFiles(vaultRoot: URL) -> [URL] {
        let fm = FileManager.default
        let root = vaultRoot.standardizedFileURL
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.path.contains("/.fontvault/") { continue }
            guard FontMetadataReader.isFontFile(url) else { continue }
            files.append(url)
        }
        return files
    }

    /// After removing fonts from the vault, prune empty style/bucket folders.
    static func pruneAfterRemovingFiles(vaultRoot: URL, vaultPaths: [String]) {
        let vaultRoot = vaultRoot.standardizedFileURL
        let parents = Set(vaultPaths.map { vaultRoot.appendingPathComponent($0).deletingLastPathComponent() })
        for dir in parents {
            pruneEmptyDirectories(from: dir, stopBefore: vaultRoot)
        }
    }

    /// After move-import, prune empty folders left at the source (FEX-style).
    static func pruneAfterMovingFiles(sources: [URL], importRoots: [URL]) {
        var pruned = Set<String>()
        for source in sources {
            let dir = source.deletingLastPathComponent().standardizedFileURL
            guard pruned.insert(dir.path).inserted else { continue }
            let stop = importStopBefore(for: source, importRoots: importRoots)
            pruneEmptyDirectories(from: dir, stopBefore: stop)
        }
    }

    /// Parent of the import selection — do not prune above this (e.g. keep `Downloads` when importing from `Downloads/FontPack`).
    static func importStopBefore(for file: URL, importRoots: [URL]) -> URL {
        let file = file.standardizedFileURL
        let roots = importRoots.map { $0.standardizedFileURL }

        var best: URL?
        for root in roots {
            let matches: Bool
            if isDirectory(root) {
                matches = file.path == root.path || file.path.hasPrefix(root.path + "/")
            } else {
                matches = file.path == root.path
            }
            if matches, best == nil || root.path.count > best!.path.count {
                best = root
            }
        }

        let anchor = best ?? file.deletingLastPathComponent()
        if isDirectory(anchor) {
            return anchor.deletingLastPathComponent()
        }
        return anchor.deletingLastPathComponent()
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
