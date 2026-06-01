import Foundation

/// Non-destructive copy of import-flagged source files plus an HTML report for offline review.
enum ImportIssueReviewExporter {
    struct Result: Sendable {
        let packageURL: URL
        let copiedCount: Int
        let missingCount: Int
    }

    enum ExportError: LocalizedError {
        case noExportableRows
        case packageAlreadyExists(URL)

        var errorDescription: String? {
            switch self {
            case .noExportableRows:
                return "No failed or naming-review files to export."
            case .packageAlreadyExists(let url):
                return "A folder already exists at \(url.path)."
            }
        }
    }

    static func defaultPackageFolderName(date: Date = Date()) -> String {
        ImportReport.defaultIssueListFilename(date: date)
            .replacingOccurrences(of: ".html", with: "")
    }

    /// Creates `FontVault Import Issues …/` with `Failed/`, `Naming/`, file copies, and `Import Issues.html`.
    static func exportFolder(
        report: ImportReport,
        parentDirectory: URL,
        packageName: String = defaultPackageFolderName(),
        fileManager: FileManager = .default
    ) throws -> Result {
        let entries = exportableEntries(from: report)
        guard !entries.isEmpty else { throw ExportError.noExportableRows }

        let packageURL = uniquePackageURL(
            parent: parentDirectory,
            baseName: packageName,
            fileManager: fileManager
        )
        if fileManager.fileExists(atPath: packageURL.path) {
            throw ExportError.packageAlreadyExists(packageURL)
        }

        let failedDir = packageURL.appendingPathComponent("Failed", isDirectory: true)
        let namingDir = packageURL.appendingPathComponent("Naming", isDirectory: true)
        try fileManager.createDirectory(at: failedDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: namingDir, withIntermediateDirectories: true)

        var copiedByEntryID: [UUID: URL] = [:]
        var copiedCount = 0
        var missingCount = 0

        for entry in entries {
            let destDir = entry.outcome == .failed ? failedDir : namingDir
            guard fileManager.fileExists(atPath: entry.sourceURL.path) else {
                missingCount += 1
                continue
            }
            let destURL = uniqueFileURL(in: destDir, fileName: entry.displayName, fileManager: fileManager)
            try fileManager.copyItem(at: entry.sourceURL, to: destURL)
            copiedByEntryID[entry.id] = destURL
            copiedCount += 1
        }

        let html = ImportReport.issueListHTML(
            from: report,
            packageRoot: packageURL,
            copiedFiles: copiedByEntryID
        )
        let htmlURL = packageURL.appendingPathComponent("Import Issues.html")
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)

        let readme = readmeText(report: report, copiedCount: copiedCount, missingCount: missingCount)
        try readme.write(
            to: packageURL.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        return Result(packageURL: packageURL, copiedCount: copiedCount, missingCount: missingCount)
    }

    // MARK: - Private

    private static func exportableEntries(from report: ImportReport) -> [ImportReportEntry] {
        report.failed + report.namingFallbackEntries
    }

    private static func uniquePackageURL(
        parent: URL,
        baseName: String,
        fileManager: FileManager
    ) -> URL {
        var candidate = parent.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName) (\(suffix))", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private static func uniqueFileURL(
        in directory: URL,
        fileName: String,
        fileManager: FileManager
    ) -> URL {
        var candidate = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let nsName = fileName as NSString
        let base = nsName.deletingPathExtension
        let ext = nsName.pathExtension
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let stem = ext.isEmpty ? "\(base) (\(suffix))" : "\(base) (\(suffix)).\(ext)"
            candidate = directory.appendingPathComponent(stem)
            suffix += 1
        }
        return candidate
    }

    private static func readmeText(report: ImportReport, copiedCount: Int, missingCount: Int) -> String {
        var lines = [
            "FontVault Import Issues — Review Package",
            "",
            report.importHeadline,
            "Generated: \(Date())",
            "",
            "Flagged source files were copied here (non-destructive). Originals were not modified.",
            "",
            "Open Import Issues.html in a browser.",
            "Use “Collect & download all” in the report to save individual copies.",
            "",
            "  Failed/   — fonts that could not be imported",
            "  Naming/   — fonts imported but vault folder used the file name",
            "",
            "Copied: \(copiedCount)",
        ]
        if missingCount > 0 {
            lines.append("Missing at export time (listed in HTML only): \(missingCount)")
        }
        return lines.joined(separator: "\n")
    }
}
