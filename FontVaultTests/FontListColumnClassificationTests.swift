import XCTest
@testable import FontVault

final class FontListColumnClassificationTests: XCTestCase {
    private func font(glyphs: Int?, weight: Int?, width: Int?, mono: Bool?) -> FontRecord {
        var details = FontExtractedDetails.empty
        details.glyphCount = glyphs
        details.weightClass = weight
        details.widthClass = width
        details.isFixedPitch = mono
        return FontRecord.from(
            metadata: FontFileMetadata(
                psName: "Test-Regular",
                fullName: "Test Regular",
                nameTableFullName: "Test Regular",
                family: "Test",
                subfamily: "Regular",
                typographicFamily: "",
                typographicSubfamily: "",
                license: "",
                licenseURL: "",
                manufacturerURL: "",
                designerURL: "",
                version: "1.0",
                manufacturer: "",
                vendorID: "",
                copyright: "",
                uniqueName: "",
                description: "",
                designer: "",
                trademark: "",
                isVariable: false,
                format: "otf",
                formatDetailed: "OpenType",
                extractedDetails: details,
                metadataIssues: .empty
            ),
            vaultPath: "A/Test.otf",
            sha256: "abc",
            fileSize: 100,
            dateAdded: 0
        )
    }

    func testClassificationColumnTitles() {
        XCTAssertEqual(FontListColumn.glyphCount.title, "Glyphs")
        XCTAssertEqual(FontListColumn.weightClass.title, "Weight")
        XCTAssertEqual(FontListColumn.widthClass.title, "Width")
        XCTAssertEqual(FontListColumn.mono.title, "Mono")
    }

    func testClassificationCellText() {
        let font = font(glyphs: 1234, weight: 700, width: 5, mono: true)
        XCTAssertEqual(FontListColumn.glyphCount.cellText(for: font), "1234")
        XCTAssertEqual(FontListColumn.weightClass.cellText(for: font), "700")
        XCTAssertEqual(FontListColumn.widthClass.cellText(for: font), "5")
        XCTAssertEqual(FontListColumn.mono.cellText(for: font), "Yes")
    }

    func testClassificationCellTextEmptyWhenUnknown() {
        let font = font(glyphs: nil, weight: nil, width: nil, mono: nil)
        XCTAssertEqual(FontListColumn.glyphCount.tableDisplayText(for: font), "")
        XCTAssertEqual(FontListColumn.mono.tableDisplayText(for: font), "")
    }

    func testClassificationMonoNo() {
        let font = font(glyphs: 1, weight: 400, width: 3, mono: false)
        XCTAssertEqual(FontListColumn.mono.cellText(for: font), "No")
    }

    func testClassificationDatabaseSortColumns() {
        XCTAssertEqual(FontListColumn.glyphCount.databaseSortColumn, "glyphCount")
        XCTAssertEqual(FontListColumn.mono.databaseSortColumn, "isFixedPitch")
    }

    func testCatalogSortExpressionUsesJsonExtract() {
        XCTAssertTrue(
            CatalogBrowseSQL.fontSortExpression(sortColumn: "glyphCount")
                .contains("json_extract(extractedDetails")
        )
    }
}
