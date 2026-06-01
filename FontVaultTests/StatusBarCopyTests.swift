import XCTest
@testable import FontVault

final class StatusBarCopyTests: XCTestCase {
    private let sidebarFormats: [(format: FontFormat, filterKey: String, count: Int)] = [
        (.otf, FontFormat.otf.rawValue, 10)
    ]

    func testFlatCapFormatsAsLoadedOverTotal() {
        let count = StatusBarCopy.visibleCount(
            browserMode: .allFonts,
            totalCount: 9_412,
            flatLoadedCount: 2_000,
            groupByFamily: false,
            catalogFontCount: 9_412,
            familySummaryCount: 0,
            sidebarSelection: .allFonts,
            sidebarFormats: sidebarFormats,
            searchText: "",
            formatFilter: nil,
            showLibraryCounters: false,
            excludedFontCount: 0,
            showIgnoredFonts: false
        )

        XCTAssertEqual(count.glance, "2,000 / 9,412")
        XCTAssertNil(count.sourceSuffix)
        XCTAssertTrue(count.tooltip.contains("2,000"))
        XCTAssertTrue(count.tooltip.contains("9,412"))
    }

    func testSidebarFormatFilterAddsInlineSuffix() {
        let count = StatusBarCopy.visibleCount(
            browserMode: .allFonts,
            totalCount: 12,
            flatLoadedCount: 12,
            groupByFamily: true,
            catalogFontCount: 12,
            familySummaryCount: 3,
            sidebarSelection: .format(filterKey: FontFormat.otf.rawValue),
            sidebarFormats: sidebarFormats,
            searchText: "",
            formatFilter: nil,
            showLibraryCounters: false,
            excludedFontCount: 0,
            showIgnoredFonts: false
        )

        XCTAssertEqual(count.glance, "12 shown")
        XCTAssertEqual(count.sourceSuffix, FontFormat.otf.badgeLabel)
    }

    func testSelectionGlanceCompaction() {
        XCTAssertEqual(StatusBarCopy.selectionGlance(fontCount: 1, totalByteCount: 2_800_000), "1 sel · 2.8 MB")
        XCTAssertEqual(StatusBarCopy.selectionGlance(fontCount: 12, totalByteCount: 2_800_000), "12 sel · 2.8 MB")
    }
}
