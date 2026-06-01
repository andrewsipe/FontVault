import XCTest
@testable import FontVault

final class FontListGroupingTests: XCTestCase {
    func testBuildDisplayRowsGroupsAndSortsStyles() {
        let fonts = [
            sample(vaultPath: "A/Aero/Aero-Bold.otf", family: "Aero", fullName: "Aero Bold"),
            sample(vaultPath: "A/Aero/Aero.otf", family: "Aero", fullName: "Aero"),
            sample(vaultPath: "B/Helvetica/Helvetica.otf", family: "Helvetica", fullName: "Helvetica"),
        ]

        let rows = FontListGrouping.buildDisplayRows(
            fonts: fonts,
            sortColumn: "fullName",
            ascending: true,
            collapsedFamilies: []
        )

        XCTAssertEqual(rows.count, 5)
        guard case .family(let first) = rows[0] else {
            return XCTFail("Expected family header first")
        }
        XCTAssertEqual(first.displayName, "Aero")
        XCTAssertEqual(first.styleCount, 2)
        XCTAssertEqual(first.importDateState.tableText, ImportDateDisplay.format(1_700_000_000))

        let paths = FontListGrouping.displayedFontPaths(from: rows)
        XCTAssertEqual(paths, [
            "A/Aero/Aero.otf",
            "A/Aero/Aero-Bold.otf",
            "B/Helvetica/Helvetica.otf",
        ])
    }

    func testCollapsedFamilyHidesChildren() {
        let fonts = [
            sample(vaultPath: "A/Aero/Aero.otf", family: "Aero", fullName: "Aero"),
        ]

        let rows = FontListGrouping.buildDisplayRows(
            fonts: fonts,
            sortColumn: "fullName",
            ascending: true,
            collapsedFamilies: ["Aero"]
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(FontListGrouping.displayedFontPaths(from: rows), [])
    }

    func testUnknownFamilyLabel() {
        let fonts = [sample(vaultPath: "Z/x.otf", family: "  ", fullName: "Mystery")]

        let rows = FontListGrouping.buildDisplayRows(
            fonts: fonts,
            sortColumn: "fullName",
            ascending: true,
            collapsedFamilies: []
        )

        guard case .family(let section) = rows.first else {
            return XCTFail("Expected family header")
        }
        XCTAssertEqual(section.displayName, "Unknown family")
    }

    func testFamilyRowTitleUsesCountInParentheses() {
        XCTAssertEqual(FontListGrouping.familyRowTitle(displayName: "00 Eckmania", styleCount: 6), "00 Eckmania (6)")
        XCTAssertEqual(
            FontListGrouping.exportFolderName(displayName: "00 Eckmania", styleCount: 6),
            "00 Eckmania (6)"
        )
    }

    func testFontsForExportIgnoresChildrenOfSelectedFamily() {
        let sectionA = FontFamilySection(
            id: "Aero",
            displayName: "Aero",
            fonts: [
                sample(vaultPath: "A/a.otf", family: "Aero", fullName: "Aero Regular"),
                sample(vaultPath: "A/a-bold.otf", family: "Aero", fullName: "Aero Bold"),
            ]
        )
        let sectionB = FontFamilySection(
            id: "Gotham",
            displayName: "Gotham",
            fonts: [sample(vaultPath: "G/g.otf", family: "Gotham", fullName: "Gotham Book")]
        )
        let byPath = Dictionary(uniqueKeysWithValues: (sectionA.fonts + sectionB.fonts).map { ($0.vaultPath, $0) })

        let export = FontListGrouping.fontsForExport(
            selectedFamilyIDs: ["Aero"],
            selectedVaultPaths: ["A/a.otf", "G/g.otf"],
            sections: [sectionA, sectionB],
            fontsByVaultPath: byPath
        )

        XCTAssertEqual(Set(export.map(\.vaultPath)), Set(["A/a.otf", "A/a-bold.otf", "G/g.otf"]))
    }

    func testFontsForExportFamilyOnly() {
        let section = FontFamilySection(
            id: "Aero",
            displayName: "Aero",
            fonts: [
                sample(vaultPath: "A/a.otf", family: "Aero", fullName: "Aero"),
                sample(vaultPath: "A/a-bold.otf", family: "Aero", fullName: "Aero Bold"),
            ]
        )
        let byPath = Dictionary(uniqueKeysWithValues: section.fonts.map { ($0.vaultPath, $0) })

        let export = FontListGrouping.fontsForExport(
            selectedFamilyIDs: ["Aero"],
            selectedVaultPaths: [],
            sections: [section],
            fontsByVaultPath: byPath
        )

        XCTAssertEqual(export.count, 2)
    }

    func testFormatAggregateMixedFamily() {
        let fonts = [
            sample(vaultPath: "A/a.otf", family: "Aero", fullName: "Aero", format: "otf"),
            sample(vaultPath: "A/a.ttf", family: "Aero", fullName: "Aero Bold", format: "ttf"),
        ]
        XCTAssertEqual(FontFormat.aggregate(for: fonts), .mixed)
        XCTAssertEqual(FontFormat.aggregate(for: [fonts[0]]), .otf)
        XCTAssertEqual(FontFormat.mixed.badgeLabel, "MIXED")
    }

    func testFamilyKeyPrefersTypographicFamily() {
        var variable = sample(
            vaultPath: "V/Thin.ttf",
            family: "00 Eckmania",
            fullName: "00 Eckmania Variable Thin"
        )
        variable.typographicFamily = "00 Eckmania Variable"
        XCTAssertEqual(FontListGrouping.familyKey(for: variable), "00 Eckmania Variable")
        XCTAssertNotEqual(FontListGrouping.familyKey(for: variable), "00 Eckmania")

        let regular = sample(vaultPath: "A/Reg.otf", family: "00 Eckmania", fullName: "00 Eckmania Regular")
        XCTAssertEqual(FontListGrouping.familyKey(for: regular), "00 Eckmania")
    }

    func testMixGradientFormatsStableOrder() {
        let ordered = FontFormat.mixGradientFormats(fromExtensionStrings: ["woff2", "ttf", "otf"])
        XCTAssertEqual(ordered, [.otf, .ttf, .woff2])
        let colors = FontFormat.mixGradientColors(fromExtensionStrings: ["woff2", "ttf", "otf"])
        XCTAssertEqual(colors.count, 3)
        XCTAssertEqual(colors[0], FontFormat.otf.badgeColors.background)
    }

    private func sample(
        vaultPath: String,
        family: String,
        fullName: String,
        format: String = "otf",
        dateAdded: TimeInterval = 1_700_000_000
    ) -> FontRecord {
        FontRecord(
            databaseID: nil,
            vaultPath: vaultPath,
            sha256: "abc",
            fileSize: 1024,
            format: format,
            dateAdded: dateAdded,
            psName: fullName.replacingOccurrences(of: " ", with: ""),
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
            formatDetailed: "",
            isVariable: false,
            excludedFromIndex: false,
            extractedDetails: .empty,
            metadataIssues: .empty
        )
    }
}
