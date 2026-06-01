import Foundation

enum ImportFileOutcome: String, Sendable {
    /// Font file was scanned but not copied (already in catalog or on disk).
    case skippedAlreadyInVault
    case skippedDestinationExists
    case failed
    /// Font was copied, but vault folder label fell back to the file name (Full name unusable).
    case vaultFolderNamingFallback
}

struct ImportReportEntry: Identifiable, Sendable, Hashable {
    let id: UUID
    let sourceURL: URL
    let displayName: String
    let outcome: ImportFileOutcome
    let message: String

    init(sourceURL: URL, outcome: ImportFileOutcome, message: String) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.displayName = sourceURL.lastPathComponent
        self.outcome = outcome
        self.message = message
    }
}

struct ImportReport: Identifiable, Sendable {
    let id = UUID()
    /// Compact line for the status bar (headline only).
    let summaryLine: String
    let move: Bool
    let scanned: Int
    let imported: Int
    let skipped: Int
    let failedCount: Int
    let ignoredUnsupported: Int
    let ignoredFiltered: Int
    let vaultFolderFallbackCount: Int
    let failed: [ImportReportEntry]
    let skippedEntries: [ImportReportEntry]
    let namingFallbackEntries: [ImportReportEntry]

    var hasInspectableRows: Bool {
        !failed.isEmpty || !skippedEntries.isEmpty || !namingFallbackEntries.isEmpty
    }

    var hasExportableIssueRows: Bool {
        !failed.isEmpty || !namingFallbackEntries.isEmpty
    }

    var ignoredFormatFileCount: Int {
        ignoredUnsupported + ignoredFiltered
    }

    var importHeadline: String {
        ImportReport.headline(imported: imported, move: move)
    }

    /// Multi-line text for alerts when a structured sheet is not used.
    var completionAlertBody: String {
        var lines = [importHeadline, "Scanned \(scanned) · Skipped \(skipped) · Failed \(failedCount)"]
        if ignoredFormatFileCount > 0 {
            lines.append(
                "Not imported: \(ignoredFormatFileCount) file\(ignoredFormatFileCount == 1 ? "" : "s") in the selection were never font candidates (unsupported type or format filter)."
            )
        }
        if vaultFolderFallbackCount > 0 {
            lines.append(
                "\(vaultFolderFallbackCount) imported font\(vaultFolderFallbackCount == 1 ? "" : "s") may need metadata review (vault folder used file name)."
            )
        }
        if hasInspectableRows {
            lines.append("Use View Details for per-file lists and export.")
        }
        return lines.joined(separator: "\n")
    }
}

extension ImportReport {
    private static let issueExportEntries: (ImportReport) -> [ImportReportEntry] = {
        $0.failed + $0.namingFallbackEntries
    }

    /// Tab-separated plain text (clipboard fallback, scripts).
    static func issueListText(from report: ImportReport) -> String {
        issueExportEntries(report).map { entry in
            let kind = issueKindLabel(for: entry.outcome)
            return "\(kind)\t\(entry.sourceURL.path)\t\(entry.message)"
        }.joined(separator: "\n")
    }

