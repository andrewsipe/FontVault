import Foundation

struct ImportResult: Sendable {
    var imported: Int = 0
    var skipped: Int = 0
    var entries: [ImportReportEntry] = []
    var scanned: Int = 0
    /// Regular files whose extension is not in `FontMetadataReader.importableExtensions`.
    var ignoredUnsupportedFormat: Int = 0
    /// Importable extension but turned off in format filters (e.g. .woff with Web fonts unchecked).
    var ignoredFilteredFormat: Int = 0
    /// Fonts whose vault folder used the filename stem because Full name (ID 4) was not viable.
    var vaultFolderFallbackCount: Int = 0

    var ignoredFormatFileCount: Int {
        ignoredUnsupportedFormat + ignoredFilteredFormat
    }
}

struct RemoveResult: Sendable {
    var removed: Int = 0
    var failed: [String] = []
}

struct ExportResult: Sendable {
    var exported: Int = 0
    var failed: [String] = []
}

struct CleanVaultResult: Sendable {
    var trashed: Int = 0
    var removedFromCatalog: Int = 0
    var prunedEmptyFolders: Int = 0
    var failed: [String] = []
    var catalogWasOptimized: Bool = false
    var catalogBytesReclaimed: Int64 = 0
}

struct ReorganizeResult: Sendable {
    var moved: Int = 0
    var unchanged: Int = 0
    var catalogAdded: Int = 0
    var failed: [String] = []
}

/// Orchestrates file operations and catalog updates.
@MainActor
final class VaultCoordinator: ObservableObject {
    @Published private(set) var catalog: CatalogStore?
    @Published private(set) var isIndexing = false
    @Published private(set) var indexProgress: String = ""
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: String = ""
    /// Called on the main actor when the modal import sheet should update (large imports only).
    var onImportProgressState: ((ImportProgressState?) -> Void)?
    /// Called on the main actor when the rebuild-catalog sheet should update.
    var onCatalogProgressState: ((ImportProgressState?) -> Void)?
    var onCleanProgressState: ((ImportProgressState?) -> Void)?
    var onReorganizeProgressState: ((ImportProgressState?) -> Void)?
    private(set) var importWasCancelled = false
    /// True when the last import showed the modal progress sheet (completion stays in-sheet).
    private(set) var importUsedProgressPanel = false
    private var importCancellationRequested = false
    private(set) var catalogWasCancelled = false
    private(set) var catalogUsedProgressPanel = false
    private var catalogCancellationRequested = false
    private(set) var cleanUsedProgressPanel = false
    private(set) var reorganizeUsedProgressPanel = false
    private var reorganizeCancellationRequested = false
    private(set) var reorganizeWasCancelled = false
    @Published private(set) var isExporting = false
    @Published private(set) var exportProgress: String = ""
    @Published private(set) var isCleaning = false
    @Published private(set) var cleanProgress: String = ""

    private let settings: VaultSettings

    init(settings: VaultSettings) {
        self.settings = settings
    }

