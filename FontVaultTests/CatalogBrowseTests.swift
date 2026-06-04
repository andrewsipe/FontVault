import XCTest
@testable import FontVault

final class CatalogBrowseTests: XCTestCase {
    private var store: CatalogStore!

    override func setUpWithError() throws {
        store = try CatalogStore.makeInMemoryForTests()
        try seedFonts()
    }

    private func seedFonts() throws {
        let day1: TimeInterval = 1_700_000_000
        let day2: TimeInterval = 1_700_086_400
        let records = [
            makeRecord(
                path: "a/Regular.otf", family: "Acme", fullName: "Acme Regular", format: "otf", size: 100, date: day1,
                sha256: "hash-acme", manufacturer: "DOUBLE ZERO", vendorID: "DBZR"
            ),
            makeRecord(
                path: "a/Bold.otf", family: "Acme", fullName: "Acme Bold", format: "otf", size: 200, date: day1,
                sha256: "hash-acme", manufacturer: "DOUBLE ZERO", vendorID: "DBZR"
            ),
            makeRecord(path: "b/Light.ttf", family: "Beta", fullName: "Beta Light", format: "ttf", size: 50, date: day2, sha256: "hash-beta"),
            makeRecord(path: "u/x.otf", family: "", fullName: "Orphan", format: "otf", size: 10, date: day1, sha256: "hash-orphan")
        ]
        for record in records {
            _ = try store.insert(record)
        }
    }

    func testStyleOrderSortWithinFamily() throws {
        guard var regular = try store.fetchRecord(vaultPath: "a/Regular.otf"),
              var bold = try store.fetchRecord(vaultPath: "a/Bold.otf") else {
            XCTFail("missing seed fonts")
            return
        }
        regular.extractedDetails.widthClass = 5
        regular.extractedDetails.weightClass = 400
        bold.extractedDetails.widthClass = 5
        bold.extractedDetails.weightClass = 700
        var condensed = makeRecord(
            path: "a/Cond.otf", family: "Acme", fullName: "Acme Condensed", format: "otf", size: 150, date: 1_700_000_000
        )
        condensed.extractedDetails.widthClass = 3
        condensed.extractedDetails.weightClass = 400
        try store.update(regular)
        try store.update(bold)
        _ = try store.insert(condensed)

        let fonts = try store.fetchFontsForFamily(
            familyKey: "Acme",
            query: FontTableBrowseQuery(),
            sortColumn: FontListSortPreset.styleOrderSortColumn,
            ascending: true
        )
        XCTAssertEqual(fonts.map(\.vaultPath), ["a/Cond.otf", "a/Regular.otf", "a/Bold.otf"])
    }

    func testStyleOrderFlatListPaths() throws {
        guard var regular = try store.fetchRecord(vaultPath: "a/Regular.otf"),
              var beta = try store.fetchRecord(vaultPath: "b/Light.ttf") else {
            XCTFail("missing seed fonts")
            return
        }
        regular.extractedDetails.widthClass = 5
        regular.extractedDetails.weightClass = 400
        beta.extractedDetails.widthClass = 3
        beta.extractedDetails.weightClass = 300
        try store.update(regular)
        try store.update(beta)

        let paths = try store.fetchOrderedVaultPaths(
            query: FontTableBrowseQuery(),
            sortColumn: FontListSortPreset.styleOrderSortColumn,
            ascending: true,
            limit: 10,
            offset: 0
        )
        let betaIndex = paths.firstIndex(of: "b/Light.ttf")
        let regularIndex = paths.firstIndex(of: "a/Regular.otf")
        XCTAssertNotNil(betaIndex)
        XCTAssertNotNil(regularIndex)
        XCTAssertLessThan(betaIndex!, regularIndex!)
    }

