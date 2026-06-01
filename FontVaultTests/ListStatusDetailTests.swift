import XCTest
@testable import FontVault

final class ListStatusDetailTests: XCTestCase {
    private func sampleFont(psName: String = "Bad_PS", metadataIssues: FontMetadataIssues = .empty) -> FontRecord {
        FontRecord(
            databaseID: nil,
            vaultPath: "A/Bad.otf",
            sha256: "abc",
            fileSize: 1024,
            format: "otf",
            dateAdded: 1_700_000_000,
            psName: psName,
            fullName: "Bad Regular",
            nameTableFullName: "Bad Regular",
            family: "Bad",
            subfamily: "Regular",
            typographicFamily: "",
            typographicSubfamily: "",
            license: "",
            licenseURL: "https://example.com/license",
            manufacturerURL: "",
            designerURL: "",
            version: "1.0",
            foundry: "",
            copyright: "",
            uniqueName: "",
            description: "",
            designer: "",
            trademark: "",
            manufacturer: "",
            vendorID: "",
            formatDetailed: "otf",
            isVariable: false,
            excludedFromIndex: false,
            extractedDetails: .empty,
            metadataIssues: metadataIssues
        )
    }

    func testPostScriptColumnShowsMetadataWarning() {
        var issues = FontMetadataIssues.empty
        issues.setIssues([.postScriptNameFilenameMismatch], for: .psName)
        let font = sampleFont(metadataIssues: issues)

        let detail = ListStatusDetail.forFont(font, column: .postScript, source: .hover)

        XCTAssertNotNil(detail?.metadataWarning)
        XCTAssertEqual(detail?.metadataWarning, .postScriptNameFilenameMismatch)
    }

    func testImportDateColumnDoesNotBleedPostScriptWarning() {
        var issues = FontMetadataIssues.empty
        issues.setIssues([.postScriptNameFilenameMismatch], for: .psName)
        let font = sampleFont(metadataIssues: issues)

        let detail = ListStatusDetail.forFont(font, column: .importDate, source: .hover)

        XCTAssertNotNil(detail)
        XCTAssertNil(detail?.metadataWarning)
        XCTAssertEqual(detail?.rowHasMetadataIssue, true)
        XCTAssertFalse(detail?.rowMetadataIssueTooltip.isEmpty == true)
        XCTAssertTrue(detail?.glanceLine.contains("Import Date:") == true)
        XCTAssertFalse(detail?.tooltipLine.contains("does not match") == true)
    }

    func testGlanceLineIncludesColumnTitle() {
        let font = sampleFont(psName: "Example-Regular")
        let detail = ListStatusDetail.forFont(font, column: .postScript, source: .selection)

        XCTAssertEqual(detail?.glanceLine, "PostScript: Example-Regular")
    }

    func testMetadataWarningsDisabledClearsRowAndColumnWarnings() {
        let key = VaultSettings.Keys.showMetadataWarnings
        let defaults = UserDefaults.standard
        let hadKey = defaults.object(forKey: key) != nil
        let saved = hadKey ? defaults.bool(forKey: key) : true
        defer {
            if hadKey {
                defaults.set(saved, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.set(false, forKey: key)

        var issues = FontMetadataIssues.empty
        issues.setIssues([.postScriptNameFilenameMismatch], for: .psName)
        let font = sampleFont(metadataIssues: issues)
        let detail = ListStatusDetail.forFont(font, column: .postScript, source: .hover)

        XCTAssertEqual(detail?.rowHasMetadataIssue, false)
        XCTAssertNil(detail?.metadataWarning)
    }

    func testURLColumnTooltipIncludesLinkHintWithoutWarning() {
        let font = sampleFont()
        let detail = ListStatusDetail.forFont(font, column: .licenseURL, source: .hover)

        XCTAssertNotNil(detail)
        XCTAssertNil(detail?.metadataWarning)
        XCTAssertTrue(detail?.showsLinkOpenHint == true)
        XCTAssertTrue(detail?.tooltipLine.contains(StatusBarCopy.linkOpenHint) == true)
    }
}