    /// HTML import report. When `packageRoot` and `copiedFiles` are set, links are relative and a collect-all download list is included.
    static func issueListHTML(
        from report: ImportReport,
        packageRoot: URL? = nil,
        copiedFiles: [UUID: URL]? = nil,
        generatedAt: Date = Date()
    ) -> String {
        let entries = issueExportEntries(report)
        let generated = issueListGeneratedTimestamp(generatedAt)
        let headline = htmlEscape(report.importHeadline)
        let failedCount = report.failed.count
        let namingCount = report.namingFallbackEntries.count
        let resolveURL: (ImportReportEntry) -> URL = { entry in
            copiedFiles?[entry.id] ?? entry.sourceURL
        }
        let inPackage = packageRoot != nil
        let collectAll = issueListCollectAllHTML(
            entries: entries,
            copiedFiles: copiedFiles ?? [:],
            packageRoot: packageRoot
        )
        let folderIndex = issueListFolderIndexHTML(
            entries: entries,
            resolveURL: resolveURL,
            packageRoot: packageRoot
        )
        let failedSection = issueListSectionHTML(
            title: "Failed",
            entries: report.failed,
            resolveURL: resolveURL,
            packageRoot: packageRoot,
            emptyMessage: nil
        )
        let namingSection = issueListSectionHTML(
            title: "Naming review",
            entries: report.namingFallbackEntries,
            resolveURL: resolveURL,
            packageRoot: packageRoot,
            emptyMessage: nil
        )
        let tips = inPackage ? issueListPackageTipsHTML() : issueListStandaloneTipsHTML()
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>FontVault Import Issues</title>
          <style>
            :root { color-scheme: light dark; }
            body {
              font: 13px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              margin: 24px;
              max-width: 1200px;
            }
            h1 { font-size: 1.25rem; margin: 0 0 0.35rem; }
            h2 { font-size: 1.05rem; margin: 1.5rem 0 0.6rem; }
            .meta { color: #666; margin: 0 0 1rem; font-size: 12px; }
            .tips {
              font-size: 12px;
              color: #444;
              background: #f4f4f5;
              border-radius: 8px;
              padding: 10px 14px;
              margin: 0 0 1.25rem;
            }
            @media (prefers-color-scheme: dark) {
              .meta { color: #aaa; }
              .tips { color: #ccc; background: #2a2a2c; }
            }
            .tips ul { margin: 0.35rem 0 0; padding-left: 1.2rem; }
            .folder-index { margin: 0 0 1.25rem; font-size: 12px; }
            .folder-index ul { margin: 0.35rem 0 0; padding-left: 1.2rem; }
            table { border-collapse: collapse; width: 100%; margin-bottom: 0.5rem; }
            th, td { text-align: left; vertical-align: top; padding: 8px 12px; border-bottom: 1px solid #ccc; }
            th { font-size: 12px; text-transform: uppercase; letter-spacing: 0.02em; background: #f4f4f5; }
            @media (prefers-color-scheme: dark) {
              th { background: #2a2a2c; }
              th, td { border-bottom-color: #444; }
            }
            .kind-failed { color: #c41e3a; font-weight: 600; white-space: nowrap; }
            .kind-naming { color: #b45309; font-weight: 600; white-space: nowrap; }
            .folder a { word-break: break-all; }
            .filename { font-weight: 500; }
            .path { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11px; color: #666; word-break: break-all; }
            @media (prefers-color-scheme: dark) { .path { color: #999; } }
            .detail { color: #444; max-width: 28rem; }
            @media (prefers-color-scheme: dark) { .detail { color: #bbb; } }
            .collect-all { margin: 0 0 1.25rem; font-size: 12px; }
            .collect-all ul { margin: 0.5rem 0 0; padding-left: 1.2rem; columns: 2; column-gap: 2rem; }
            @media (max-width: 720px) { .collect-all ul { columns: 1; } }
            .collect-all li { margin-bottom: 0.35rem; break-inside: avoid; }
            .collect-all .missing { color: #888; font-style: italic; }
          </style>
        </head>
        <body>
          <h1>FontVault Import Issues</h1>
          <p class="meta">\(headline) · Generated \(generated)<br>
          \(failedCount) failed · \(namingCount) naming review · \(entries.count) row\(entries.count == 1 ? "" : "s")</p>
          \(tips)
          \(collectAll)
          \(folderIndex)
          \(failedSection)
          \(namingSection)
        </body>
        </html>
        """
    }

    private static func issueListPackageTipsHTML() -> String {
        """
        <div class="tips">
          <strong>Review package</strong>
          <ul>
            <li>Flagged files were copied into this folder (<code>Failed/</code>, <code>Naming/</code>).</li>
            <li><strong>Collect &amp; download all</strong> — use the links below (or open subfolders in Finder).</li>
            <li>Original import sources were not modified.</li>
          </ul>
        </div>
        """
    }

    private static func issueListStandaloneTipsHTML() -> String {
        """
        <div class="tips">
          <strong>Report only</strong>
          <ul>
            <li>This HTML does not include file copies. In FontVault use <strong>Save Review Package…</strong> to collect all flagged files into a folder with this report.</li>
            <li>For Reveal in Finder on a specific file, use <em>Import Details</em> (View Details…).</li>
          </ul>
        </div>
        """
    }

    private static func issueListCollectAllHTML(
        entries: [ImportReportEntry],
        copiedFiles: [UUID: URL],
        packageRoot: URL?
    ) -> String {
        guard let packageRoot, !entries.isEmpty else { return "" }
        let sorted = entries.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        let items = sorted.map { entry -> String in
            let kind = issueKindLabel(for: entry.outcome)
            let kindClass = entry.outcome == .failed ? "kind-failed" : "kind-naming"
            guard let copied = copiedFiles[entry.id] else {
                return "<li class=\"missing\">\(htmlEscape(kind)): \(htmlEscape(entry.displayName)) (not copied — missing at export)</li>"
            }
            let rel = packageRelativePath(fileURL: copied, packageRoot: packageRoot)
            let href = htmlAttributeEscape(rel)
            let name = htmlEscape(copied.lastPathComponent)
            let download = htmlAttributeEscape(copied.lastPathComponent)
            return "<li><span class=\"\(kindClass)\">\(htmlEscape(kind))</span> <a href=\"\(href)\" download=\"\(download)\">\(name)</a></li>"
        }.joined(separator: "\n")
        let copiedCount = entries.filter { copiedFiles[$0.id] != nil }.count
        return """
        <div class="collect-all">
          <h2>Collect &amp; download all (\(copiedCount))</h2>
          <p>Copies are in this folder. Click a file to download it, or <a href="./">open this package folder</a> in Finder.</p>
          <ul>
        \(items)
          </ul>
        </div>
        """
    }

    private static func issueListSectionHTML(
        title: String,
        entries: [ImportReportEntry],
        resolveURL: (ImportReportEntry) -> URL,
        packageRoot: URL?,
        emptyMessage: String?
    ) -> String {
        guard !entries.isEmpty else {
            guard let emptyMessage else { return "" }
            return "<p class=\"meta\">\(htmlEscape(emptyMessage))</p>\n"
        }
        let rows = entries.map {
            issueListRowHTML(entry: $0, fileURL: resolveURL($0), packageRoot: packageRoot)
        }.joined()
        return """
        <h2>\(htmlEscape(title)) (\(entries.count))</h2>
        <table>
          <thead>
            <tr><th>Kind</th><th>Folder</th><th>File</th><th>Detail</th></tr>
          </thead>
          <tbody>
        \(rows)  </tbody>
        </table>

        """
    }

    private static func issueListRowHTML(
        entry: ImportReportEntry,
        fileURL: URL,
        packageRoot: URL?
    ) -> String {
        let kind = issueKindLabel(for: entry.outcome)
        let kindClass = entry.outcome == .failed ? "kind-failed" : "kind-naming"
        let folderURL = directoryFileURL(for: fileURL)
        let folderHref = issueListHref(for: folderURL, packageRoot: packageRoot, isDirectory: true)
        let folderLabel = htmlEscape(folderURL.lastPathComponent.isEmpty ? folderURL.path : folderURL.lastPathComponent)
        let folderPath = htmlAttributeEscape(folderURL.path)
        let fileName = htmlEscape(fileURL.lastPathComponent)
        let fullPath = htmlEscape(fileURL.path)
        let detail = htmlEscape(entry.message)
        let fileLink: String
        if packageRoot != nil {
            let rel = issueListHref(for: fileURL, packageRoot: packageRoot, isDirectory: false)
            let download = htmlAttributeEscape(fileURL.lastPathComponent)
            fileLink = "<a href=\"\(rel)\" download=\"\(download)\">\(fileName)</a>"
        } else {
            fileLink = "<span class=\"filename\">\(fileName)</span>"
        }
        return """
          <tr>
            <td class="\(kindClass)">\(htmlEscape(kind))</td>
            <td class="folder"><a href="\(folderHref)" title="\(folderPath)">\(folderLabel)</a></td>
            <td class="file">
              \(fileLink)<br>
              <span class="path">\(fullPath)</span>
            </td>
            <td class="detail">\(detail)</td>
          </tr>

        """
    }

    private static func issueListFolderIndexHTML(
        entries: [ImportReportEntry],
        resolveURL: (ImportReportEntry) -> URL,
        packageRoot: URL?
    ) -> String {
        var seen = Set<String>()
        var folders: [URL] = []
        for entry in entries {
            let fileURL = resolveURL(entry)
            let folder = directoryFileURL(for: fileURL)
            let key = folder.path
            if seen.insert(key).inserted {
                folders.append(folder)
            }
        }
        folders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !folders.isEmpty else { return "" }
        let items = folders.map { folder in
            let href = issueListHref(for: folder, packageRoot: packageRoot, isDirectory: true)
            let label = htmlEscape(
                packageRoot != nil
                    ? packageRelativePath(fileURL: folder, packageRoot: packageRoot!) + "/"
                    : folder.path
            )
            return "<li><a href=\"\(href)\">\(label)</a></li>"
        }.joined(separator: "\n")
        return """
        <div class="folder-index">
          <strong>Folders in this report (\(folders.count))</strong>
          <ul>
        \(items)
          </ul>
        </div>

        """
    }

    /// Directory `file://` URL with trailing slash so browsers open Finder instead of downloading.
    private static func directoryFileURL(for fileURL: URL) -> URL {
        let path = fileURL.deletingLastPathComponent().path
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func packageRelativePath(fileURL: URL, packageRoot: URL) -> String {
        let root = packageRoot.standardizedFileURL.path
        let file = fileURL.standardizedFileURL.path
        guard file.hasPrefix(root + "/") else { return fileURL.lastPathComponent }
        return String(file.dropFirst(root.count + 1))
    }

    private static func issueListHref(for url: URL, packageRoot: URL?, isDirectory: Bool) -> String {
        if let packageRoot {
            var rel = packageRelativePath(fileURL: url, packageRoot: packageRoot)
            if isDirectory, !rel.hasSuffix("/") { rel += "/" }
            return htmlAttributeEscape(rel)
        }
        let target = isDirectory ? url : url
        return htmlAttributeEscape((isDirectory ? directoryFileURL(for: url) : target).absoluteString)
    }

    static func defaultIssueListFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "FontVault Import Issues \(formatter.string(from: date)).html"
    }

    private static func issueKindLabel(for outcome: ImportFileOutcome) -> String {
        outcome == .failed ? "Failed" : "Naming"
    }

    private static func issueListGeneratedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return htmlEscape(formatter.string(from: date))
    }

    private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func htmlAttributeEscape(_ text: String) -> String {
        htmlEscape(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Backward-compatible alias for export helpers.
    static func failureListText(from report: ImportReport) -> String {
        issueListText(from: report)
    }

    static func defaultFailureListFilename(date: Date = Date()) -> String {
        defaultIssueListFilename(date: date)
    }

    static func headline(imported: Int, move: Bool) -> String {
        let verb = move ? "Moved" : "Copied"
        return "\(verb) \(imported) font\(imported == 1 ? "" : "s") into the vault"
    }
}

extension ImportResult {
    var failedCount: Int {
        entries.filter { $0.outcome == .failed }.count
    }

    func makeReport(move: Bool) -> ImportReport {
        let failedEntries = entries.filter { $0.outcome == .failed }
        let skippedEntries = entries.filter {
            $0.outcome == .skippedAlreadyInVault || $0.outcome == .skippedDestinationExists
        }
        let namingEntries = entries.filter { $0.outcome == .vaultFolderNamingFallback }
        return ImportReport(
            summaryLine: ImportReport.headline(imported: imported, move: move),
            move: move,
            scanned: scanned,
            imported: imported,
            skipped: skipped,
            failedCount: failedEntries.count,
            ignoredUnsupported: ignoredUnsupportedFormat,
            ignoredFiltered: ignoredFilteredFormat,
            vaultFolderFallbackCount: namingEntries.isEmpty ? vaultFolderFallbackCount : namingEntries.count,
            failed: failedEntries,
            skippedEntries: skippedEntries,
            namingFallbackEntries: namingEntries
        )
    }

    mutating func recordSkipped(
        file: URL,
        outcome: ImportFileOutcome,
        message: String
    ) {
        skipped += 1
        entries.append(ImportReportEntry(sourceURL: file, outcome: outcome, message: message))
    }

    mutating func recordFailed(file: URL, message: String) {
        entries.append(
            ImportReportEntry(sourceURL: file, outcome: .failed, message: message)
        )
    }

    mutating func recordNamingFallback(file: URL, message: String) {
        vaultFolderFallbackCount += 1
        entries.append(
            ImportReportEntry(sourceURL: file, outcome: .vaultFolderNamingFallback, message: message)
        )
    }
}
