import XCTest
@testable import FontVault

final class ImportIssueReviewExporterTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportIssueReviewExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testExportFolderCopiesFilesAndWritesHTML() throws {
        let sourceDir = tempRoot.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir.appendingPathComponent("Bad.otf")
        try Data("fake".utf8).write(to: sourceFile)

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
                ImportReportEntry(
                    sourceURL: sourceFile,
                    outcome: .failed,
                    message: "Corrupt"
                )
            ],
            skippedEntries: [],
            namingFallbackEntries: []
        )

        let parent = tempRoot.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let result = try ImportIssueReviewExporter.exportFolder(
            report: report,
            parentDirectory: parent,
            packageName: "Test Package"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.packageURL.path))
        let failedCopy = result.packageURL
            .appendingPathComponent("Failed/Bad.otf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: failedCopy.path))
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(result.missingCount, 0)

        let htmlURL = result.packageURL.appendingPathComponent("Import Issues.html")
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        XCTAssertTrue(html.contains("Collect &amp; download all"))
        XCTAssertTrue(html.contains("href=\"Failed/Bad.otf\""))
        XCTAssertTrue(html.contains("download=\"Bad.otf\""))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: result.packageURL.appendingPathComponent("README.txt").path
        ))
    }
}