    func testStyleOrderFamilySummariesAlphabetical() throws {
        let summaries = try store.fetchFamilySummaries(
            query: FontTableBrowseQuery(),
            sortColumn: FontListSortPreset.styleOrderSortColumn,
            ascending: true
        )
        let keys = summaries.map(\.id).filter { $0 != "_Unknown" }
        XCTAssertEqual(keys, keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    private func makeRecord(
        path: String,
        family: String,
        fullName: String,
        format: String,
        size: Int64,
        date: TimeInterval,
        sha256: String? = nil,
        manufacturer: String = "",
        vendorID: String = ""
    ) -> FontRecord {
        FontRecord(
            databaseID: nil,
            vaultPath: path,
            sha256: sha256 ?? path,
            fileSize: size,
            format: format,
            dateAdded: date,
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
            manufacturer: manufacturer,
            vendorID: vendorID,
            formatDetailed: format,
            isVariable: false,
            excludedFromIndex: false,
            extractedDetails: .empty,
            metadataIssues: .empty
        )
    }

    func testFamilySummariesCountAndUnknownKey() throws {
        let summaries = try store.fetchFamilySummaries(query: FontTableBrowseQuery())
        XCTAssertEqual(summaries.count, 3)
        XCTAssertTrue(summaries.contains { $0.id == "_Unknown" })
        let acme = summaries.first { $0.id == "Acme" }
        XCTAssertEqual(acme?.styleCount, 2)
        XCTAssertEqual(acme?.totalSize, 300)
    }

    func testFilteredFontCount() throws {
        XCTAssertEqual(try store.filteredFontCount(query: FontTableBrowseQuery()), 4)
        XCTAssertEqual(try store.filteredFontCount(query: FontTableBrowseQuery(format: "otf")), 3)
        XCTAssertEqual(try store.filteredFontCount(query: FontTableBrowseQuery(search: "Beta")), 1)
    }

    func testExcludedFontsHiddenFromDefaultBrowse() throws {
        _ = try store.setExcludedFromIndex(vaultPaths: ["u/x.otf"], excluded: true)
        XCTAssertEqual(try store.filteredFontCount(query: FontTableBrowseQuery()), 3)
        XCTAssertEqual(try store.excludedFontCount(), 1)
        let shown = try store.filteredFontCount(
            query: FontTableBrowseQuery(showIgnoredFonts: true)
        )
        XCTAssertEqual(shown, 4)
        let excludedOnly = try store.filteredFontCount(
            query: FontTableBrowseQuery(tableScope: .excludedFontsOnly, showIgnoredFonts: true)
        )
        XCTAssertEqual(excludedOnly, 1)
    }

    func testFetchFontsForFamiliesReturnsAllStyles() throws {
        let fonts = try store.fetchFontsForFamilies(
            familyKeys: ["Acme"],
            query: FontTableBrowseQuery()
        )
        XCTAssertEqual(fonts.count, 2)
        XCTAssertEqual(Set(fonts.map(\.vaultPath)), Set(["a/Regular.otf", "a/Bold.otf"]))
    }

    func testFetchOrderedVaultPathsWindow() throws {
        let page = try store.fetchOrderedVaultPaths(query: FontTableBrowseQuery(), limit: 2, offset: 0)
        XCTAssertEqual(page.count, 2)
        let all = try store.fetchAllFilteredVaultPaths(query: FontTableBrowseQuery())
        XCTAssertEqual(all.count, 4)
    }

    func testImportDateDistinctDaysOnSummary() throws {
        let summaries = try store.fetchFamilySummaries(query: FontTableBrowseQuery())
        let acme = summaries.first { $0.id == "Acme" }
        XCTAssertEqual(acme?.distinctImportDays, 1)
        XCTAssertNotEqual(acme?.importDateLabel, ImportDateDisplay.conflictIndicator)
        let beta = summaries.first { $0.id == "Beta" }
        XCTAssertEqual(beta?.distinctImportDays, 1)
    }

    func testDuplicateExtraFileCount() throws {
        XCTAssertEqual(try store.duplicateExtraFileCount(), 1)
    }

    func testDuplicateExtraFileCountAllUnique() throws {
        try store.delete(vaultPaths: ["a/Bold.otf"])
        XCTAssertEqual(try store.duplicateExtraFileCount(), 0)
    }

    func testFamilySummaryUniformValuesWhenAllStylesMatch() throws {
        let acme = try store.fetchFamilySummaries(query: FontTableBrowseQuery()).first { $0.id == "Acme" }
        XCTAssertEqual(acme?.uniformValues.family, .uniform("Acme"))
        XCTAssertEqual(acme?.uniformValues.manufacturer, .uniform("DOUBLE ZERO"))
        XCTAssertEqual(acme?.uniformValues.vendorID, .uniform("DBZR"))
    }

    func testFamilySummaryMixedWhenOnlyOneStylePopulated() throws {
        guard var regular = try store.fetchRecord(vaultPath: "a/Regular.otf") else {
            XCTFail("missing seed font")
            return
        }
        regular.manufacturer = ""
        try store.update(regular)
        let acme = try store.fetchFamilySummaries(query: FontTableBrowseQuery()).first { $0.id == "Acme" }
        XCTAssertEqual(acme?.uniformValues.manufacturer, .mixed)
    }

    func testFamilySummaryEmptyWhenAllStylesMissingField() throws {
        guard var regular = try store.fetchRecord(vaultPath: "a/Regular.otf"),
              var bold = try store.fetchRecord(vaultPath: "a/Bold.otf") else {
            XCTFail("missing seed fonts")
            return
        }
        regular.designer = ""
        bold.designer = ""
        try store.update(regular)
        try store.update(bold)
        let fonts = try store.fetchFontsForFamily(familyKey: "Acme", query: FontTableBrowseQuery())
        let section = FontFamilySection(id: "Acme", displayName: "Acme", fonts: fonts)
        XCTAssertEqual(FontListColumn.designer.familyCellText(for: section), "")
    }

    func testFamilySummaryColumnsFromSQLWithoutLoadedChildren() throws {
        let summary = try store.fetchFamilySummaries(query: FontTableBrowseQuery()).first { $0.id == "Acme" }
        let section = summary!.asSection()
        XCTAssertEqual(section.uniformValues.designer, .empty)
        XCTAssertEqual(FontListColumn.designer.familyFieldState(for: section), .empty)
        XCTAssertEqual(section.uniformValues.style, .uniform("Regular"))
        XCTAssertEqual(FontListColumn.style.familyFieldState(for: section), .uniform("Regular"))
        XCTAssertEqual(section.uniformValues.manufacturer, .uniform("DOUBLE ZERO"))
    }

    func testFamilyMixedWhenStylesDisagree() throws {
        guard var bold = try store.fetchRecord(vaultPath: "a/Bold.otf") else {
            XCTFail("missing seed font")
            return
        }
        bold.subfamily = "Bold"
        try store.update(bold)
        let acme = try store.fetchFamilySummaries(query: FontTableBrowseQuery()).first { $0.id == "Acme" }
        XCTAssertEqual(acme?.uniformValues.style, .mixed)
        let section = acme!.asSection()
        XCTAssertEqual(FontListColumn.style.familyFieldState(for: section), .mixed)
        let fonts = try store.fetchFontsForFamily(familyKey: "Acme", query: FontTableBrowseQuery())
        XCTAssertEqual(FontListColumn.style.familyFieldState(for: section, loadedFonts: fonts), .mixed)
    }

    func testFamilyEmptyWhenAllChildrenLackDescription() throws {
        let fonts = try store.fetchFontsForFamily(familyKey: "Acme", query: FontTableBrowseQuery())
        XCTAssertEqual(
            FontListColumn.description.familyFieldState(
                for: FontFamilySection(id: "Acme", displayName: "Acme", fonts: fonts)
            ),
            .empty
        )
    }

    func testFontRowEmptyCellWhenFieldMissing() {
        var font = makeRecord(
            path: "z/Empty.otf",
            family: "Solo",
            fullName: "Solo",
            format: "otf",
            size: 1,
            date: 0
        )
        font.designer = ""
        XCTAssertEqual(FontListColumn.designer.tableDisplayText(for: font), "")
    }

    func testFamilySummaryUniformNilWhenStylesDiffer() throws {
        guard var bold = try store.fetchRecord(vaultPath: "a/Bold.otf") else {
            XCTFail("missing seed font")
            return
        }
        bold.vendorID = "AAAA"
        try store.update(bold)
        let acme = try store.fetchFamilySummaries(query: FontTableBrowseQuery()).first { $0.id == "Acme" }
        XCTAssertEqual(acme?.uniformValues.vendorID, .mixed)
    }
}