    func reloadCatalog() throws {
        guard let root = settings.vaultRootURL else {
            catalog = nil
            return
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        catalog = try CatalogStore.open(vaultRoot: root)
    }

    func importURLs(
        _ urls: [URL],
        move: Bool,
        formats: ImportFormatOptions
    ) async throws -> ImportResult {
        guard let root = settings.vaultRootURL else {
            throw CatalogStoreError.vaultNotConfigured
        }
        guard formats.allowsAnyFontFile() else {
            throw CatalogStoreError.noFormatsSelected
        }
        if catalog == nil {
            try reloadCatalog()
        }
        guard let catalog else { throw CatalogStoreError.databaseUnavailable }

        isImporting = true
        importCancellationRequested = false
        importWasCancelled = false
        importUsedProgressPanel = false
        importProgress = "Preparing import…"

        let engine = LayoutEngine(vaultRoot: root)
        var result = ImportResult()
        let tracker = ImportBatchTracker()

        defer {
            isImporting = false
            importProgress = ""
            importWasCancelled = importCancellationRequested
            if !importUsedProgressPanel {
                onImportProgressState?(nil)
            }
        }

        let collected = collectFontFiles(from: urls, formats: formats)
        let files = collected.files
        result.scanned = files.count
        result.ignoredUnsupportedFormat = collected.ignoredUnsupported
        result.ignoredFilteredFormat = collected.ignoredFiltered
        let showPanel = files.count >= ImportProgressReporter.panelThreshold
        importUsedProgressPanel = showPanel
        let total = files.count

        reportImportProgress(
            showPanel: showPanel,
            title: "Importing…",
            fileName: "Preparing…",
            completed: 0,
            total: total
        )

        // Single pass: source → vault (+ catalog). Move deletes sources only after full success.
        for (index, file) in files.enumerated() {
            if importCancellationRequested { break }

            reportImportProgress(
                showPanel: showPanel,
                title: "Importing…",
                fileName: file.lastPathComponent,
                completed: index,
                total: total
            )

            try await importOneFile(
                file: file,
                move: move,
                engine: engine,
                catalog: catalog,
                tracker: tracker,
                result: &result
            )

            reportImportProgress(
                showPanel: showPanel,
                title: "Importing…",
                fileName: file.lastPathComponent,
                completed: index + 1,
                total: total
            )

            if !showPanel, index % 10 == 0 || index == files.count - 1 {
                importProgress = "Importing \(index + 1) / \(total)…"
            }
            await Task.yield()
        }

        if importCancellationRequested {
            try tracker.rollbackCommittedFiles(vaultRoot: root, catalog: catalog)
            return result
        }

        if move {
            tracker.removeSourcesAfterSuccessfulMove(importRoots: urls)
        }

        return result
    }

    func importCompletionProgressState(result: ImportResult, move: Bool, total: Int) -> ImportProgressState {
        let title = result.imported > 0 ? "Import complete" : "Nothing imported"
        let message = importSummaryLine(result: result, move: move)
        return ImportProgressState.complete(title: title, message: message, total: total)
    }

    private func importSummaryLine(result: ImportResult, move: Bool) -> String {
        ImportResult.summaryText(for: result, move: move)
    }

    func requestImportCancellation() {
        importCancellationRequested = true
    }

    func requestCatalogCancellation() {
        catalogCancellationRequested = true
    }

    func requestReorganizeCancellation() {
        reorganizeCancellationRequested = true
    }

    func catalogCompletionProgressState(result: CatalogIndexResult) -> ImportProgressState {
        let completeTitle = settings.catalogScanCompleteTitle
        let title = result.scanned > 0 ? completeTitle : (settings.organizesVaultFiles ? "Nothing to rebuild" : "No changes found")
        let message: String
        if result.updated > 0 {
            message =
                "Scanned \(result.scanned) font\(result.scanned == 1 ? "" : "s"). " +
                "Added \(result.added), refreshed metadata for \(result.updated)."
        } else {
            message =
                "Scanned \(result.scanned) font\(result.scanned == 1 ? "" : "s"). " +
                "Added \(result.added) to catalog."
        }
        return ImportProgressState.complete(title: title, message: message, total: result.scanned)
    }

    func cleanVaultAlreadyCleanProgressState() -> ImportProgressState {
        ImportProgressState.complete(
            title: "Vault is clean",
            message: """
            Every font file on disk is listed in the catalog, and every catalog entry has a file on disk.

            Catalog database compaction was not needed.

            Rebuild Catalog only rescans files and refreshes metadata. Clean Vault removes orphans on disk, drops stale catalog rows, and prunes empty folders.
            """,
            total: 0
        )
    }

    func cleanCompletionProgressState(result: CleanVaultResult) -> ImportProgressState {
        var lines: [String] = []
        if result.trashed > 0 {
            lines.append("Moved \(result.trashed) orphan file\(result.trashed == 1 ? "" : "s") to the Trash (on disk but not in the catalog).")
        }
        if result.removedFromCatalog > 0 {
            lines.append("Removed \(result.removedFromCatalog) stale catalog entr\(result.removedFromCatalog == 1 ? "y" : "ies") (listed in the catalog but missing on disk).")
        }
        if result.prunedEmptyFolders > 0 {
            lines.append("Removed \(result.prunedEmptyFolders) empty folder\(result.prunedEmptyFolders == 1 ? "" : "s").")
        }
        if !result.failed.isEmpty {
            lines.append("\(result.failed.count) item\(result.failed.count == 1 ? "" : "s") could not be cleaned.")
        }
        if result.catalogWasOptimized {
            lines.append(catalogOptimizationSummary(result))
        } else if result.removedFromCatalog == 0, result.trashed > 0 || result.prunedEmptyFolders > 0 {
            lines.append("Catalog database compaction was not needed.")
        }
        let message = lines.isEmpty
            ? "No changes were needed."
            : lines.joined(separator: "\n")
        let total = result.trashed + result.removedFromCatalog + result.prunedEmptyFolders
        return ImportProgressState.complete(title: "Clean Vault complete", message: message, total: max(total, 1))
    }

    func cleanVaultAlreadyCleanWithOptimizationProgressState(result: CleanVaultResult) -> ImportProgressState {
        if result.catalogWasOptimized {
            return ImportProgressState.complete(
                title: "Vault is clean",
                message: """
                Every font file on disk is listed in the catalog, and every catalog entry has a file on disk.

                \(catalogOptimizationSummary(result))
                """,
                total: 1
            )
        }
        return cleanVaultAlreadyCleanProgressState()
    }

    private func catalogOptimizationSummary(_ result: CleanVaultResult) -> String {
        if result.catalogBytesReclaimed > 0 {
            let saved = ByteCountFormatter.string(fromByteCount: result.catalogBytesReclaimed, countStyle: .file)
            return "Compacted the catalog database (reclaimed about \(saved) on disk)."
        }
        return "Compacted the catalog database."
    }

    func reorganizeCompletionProgressState(result: ReorganizeResult, fileCount: Int) -> ImportProgressState {
        var lines: [String] = []
        if result.moved > 0 {
            lines.append("Moved \(result.moved) font\(result.moved == 1 ? "" : "s") into letter buckets and style folders.")
        }
        if result.unchanged > 0 {
            lines.append("\(result.unchanged) already matched the current layout.")
        }
        if result.catalogAdded > 0 {
            lines.append("Added \(result.catalogAdded) to the catalog at their new paths.")
        }
        if !result.failed.isEmpty {
            lines.append("\(result.failed.count) file\(result.failed.count == 1 ? "" : "s") could not be reorganized.")
        }
        let message = lines.isEmpty
            ? "No font files needed to move."
            : lines.joined(separator: "\n")
        return ImportProgressState.complete(
            title: reorganizeWasCancelled ? "Reorganize cancelled" : "Reorganize complete",
            message: message,
            total: max(fileCount, 1)
        )
    }

    func reportCleanScanProgress() {
        cleanUsedProgressPanel = true
        cleanProgress = "Checking vault…"
        onCleanProgressState?(
            ImportProgressState.active(
                title: "Clean Vault…",
                fileName: "Comparing files on disk with the catalog…",
                completed: 0,
                total: 0
            )
        )
    }

    private func reportImportProgress(
        showPanel: Bool,
        title: String,
        fileName: String,
        completed: Int,
        total: Int
    ) {
        importProgress = total > 0 ? "Importing \(completed) / \(total)…" : "Preparing import…"
        guard showPanel else { return }
        onImportProgressState?(
            ImportProgressState.active(
                title: title,
                fileName: fileName,
                completed: completed,
                total: total
            )
        )
    }

    /// Imports one font: copy into vault layout, catalog row, tracked for cancel rollback.
    /// When `move` is true, the source file is removed only after the whole batch succeeds.
    private func importOneFile(
        file: URL,
        move: Bool,
        engine: LayoutEngine,
        catalog: CatalogStore,
        tracker: ImportBatchTracker,
        result: inout ImportResult
    ) async throws {
        do {
            let meta = try FontMetadataReader.read(from: file)
            let fileName = file.lastPathComponent
            let folder = engine.resolveVaultFolderLabel(fullName: meta.fullName, fileName: fileName)
            let dest = engine.destinationURL(
                folderLabel: folder.label,
                fileName: fileName,
                foundry: meta.foundry
            )

            let relative = dest.path.replacingOccurrences(of: engine.vaultRoot.path + "/", with: "")

            if try catalog.vaultPathExists(relative) {
                result.recordSkipped(
                    file: file,
                    outcome: .skippedAlreadyInVault,
                    message: "Already in vault"
                )
                return
            }

            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: dest.path) {
                result.recordSkipped(
                    file: file,
                    outcome: .skippedDestinationExists,
                    message: "File already exists at destination"
                )
                return
            }

            try FileManager.default.copyItem(at: file, to: dest)

            let hash = try FontMetadataReader.sha256(of: dest)
            let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
            let size = (attrs[.size] as? Int64) ?? 0

            let record = FontRecord.from(
                metadata: meta,
                vaultPath: relative,
                sha256: hash,
                fileSize: size,
                dateAdded: Date().timeIntervalSince1970
            )
            _ = try catalog.insert(record)
            tracker.recordImport(vaultPath: relative, source: file, move: move)
            result.imported += 1
            if folder.usedFilenameFallback {
                result.recordNamingFallback(
                    file: file,
                    message: "Vault folder uses file name (Full name from font not usable)"
                )
            }
        } catch {
            result.recordFailed(file: file, message: error.localizedDescription)
        }
    }

