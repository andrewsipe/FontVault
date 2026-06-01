import XCTest
@testable import FontVault

final class FontListContextMenuContextTests: XCTestCase {
    private func sampleFont(
        licenseURL: String = "https://example.com/license",
        format: String = "otf",
        psName: String = "Example-Regular"
    ) -> FontRecord {
        FontRecord(
            databaseID: nil,
            vaultPath: "A/Example-Regular.otf",
            sha256: "abc",
            fileSize: 1024,
            format: format,
            dateAdded: 1_700_000_000,
            psName: psName,
            fullName: "Example Regular",
            nameTableFullName: "Example Regular",
            family: "Example",
            subfamily: "Regular",
            typographicFamily: "",
            typographicSubfamily: "",
            license: "",
            licenseURL: licenseURL,
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
            formatDetailed: format,
            isVariable: false,
            excludedFromIndex: false,
            extractedDetails: .empty,
            metadataIssues: .empty
        )
    }

    private func context(
        column: FontListColumn?,
        rowKind: FontListContextMenuRowKind,
        selectedFonts: [FontRecord] = []
    ) -> FontListContextMenuContext {
        FontListContextMenuContext(
            rowKind: rowKind,
            clickedColumn: column,
            clickedDisplayText: "",
            selectionCount: selectedFonts.count,
            singleFontSelected: selectedFonts.count == 1,
            browserMode: .allFonts,
            groupByFamily: true,
            showInspector: false,
            selectedFonts: selectedFonts,
            visibleColumns: [.name, .licenseURL, .format],
            vaultRootURL: URL(fileURLWithPath: "/Vault"),
            activeFormatFilter: nil,
            showsExcludedFontsSmartFilter: false
        )
    }

    func testURLValidationRequiresSingleDistinctValue() {
        let font = sampleFont()
        let ctx = context(column: .licenseURL, rowKind: .font(font), selectedFonts: [font])
        XCTAssertNotNil(ctx.urlIfValid)
    }

    func testURLDisabledForAmbiguousMultiSelect() {
        let a = sampleFont(licenseURL: "https://a.example/license")
        let b = sampleFont(licenseURL: "https://b.example/license")
        let ctx = context(column: .licenseURL, rowKind: .font(a), selectedFonts: [a, b])
        XCTAssertNil(ctx.urlIfValid)
    }

    func testFindRequiresNonEmptyUniformValue() {
        let font = sampleFont()
        let ctx = context(column: .postScript, rowKind: .font(font), selectedFonts: [font])
        XCTAssertTrue(ctx.canFind)
        XCTAssertEqual(ctx.findText, font.psName)
    }

    func testFindDisabledWhenNoClickedColumn() {
        let font = sampleFont()
        let ctx = context(column: nil, rowKind: .font(font), selectedFonts: [font])
        XCTAssertFalse(ctx.canFind)
    }

    func testFormatFilterOptionsForFontRow() {
        let font = sampleFont(format: "otf")
        let ctx = context(column: .format, rowKind: .font(font), selectedFonts: [font])
        XCTAssertEqual(ctx.formatFilterMenuOptions.map(\.filterKey), ["otf"])
        XCTAssertEqual(ctx.formatFilterMenuOptions.map(\.badgeLabel), ["OTF"])
    }

    func testShowsClearFormatFilterWhenFormatColumnAndFilterActive() {
        let font = sampleFont()
        var ctx = context(column: .format, rowKind: .font(font), selectedFonts: [font])
        XCTAssertFalse(ctx.showsClearFormatFilter)
        ctx = FontListContextMenuContext(
            rowKind: ctx.rowKind,
            clickedColumn: .format,
            clickedDisplayText: "",
            selectionCount: 1,
            singleFontSelected: true,
            browserMode: ctx.browserMode,
            groupByFamily: ctx.groupByFamily,
            showInspector: ctx.showInspector,
            selectedFonts: [font],
            visibleColumns: ctx.visibleColumns,
            vaultRootURL: ctx.vaultRootURL,
            activeFormatFilter: "otf",
            showsExcludedFontsSmartFilter: false
        )
        XCTAssertTrue(ctx.showsClearFormatFilter)
    }

    func testShowsClearFormatFilterFalseOnNonFormatColumn() {
        let font = sampleFont()
        let ctx = context(
            column: .postScript,
            rowKind: .font(font),
            selectedFonts: [font]
        )
        XCTAssertFalse(ctx.showsClearFormatFilter)
    }

    func testFindRejectsImportDateConflictOnFamilyHeader() {
        let early = sampleFont()
        var late = sampleFont()
        late = FontRecord(
            databaseID: late.databaseID,
            vaultPath: "A/Example-Bold.otf",
            sha256: late.sha256,
            fileSize: late.fileSize,
            format: late.format,
            dateAdded: early.dateAdded + 86_400,
            psName: "Example-Bold",
            fullName: "Example Bold",
            nameTableFullName: "Example Bold",
            family: early.family,
            subfamily: late.subfamily,
            typographicFamily: late.typographicFamily,
            typographicSubfamily: late.typographicSubfamily,
            license: late.license,
            licenseURL: late.licenseURL,
            manufacturerURL: late.manufacturerURL,
            designerURL: late.designerURL,
            version: late.version,
            foundry: late.foundry,
            copyright: late.copyright,
            uniqueName: late.uniqueName,
            description: late.description,
            designer: late.designer,
            trademark: late.trademark,
            manufacturer: late.manufacturer,
            vendorID: late.vendorID,
            formatDetailed: late.formatDetailed,
            isVariable: late.isVariable,
            excludedFromIndex: late.excludedFromIndex,
            extractedDetails: late.extractedDetails,
            metadataIssues: late.metadataIssues
        )
        let section = FontFamilySection(id: "Example", displayName: "Example", fonts: [early, late])
        let ctx = context(
            column: .importDate,
            rowKind: .family(section),
            selectedFonts: [early, late]
        )
        XCTAssertFalse(ctx.canFind)
    }
}
