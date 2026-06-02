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

    /// Single HTML report: summary, folder shortcuts, and one consolidated issue table (links to original import paths).
    static func issueListHTML(from report: ImportReport, generatedAt: Date = Date()) -> String {
        let entries = sortedIssueExportEntries(report)
        let generated = issueListGeneratedTimestamp(generatedAt)
        let headline = htmlEscape(report.importHeadline)
        let failedCount = report.failed.count
        let namingCount = report.namingFallbackEntries.count
        let folderIndex = issueListFolderIndexHTML(entries: entries)
        let rows = entries.map { issueListRowHTML(entry: $0) }.joined()
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
          </style>
        </head>
        <body>
          <h1>FontVault Import Issues</h1>
          <p class="meta">\(headline) · Generated \(generated)<br>
          \(failedCount) failed · \(namingCount) naming review · \(entries.count) row\(entries.count == 1 ? "" : "s")</p>
          <div class="tips">
            <strong>Using this report</strong>
            <ul>
              <li><strong>Folder</strong> links open the import directory in Finder.</li>
              <li><strong>File</strong> links point at the original path (Safari may download the font instead of revealing it).</li>
              <li>In FontVault, <em>Import Details</em> → right-click a row → Reveal in Finder.</li>
            </ul>
          </div>
          \(folderIndex)
          <h2>Issues (\(entries.count))</h2>
          <table>
            <thead>
              <tr><th>Kind</th><th>Folder</th><th>File</th><th>Detail</th></tr>
            </thead>
            <tbody>
        \(rows)  </tbody>
          </table>
        </body>
        </html>
        """
    }

    private static func sortedIssueExportEntries(_ report: ImportReport) -> [ImportReportEntry] {
        issueExportEntries(report).sorted { lhs, rhs in
            let lk = lhs.outcome == .failed ? 0 : 1
            let rk = rhs.outcome == .failed ? 0 : 1
            if lk != rk { return lk < rk }
            return lhs.sourceURL.path.localizedStandardCompare(rhs.sourceURL.path) == .orderedAscending
        }
    }

    private static func issueListRowHTML(entry: ImportReportEntry) -> String {
        let kind = issueKindLabel(for: entry.outcome)
        let kindClass = entry.outcome == .failed ? "kind-failed" : "kind-naming"
        let fileURL = entry.sourceURL
        let folderURL = directoryFileURL(for: fileURL)
        let folderHref = htmlAttributeEscape(folderURL.absoluteString)
        let folderLabel = htmlEscape(folderURL.lastPathComponent.isEmpty ? folderURL.path : folderURL.lastPathComponent)
        let folderPath = htmlAttributeEscape(folderURL.path)
        let fileHref = htmlAttributeEscape(fileURL.absoluteString)
        let fileName = htmlEscape(entry.displayName)
        let fullPath = htmlEscape(fileURL.path)
        let detail = htmlEscape(entry.message)
        return """
          <tr>
            <td class="\(kindClass)">\(htmlEscape(kind))</td>
            <td class="folder"><a href="\(folderHref)" title="\(folderPath)">\(folderLabel)</a></td>
            <td class="file">
              <a href="\(fileHref)" title="\(fullPath)">\(fileName)</a><br>
              <span class="path">\(fullPath)</span>
            </td>
            <td class="detail">\(detail)</td>
          </tr>

        """
    }

    private static func issueListFolderIndexHTML(entries: [ImportReportEntry]) -> String {
        var seen = Set<String>()
        var folders: [URL] = []
        for entry in entries {
            let folder = directoryFileURL(for: entry.sourceURL)
            if seen.insert(folder.path).inserted {
                folders.append(folder)
            }
        }
        folders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !folders.isEmpty else { return "" }
        // Use String concatenation, not `"…\(x)…"` — GRDB in this module hijacks that into SQL literals.
        let items: String = folders.map { folder -> String in
            let href = htmlAttributeEscape(folder.absoluteString)
            let label = htmlEscape(folder.path)
            return "<li><a href=\"" + href + "\">" + label + "</a></li>"
        }.joined(separator: "\n")
        return htmlLiteral(
            """
            <div class="folder-index">
              <strong>Import folders (\(folders.count))</strong>
              <ul>
            """,
            items,
            """
              </ul>
            </div>

            """
        )
    }

    /// Join HTML fragments as plain `String` (avoids GRDB SQL string interpolation in this target).
    private static func htmlLiteral(_ parts: String...) -> String {
        parts.joined()
    }

    /// Directory `file://` URL with trailing slash so browsers open Finder instead of downloading.
    private static func directoryFileURL(for fileURL: URL) -> URL {
        let path = fileURL.deletingLastPathComponent().path
        return URL(fileURLWithPath: path, isDirectory: true)
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
