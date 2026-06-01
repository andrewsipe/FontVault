import Foundation

/// Tracks vault paths committed during a batch import so cancel can roll back.
/// Does not copy files to a temp folder — one pass source → vault only.
@MainActor
final class ImportBatchTracker {
    private(set) var committedVaultPaths: [String] = []
    private var sourcesForMoveAfterSuccess: [URL] = []

    func recordImport(vaultPath: String, source: URL, move: Bool) {
        committedVaultPaths.append(vaultPath)
        if move {
            sourcesForMoveAfterSuccess.append(source.standardizedFileURL)
        }
    }

    func rollbackCommittedFiles(vaultRoot: URL, catalog: CatalogStore) throws {
        guard !committedVaultPaths.isEmpty else { return }
        let paths = committedVaultPaths
        for path in paths {
            let fileURL = vaultRoot.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        try catalog.delete(vaultPaths: paths)
        committedVaultPaths.removeAll()
        sourcesForMoveAfterSuccess.removeAll()
        VaultMaintenance.pruneAfterRemovingFiles(vaultRoot: vaultRoot, vaultPaths: paths)
    }

    func removeSourcesAfterSuccessfulMove(importRoots: [URL]) {
        guard !sourcesForMoveAfterSuccess.isEmpty else { return }
        let sources = sourcesForMoveAfterSuccess
        for source in sources {
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.removeItem(at: source)
            }
        }
        VaultMaintenance.pruneAfterMovingFiles(sources: sources, importRoots: importRoots)
        sourcesForMoveAfterSuccess.removeAll()
    }
}
