import XCTest
@testable import FontVault

final class FontListStyleSortTests: XCTestCase {
    func testStyleSortOrdersWidthWeightSlopeThenName() {
        let condensedLight = styleRecord(
            path: "a/CondLight.otf",
            fullName: "Acme Condensed Light",
            widthClass: 3,
            weightClass: 300,
            italic: false
        )
        let condensedLightItalic = styleRecord(
            path: "a/CondLightIt.otf",
            fullName: "Acme Condensed Light Italic",
            widthClass: 3,
            weightClass: 300,
            italic: true
        )
        let regular = styleRecord(
            path: "a/Regular.otf",
            fullName: "Acme Regular",
            widthClass: 5,
            weightClass: 400,
            italic: false
        )
        let bold = styleRecord(
            path: "a/Bold.otf",
            fullName: "Acme Bold",
            widthClass: 5,
            weightClass: 700,
            italic: false
        )

        let sorted = [bold, condensedLightItalic, regular, condensedLight].sorted {
            FontListStyleSort.compare($0, $1, ascending: true)
        }

        XCTAssertEqual(
            sorted.map(\.vaultPath),
            ["a/CondLight.otf", "a/CondLightIt.otf", "a/Regular.otf", "a/Bold.otf"]
        )
    }

    func testGroupedDisplayRowsUseStyleOrderWithinFamily() {
        let fonts = [
            styleRecord(path: "a/Bold.otf", fullName: "Acme Bold", widthClass: 5, weightClass: 700, italic: false),
            styleRecord(path: "a/Regular.otf", fullName: "Acme Regular", widthClass: 5, weightClass: 400, italic: false),
            styleRecord(
                path: "b/Light.ttf",
                fullName: "Beta Light",
                family: "Beta",
                widthClass: 5,
                weightClass: 300,
                italic: false
            ),
        ]

        let rows = FontListGrouping.buildDisplayRows(
            fonts: fonts,
            sortColumn: FontListSortPreset.styleOrderSortColumn,
            ascending: true,
            collapsedFamilies: []
        )

        XCTAssertEqual(rows.count, 5)
        let paths = FontListGrouping.displayedFontPaths(from: rows)
        XCTAssertEqual(paths, ["a/Regular.otf", "a/Bold.otf", "b/Light.ttf"])
    }

    func testPresetSortColumns() {
        XCTAssertEqual(FontListSortPreset.byName.sortColumn, "fullName")
        XCTAssertEqual(FontListSortPreset.styleOrder.sortColumn, "styleOrder")
        XCTAssertTrue(FontListSortPreset.isPresetSortColumn("fullName"))
        XCTAssertTrue(FontListSortPreset.isPresetSortColumn("styleOrder"))
        XCTAssertFalse(FontListSortPreset.isPresetSortColumn("weightClass"))
    }

    private func styleRecord(
        path: String,
        fullName: String,
        family: String = "Acme",
        widthClass: Int,
        weightClass: Int,
        italic: Bool
    ) -> FontRecord {
        var details = FontExtractedDetails.empty
        details.widthClass = widthClass
        details.weightClass = weightClass
        details.fsSelectionItalic = italic
        if italic {
            details.italicAngle = -12.0
        }
        return FontRecord(
            databaseID: nil,
            vaultPath: path,
            sha256: path,
            fileSize: 100,
            format: "otf",
            dateAdded: 0,
            psName: fullName,
            fullName: fullName,
            nameTableFullName: fullName,
            family: family,
            subfamily: "Regular",
            typographicFamily: "",
            typographicSubfamily: "",
            license: "",
            licenseURL: "",
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
            extractedDetails: details,
            metadataIssues: .empty
        )
    }
}
