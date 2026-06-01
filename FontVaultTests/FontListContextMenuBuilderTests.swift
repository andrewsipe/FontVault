import XCTest
@testable import FontVault

@MainActor
final class FontListContextMenuBuilderTests: XCTestCase {
    private func sampleFont(psName: String = "Example-Regular") -> FontRecord {
        FontRecord(
            databaseID: nil,
            vaultPath: "A/Example-Regular.otf",
            sha256: "abc",
            fileSize: 1024,
            format: "otf",
            dateAdded: 1_700_000_000,
            psName: psName,
            fullName: "Example Regular",
            nameTableFullName: "Example Regular",
            family: "Example",
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
            extractedDetails: .empty,
            metadataIssues: .empty
        )
    }

    private func context(
        column: FontListColumn,
        rowKind: FontListContextMenuRowKind,
        selectedFonts: [FontRecord],
        activeFormatFilter: String? = nil,
        showsExcludedFontsSmartFilter: Bool = false
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
            visibleColumns: [.name, .postScript, .format],
            vaultRootURL: URL(fileURLWithPath: "/Vault"),
            activeFormatFilter: activeFormatFilter,
            showsExcludedFontsSmartFilter: showsExcludedFontsSmartFilter
        )
    }

    private func allMenuTitles(in menu: NSMenu) -> [String] {
        var titles: [String] = []
        for item in menu.items {
            titles.append(item.title)
            if let submenu = item.submenu {
                titles.append(contentsOf: allMenuTitles(in: submenu))
            }
        }
        return titles
    }

    func testFindItemUsesFindValueCopy() {
        let font = sampleFont()
        let ctx = context(column: .postScript, rowKind: .font(font), selectedFonts: [font])
        let menu = FontListContextMenuBuilder.menu(for: ctx, target: FontListOutlineCoordinator())
        XCTAssertTrue(allMenuTitles(in: menu).contains(AppMenuCopy.findValue(font.psName)))
    }

    func testFilterSubmenuIncludesExcludedFontsWhenGated() {
        let font = sampleFont()
        let ctx = context(
            column: .name,
            rowKind: .font(font),
            selectedFonts: [font],
            showsExcludedFontsSmartFilter: true
        )
        let menu = FontListContextMenuBuilder.menu(for: ctx, target: FontListOutlineCoordinator())
        XCTAssertTrue(
            allMenuTitles(in: menu).contains(
                AppMenuCopy.showOnlySmartFilter(AppMenuCopy.smartFilterExcludedFonts)
            )
        )
    }

    func testFilterSubmenuOmitsExcludedFontsWhenNotGated() {
        let font = sampleFont()
        let ctx = context(
            column: .name,
            rowKind: .font(font),
            selectedFonts: [font],
            showsExcludedFontsSmartFilter: false
        )
        let menu = FontListContextMenuBuilder.menu(for: ctx, target: FontListOutlineCoordinator())
        XCTAssertFalse(
            allMenuTitles(in: menu).contains(
                AppMenuCopy.showOnlySmartFilter(AppMenuCopy.smartFilterExcludedFonts)
            )
        )
    }

    func testFilterSubmenuIncludesClearFormatFilter() {
        let font = sampleFont()
        let ctx = context(
            column: .format,
            rowKind: .font(font),
            selectedFonts: [font],
            activeFormatFilter: "otf"
        )
        let menu = FontListContextMenuBuilder.menu(for: ctx, target: FontListOutlineCoordinator())
        XCTAssertTrue(allMenuTitles(in: menu).contains(AppMenuCopy.clearFormatFilter))
    }
}