    private struct CollectedImportFiles: Sendable {
        var files: [URL] = []
        var ignoredUnsupported: Int = 0
        var ignoredFiltered: Int = 0
    }

    private func collectFontFiles(from urls: [URL], formats: ImportFormatOptions) -> CollectedImportFiles {
        var collected = CollectedImportFiles()
        for url in urls {
            if url.hasDirectoryPath {
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                while let file = enumerator?.nextObject() as? URL {
                    classifyImportCandidate(file, formats: formats, into: &collected)
                }
            } else {
                classifyImportCandidate(url, formats: formats, into: &collected)
            }
        }
        return collected
    }

    private func classifyImportCandidate(
        _ url: URL,
        formats: ImportFormatOptions,
        into collected: inout CollectedImportFiles
    ) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return
        }

        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else {
            collected.ignoredUnsupported += 1
            return
        }
        guard FontMetadataReader.importableExtensions.contains(ext) else {
            collected.ignoredUnsupported += 1
            return
        }
        guard formats.allows(url: url) else {
            collected.ignoredFiltered += 1
            return
        }
        guard FontMetadataReader.isFontFile(url) else { return }
        collected.files.append(url)
    }

    /// Walk vault on disk and add any font files missing from the catalog.
    func indexExistingVault() async throws -> CatalogIndexResult {
        guard let root = settings.vaultRootURL else {
            throw CatalogStoreError.vaultNotConfigured
        }
        if catalog == nil {
            try reloadCatalog()
        }

        isIndexing = true
        catalogCancellationRequested = false
        catalogWasCancelled = false
        catalogUsedProgressPanel = false
        indexProgress = "Scanning vault for fonts…"

        defer {
            isIndexing = false
            catalogWasCancelled = catalogCancellationRequested
            if !catalogUsedProgressPanel {
                onCatalogProgressState?(nil)
            }
        }

        catalogUsedProgressPanel = CatalogProgressReporter.alwaysShowPanel
        let showPanel = catalogUsedProgressPanel
        reportCatalogProgress(
            showPanel: showPanel,
            title: settings.catalogScanProgressTitle,
            fileName: "Scanning vault…",
            completed: 0,
            total: 0
        )

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var toImport: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if catalogCancellationRequested { break }
            if url.path.contains("/.fontvault/") { continue }
            guard FontMetadataReader.isFontFile(url) else { continue }
            toImport.append(url)
        }

        var result = CatalogIndexResult(scanned: toImport.count)
        let total = toImport.count

        reportCatalogProgress(
            showPanel: showPanel,
            title: settings.catalogScanProgressTitle,
            fileName: total > 0 ? "Reading font metadata…" : "No font files found",
            completed: 0,
            total: total
        )

        guard let catalog else { return result }

        var existingPaths = (try? catalog.allVaultPaths()) ?? []
        var added = 0
        var updated = 0
        var batch: [FontRecord] = []
        let batchSize = 200

        func flushBatch() throws {
            guard !batch.isEmpty else { return }
            let batchAdded = batch.filter { !existingPaths.contains($0.vaultPath) }.count
            let batchUpdated = batch.count - batchAdded
            try catalog.applyIndexBatch(batch, existingPaths: &existingPaths)
            added += batchAdded
            updated += batchUpdated
            batch.removeAll(keepingCapacity: true)
        }

        for (index, file) in toImport.enumerated() {
            if catalogCancellationRequested { break }

            let relative = VaultMaintenance.relativeVaultPath(file: file, vaultRoot: root)
            guard !relative.isEmpty else { continue }

            reportCatalogProgress(
                showPanel: showPanel,
                title: settings.catalogScanProgressTitle,
                fileName: file.lastPathComponent,
                completed: index,
                total: total
            )

            do {
                let meta = try FontMetadataReader.read(from: file)
                let hash = try FontMetadataReader.sha256(of: file)
                let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
                let size = (attrs[.size] as? Int64) ?? 0

                let record: FontRecord
                if existingPaths.contains(relative),
                   var existing = try catalog.fetchRecord(vaultPath: relative) {
                    existing.apply(metadata: meta, sha256: hash, fileSize: size)
                    if !settings.excludeIgnoredFontsFromIndex {
                        existing.excludedFromIndex = false
                    }
                    record = existing
                } else {
                    record = FontRecord.from(
                        metadata: meta,
                        vaultPath: relative,
                        sha256: hash,
                        fileSize: size,
                        dateAdded: Date().timeIntervalSince1970
                    )
                }
                batch.append(record)

                if batch.count >= batchSize {
                    try flushBatch()
                }
            } catch {
                continue
            }

            if index % 50 == 0 || index == toImport.count - 1 {
                try? flushBatch()
                reportCatalogProgress(
                    showPanel: showPanel,
                    title: settings.catalogScanProgressTitle,
                    fileName: file.lastPathComponent,
                    completed: index + 1,
                    total: total
                )
                if !showPanel {
                    indexProgress = "Indexed \(index + 1) / \(total)…"
                }
                await Task.yield()
            }
        }

        if !catalogCancellationRequested {
            try flushBatch()
        }

        result.added = added
        result.updated = updated

        if catalogCancellationRequested {
            indexProgress = "Catalog rebuild cancelled."
        } else if updated > 0 {
            indexProgress = "Added \(added), refreshed metadata for \(updated) font\(updated == 1 ? "" : "s")."
        } else {
            indexProgress = "Added \(added) fonts to catalog."
        }

        return result
    }

    private func reportCatalogProgress(
        showPanel: Bool,
        title: String,
        fileName: String,
        completed: Int,
        total: Int
    ) {
        let verb = settings.organizesVaultFiles ? "Rebuilding" : "Scanning"
        indexProgress = total > 0 ? "\(verb) \(completed) / \(total)…" : "Scanning vault…"
        guard showPanel else { return }
        onCatalogProgressState?(
            ImportProgressState.active(
                title: title,
                fileName: fileName,
                completed: completed,
                total: total
            )
        )
    }

    private func reportCleanProgress(
        title: String,
        fileName: String,
        completed: Int,
        total: Int
    ) {
        cleanProgress = total > 0 ? "Cleaning \(completed) / \(total)…" : title
        guard cleanUsedProgressPanel else { return }
        onCleanProgressState?(
            ImportProgressState.active(
                title: title,
                fileName: fileName,
                completed: completed,
                total: total
            )
        )
    }

    private func reportReorganizeProgress(
        title: String,
        fileName: String,
        completed: Int,
        total: Int
    ) {
        indexProgress = total > 0 ? "Reorganizing \(completed) / \(total)…" : "Scanning vault…"
        guard reorganizeUsedProgressPanel else { return }
        onReorganizeProgressState?(
            ImportProgressState.active(
                title: title,
                fileName: fileName,
                completed: completed,
                total: total
            )
        )
    }

    // MARK: - Remove

    func removeFonts(_ records: [FontRecord], moveToTrash: Bool) async throws -> RemoveResult {
        guard let root = settings.vaultRootURL else {
            throw CatalogStoreError.vaultNotConfigured
        }
        if catalog == nil {
            try reloadCatalog()
        }
        guard let catalog else {
            throw CatalogStoreError.databaseUnavailable
        }

        var result = RemoveResult()
        var removedPaths: [String] = []

        for record in records {
            let fileURL = root.appendingPathComponent(record.vaultPath)
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if moveToTrash {
                        try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                    } else {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                }
                removedPaths.append(record.vaultPath)
                result.removed += 1
            } catch {
                result.failed.append("\(record.fullName): \(error.localizedDescription)")
            }
        }

        if !removedPaths.isEmpty {
            try catalog.delete(vaultPaths: removedPaths)
            VaultMaintenance.pruneAfterRemovingFiles(vaultRoot: root, vaultPaths: removedPaths)
        }

        return result
    }

    // MARK: - Export

    func exportFonts(
        _ records: [FontRecord],
        to destination: URL,
        layoutMode: ExportLayoutMode
    ) async throws -> ExportResult {
        guard let root = settings.vaultRootURL else {
            throw CatalogStoreError.vaultNotConfigured
        }

        isExporting = true
        exportProgress = "Preparing export…"
        defer {
            isExporting = false
            exportProgress = ""
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var result = ExportResult()
        let fm = FileManager.default
        exportProgress = "Exporting 0 / \(records.count)…"

        let pathMap = DragExportStaging.relativeExportPaths(for: records, mode: layoutMode) { record in
            root.appendingPathComponent(record.vaultPath).lastPathComponent
        }

        for (index, record) in records.enumerated() {
            let source = root.appendingPathComponent(record.vaultPath)
            guard fm.fileExists(atPath: source.path) else {
                result.failed.append("\(record.fullName): file missing in vault")
                continue
            }

            guard let relative = pathMap[record.vaultPath] else {
                result.failed.append("\(record.fullName): could not determine export path")
                continue
            }

            let dest = destination.appendingPathComponent(relative)

            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: source, to: dest)
                result.exported += 1
            } catch {
                result.failed.append("\(record.fullName): \(error.localizedDescription)")
            }

            if index % 10 == 0 || index == records.count - 1 {
                exportProgress = "Exporting \(index + 1) / \(records.count)…"
                await Task.yield()
            }
        }

        return result
    }

    // MARK: - Clean vault (FEX “Clean Organized Fonts Folder”)

    func scanVaultIntegrity() throws -> OrphanScanResult {
        guard let root = settings.vaultRootURL else {
            throw CatalogStoreError.vaultNotConfigured
        }
        if catalog == nil {
            try reloadCatalog()
        }
        guard let catalog else {
            throw CatalogStoreError.databaseUnavailable
        }

        let paths = try catalog.allVaultPaths()
        return VaultMaintenance.scanVaultIntegrity(vaultRoot: root, catalogPaths: paths)
    }

    /// Orphan files → Trash; stale catalog rows → removed; empty folders pruned.
    func performVaultClean(scan: OrphanScanResult) async throws -> CleanVaultResult {
        guard let root = settings.vaultRootURL else {
            throw CatalogStoreError.vaultNotConfigured
        }
        if catalog == nil {
            try reloadCatalog()
        }
        guard let catalog else {
            throw CatalogStoreError.databaseUnavailable
        }

        isCleaning = true
        cleanUsedProgressPanel = true
        cleanProgress = "Cleaning vault…"
        defer {
            isCleaning = false
            if !cleanUsedProgressPanel {
                onCleanProgressState?(nil)
            }
        }

        let orphanTotal = scan.orphanFiles.count
        let phaseTotal = max(1, orphanTotal + (scan.missingCatalogPaths.isEmpty ? 0 : 1) + 1)
        var completedPhase = 0

        reportCleanProgress(
            title: "Cleaning vault…",
            fileName: orphanTotal > 0
                ? "Moving orphan files to the Trash…"
                : "No orphan files on disk.",
            completed: completedPhase,
            total: phaseTotal
        )

        var result = CleanVaultResult()
        var trashedPaths: [String] = []
        let fm = FileManager.default

        for (index, url) in scan.orphanFiles.enumerated() {
            let relative = VaultMaintenance.relativeVaultPath(file: url, vaultRoot: root)
            do {
                if fm.fileExists(atPath: url.path) {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                    result.trashed += 1
                    if !relative.isEmpty {
                        trashedPaths.append(relative)
                    }
                }
            } catch {
                result.failed.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }

            if index % 10 == 0 || index == orphanTotal - 1 {
                reportCleanProgress(
                    title: "Cleaning vault…",
                    fileName: url.lastPathComponent,
                    completed: index + 1,
                    total: phaseTotal
                )
                await Task.yield()
            }
        }
        completedPhase = orphanTotal > 0 ? orphanTotal : 0

        if !scan.missingCatalogPaths.isEmpty {
            reportCleanProgress(
                title: "Cleaning vault…",
                fileName: "Removing stale catalog entries…",
                completed: max(completedPhase, 1),
                total: phaseTotal
            )
            try catalog.delete(vaultPaths: scan.missingCatalogPaths)
            result.removedFromCatalog = scan.missingCatalogPaths.count
            VaultMaintenance.pruneAfterRemovingFiles(vaultRoot: root, vaultPaths: scan.missingCatalogPaths)
            completedPhase += 1
        }

        if !trashedPaths.isEmpty {
            VaultMaintenance.pruneAfterRemovingFiles(vaultRoot: root, vaultPaths: trashedPaths)
        }

        reportCleanProgress(
            title: "Cleaning vault…",
            fileName: "Removing empty folders…",
            completed: phaseTotal,
            total: phaseTotal
        )
        result.prunedEmptyFolders = VaultMaintenance.pruneAllEmptyDirectories(vaultRoot: root)

        return try await optimizeCatalogIfNeeded(afterClean: result)
    }

    /// Compacts `catalog.sqlite` when Clean Vault removed stale rows or enough time has passed.
    func optimizeCatalogIfNeeded(afterClean result: CleanVaultResult) async throws -> CleanVaultResult {
        guard let catalog else { return result }
        guard CatalogOptimizationPolicy.shouldOptimize(
            after: result,
            lastOptimizedAt: settings.lastCatalogOptimizationDate
        ) else {
            return result
        }

        cleanUsedProgressPanel = true
        reportCleanProgress(
            title: "Cleaning vault…",
            fileName: "Compacting catalog database…",
            completed: 0,
            total: 1
        )
        await Task.yield()

        var updated = result
        let sizeBefore = catalog.databaseFileSizeBytes()
        try catalog.vacuum()
        settings.recordCatalogOptimization()
        updated.catalogWasOptimized = true
        if let before = sizeBefore, let after = catalog.databaseFileSizeBytes() {
            updated.catalogBytesReclaimed = max(0, before - after)
        }

        reportCleanProgress(
            title: "Cleaning vault…",
            fileName: "Catalog compacted.",
            completed: 1,
            total: 1
        )
        return updated
    }

    /// Move font files into the current layout (FEX A–Z buckets) and sync catalog paths.
    func reorganizeVaultLayout() async throws -> ReorganizeResult {
        guard let root = settings.vaultRootURL else {
            throw CatalogStoreError.vaultNotConfigured
        }
        if catalog == nil {
            try reloadCatalog()
        }
        guard let catalog else {
            throw CatalogStoreError.databaseUnavailable
        }

        isIndexing = true
        reorganizeCancellationRequested = false
        reorganizeWasCancelled = false
        reorganizeUsedProgressPanel = true
        indexProgress = "Scanning vault for fonts…"
        defer {
            isIndexing = false
            reorganizeWasCancelled = reorganizeCancellationRequested
            if !reorganizeUsedProgressPanel {
                onReorganizeProgressState?(nil)
            }
        }

        reportReorganizeProgress(
            title: "Reorganizing vault…",
            fileName: "Scanning font files…",
            completed: 0,
            total: 0
        )
        await Task.yield()

        let engine = LayoutEngine(vaultRoot: root)
        let files = VaultMaintenance.allFontFiles(vaultRoot: root)
        let total = files.count
        var result = ReorganizeResult()
        let fm = FileManager.default

        reportReorganizeProgress(
            title: "Reorganizing vault…",
            fileName: total > 0 ? "Found \(total) font files" : "No font files found",
            completed: 0,
            total: max(total, 1)
        )
        await Task.yield()

        for (index, file) in files.enumerated() {
            if reorganizeCancellationRequested { break }
            let sourceRelative = VaultMaintenance.relativeVaultPath(file: file, vaultRoot: root)
            guard !sourceRelative.isEmpty else { continue }

            do {
                let meta = try FontMetadataReader.read(from: file)
                let fileName = file.lastPathComponent

                let folder = engine.resolveVaultFolderLabel(fullName: meta.fullName, fileName: fileName)

                if engine.isAlreadyCanonical(
                    relativePath: sourceRelative,
                    folderLabel: folder.label,
                    foundry: meta.foundry
                ) {
                    if (try? catalog.vaultPathExists(sourceRelative)) != true {
                        try insertCatalogRecord(for: file, vaultPath: sourceRelative, catalog: catalog)
                        result.catalogAdded += 1
                    }
                    result.unchanged += 1
                    continue
                }

                var targetRelative = engine.canonicalRelativeDestination(
                    folderLabel: folder.label,
                    fileName: fileName,
                    foundry: meta.foundry
                )

                if sourceRelative == targetRelative {
                    if (try? catalog.vaultPathExists(sourceRelative)) != true {
                        try insertCatalogRecord(for: file, vaultPath: sourceRelative, catalog: catalog)
                        result.catalogAdded += 1
                    }
                    result.unchanged += 1
                    continue
                }

                var dest = root.appendingPathComponent(targetRelative)
                if fm.fileExists(atPath: dest.path) {
                    let destRelative = VaultMaintenance.relativeVaultPath(file: dest, vaultRoot: root)
                    if destRelative == sourceRelative {
                        result.unchanged += 1
                        continue
                    }
                    let uniqueName = VaultMaintenance.uniqueFileName(
                        base: fileName,
                        in: dest.deletingLastPathComponent()
                    )
                    targetRelative = (targetRelative as NSString).deletingLastPathComponent + "/" + uniqueName
                    dest = root.appendingPathComponent(targetRelative)
                }

                reportReorganizeProgress(
                    title: "Reorganizing vault…",
                    fileName: file.lastPathComponent,
                    completed: index,
                    total: total
                )
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: file, to: dest)

                if let existing = try catalog.fetchRecord(vaultPath: sourceRelative) {
                    try catalog.delete(vaultPaths: [sourceRelative])
                    var updated = existing
                    updated.databaseID = nil
                    updated.vaultPath = targetRelative
                    updated.fileSize = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? existing.fileSize
                    updated.sha256 = try FontMetadataReader.sha256(of: dest)
                    _ = try catalog.insert(updated)
                } else {
                    try insertCatalogRecord(for: dest, vaultPath: targetRelative, catalog: catalog)
                    result.catalogAdded += 1
                }

                result.moved += 1
            } catch {
                result.failed.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }

            if index % 20 == 0 || index == total - 1 {
                reportReorganizeProgress(
                    title: "Reorganizing vault…",
                    fileName: file.lastPathComponent,
                    completed: index + 1,
                    total: total
                )
                await Task.yield()
            }
        }

        if !reorganizeCancellationRequested {
            _ = VaultMaintenance.pruneAllEmptyDirectories(vaultRoot: root)
        }
        indexProgress = reorganizeWasCancelled
            ? "Reorganize cancelled."
            : "Reorganized \(result.moved) font\(result.moved == 1 ? "" : "s")."
        return result
    }

    private func insertCatalogRecord(for file: URL, vaultPath: String, catalog: CatalogStore) throws {
        let meta = try FontMetadataReader.read(from: file)
        let hash = try FontMetadataReader.sha256(of: file)
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attrs[.size] as? Int64) ?? 0
        let record = FontRecord.from(
            metadata: meta,
            vaultPath: vaultPath,
            sha256: hash,
            fileSize: size,
            dateAdded: Date().timeIntervalSince1970
        )
        _ = try catalog.insert(record)
    }
}

extension ImportResult {
    /// Status bar / legacy one-liner (headline only; use `makeReport` for structured UI).
    static func summaryText(for result: ImportResult, move: Bool) -> String {
        result.makeReport(move: move).summaryLine
    }
}
