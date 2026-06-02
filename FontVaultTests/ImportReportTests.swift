import XCTest
@testable import FontVault

final class ImportReportTests: XCTestCase {
    private func sampleEntry(
        name: String,
        outcome: ImportFileOutcome,
        message: String
    ) -> ImportReportEntry {
        ImportReportEntry(
            sourceURL: URL(fileURLWithPath: "/tmp/\(name)"),
            outcome: outcome,
            message: message
        )
    }

    func testMakeReportCleanImportHasNoInspectableRows() {
        var result = ImportResult()
        result.scanned = 5
        result.imported = 5
        let report = result.makeReport(move: false)

        XCTAssertFalse(report.hasInspectableRows)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertTrue(report.skippedEntries.isEmpty)
    }

    func testMakeReportFailedAndSkippedSections() {
        var result = ImportResult()
        result.scanned = 3
        result.imported = 1
        result.recordSkipped(
            file: URL(fileURLWithPath: "/tmp/Existing.otf"),
            outcome: .skippedAlreadyInVault,
            message: "Already in vault"
        )
        result.recordFailed(file: URL(fileURLWithPath: "/tmp/Bad.otf"), message: "Could not read font")

        let report = result.makeReport(move: true)

        XCTAssertTrue(report.hasInspectableRows)
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertEqual(report.skippedEntries.count, 1)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.skipped, 1)
        XCTAssertTrue(report.summaryLine.contains("Moved"))
    }

    func testNamingFallbackEnablesExportAndInspectableRows() {
        var result = ImportResult()
        result.imported = 2
        result.scanned = 2
        result.recordNamingFallback(
            file: URL(fileURLWithPath: "/tmp/A.otf"),
            message: "Vault folder uses file name"
        )
        let report = result.makeReport(move: false)

        XCTAssertEqual(report.namingFallbackEntries.count, 1)
        XCTAssertTrue(report.hasInspectableRows)
        XCTAssertTrue(report.hasExportableIssueRows)
        XCTAssertTrue(ImportReport.issueListText(from: report).contains("Naming"))
    }

    func testFailureListTextFormat() {
        let report = ImportReport(
            summaryLine: "test",
            move: false,
            scanned: 1,
            imported: 0,
            skipped: 0,
            failedCount: 1,
            ignoredUnsupported: 0,
            ignoredFiltered: 0,
            vaultFolderFallbackCount: 0,
            failed: [
                sampleEntry(name: "Bad.otf", outcome: .failed, message: "Corrupt file")
            ],
            skippedEntries: [],
            namingFallbackEntries: []
        )
        let text = ImportReport.issueListText(from: report)
        XCTAssertTrue(text.contains("/tmp/Bad.otf"))
        XCTAssertTrue(text.contains("Corrupt file"))
        XCTAssertTrue(text.contains("\t"))
    }

    func testIssueListHTMLUsesFolderLinksNotFileDownloads() {
        let path = "/tmp/Bulk-Up#1.woff2"
        let report = ImportReport(
            summaryLine: "test",
            move: false,
            scanned: 1,
            imported: 1,
            skipped: 0,
            failedCount: 0,
            ignoredUnsupported: 0,
            ignoredFiltered: 0,
            vaultFolderFallbackCount: 1,
            failed: [],
            skippedEntries: [],
            namingFallbackEntries: [
                ImportReportEntry(
                    sourceURL: URL(fileURLWithPath: path),
                    outcome: .vaultFolderNamingFallback,
                    message: "Vault folder uses file name"
                )
            ]
        )
        let html = ImportReport.issueListHTML(from: report)
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("Issues (1)"))
        XCTAssertTrue(html.contains("kind-naming"))
        XCTAssertTrue(html.contains("Bulk-Up") && html.contains("href=\"file://"))
        XCTAssertTrue(html.contains("Import folders"))
        XCTAssertTrue(html.contains("Bulk-Up#1.woff2"))
        XCTAssertTrue(html.contains("Vault folder uses file name"))
        XCTAssertTrue(ImportReport.defaultIssueListFilename().hasSuffix(".html"))
    }

    func testIssueListHTMLFolderIndexIsPlainTextNotGRDBSQL() {
        let report = ImportReport(
            summaryLine: "test",
            move: false,
            scanned: 2,
            imported: 2,
            skipped: 0,
            failedCount: 0,
            ignoredUnsupported: 0,
            ignoredFiltered: 0,
            vaultFolderFallbackCount: 2,
            failed: [],
            skippedEntries: [],
            namingFallbackEntries: [
                ImportReportEntry(
                    sourceURL: URL(fileURLWithPath: "/tmp/import/A.otf"),
                    outcome: .vaultFolderNamingFallback,
                    message: "Naming"
                ),
                ImportReportEntry(
                    sourceURL: URL(fileURLWithPath: "/tmp/import/B.otf"),
                    outcome: .vaultFolderNamingFallback,
                    message: "Naming"
                ),
            ]
        )
        let html = ImportReport.issueListHTML(from: report)
        XCTAssertTrue(html.contains("Import folders (1)"))
        XCTAssertTrue(html.contains("<li><a href=\"file:///tmp/import/\">"))
        XCTAssertFalse(html.contains("GRDB"))
        XCTAssertFalse(html.contains("SQL(elements"))
    }
}
