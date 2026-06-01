import Foundation

struct StatusBarVisibleCount: Equatable, Sendable {
    /// Compact left-zone text, e.g. `12 shown` or `2,000 / 9,412`.
    var glance: String
    /// Short suffix when sidebar is not All Fonts, e.g. `OTF` (displayed after glance).
    var sourceSuffix: String?
    /// Full explanation for `.help` / accessibility.
    var tooltip: String
}

enum StatusBarCopy {
    static let linkOpenHint = "⌘-click to open"

    static func visibleCount(
        browserMode: VaultBrowserMode,
        totalCount: Int,
        flatLoadedCount: Int,
        groupByFamily: Bool,
        catalogFontCount: Int,
        familySummaryCount: Int,
        sidebarSelection: SidebarItem,
        sidebarFormats: [(format: FontFormat, filterKey: String, count: Int)],
        searchText: String,
        formatFilter: String?,
        showLibraryCounters: Bool,
        excludedFontCount: Int,
        showIgnoredFonts: Bool
    ) -> StatusBarVisibleCount {
        switch browserMode {
        case .duplicates:
            let glance = "\(formattedCount(catalogFontCount)) vault"
            let tooltip = "\(catalogFontCount) \(catalogFontCount == 1 ? "font" : "fonts") in vault (Duplicates view)."
            return StatusBarVisibleCount(glance: glance, sourceSuffix: nil, tooltip: tooltip)
        case .allFonts:
            let capped = !groupByFamily && flatLoadedCount < totalCount
            let shown = capped ? flatLoadedCount : totalCount
            let glanceCore = capped
                ? "\(formattedCount(flatLoadedCount)) / \(formattedCount(totalCount))"
                : "\(formattedCount(shown)) shown"
            let suffix = sidebarSourceSuffix(
                sidebarSelection: sidebarSelection,
                sidebarFormats: sidebarFormats
            )
            var tooltipParts: [String] = []
            if capped {
                tooltipParts.append(
                    "Showing \(formattedCount(flatLoadedCount)) of \(formattedCount(totalCount)) fonts matching the current filter (scroll to load more)."
                )
            } else {
                tooltipParts.append(
                    "\(formattedCount(totalCount)) \(totalCount == 1 ? "font" : "fonts") match the current filter in the font table."
                )
            }
            if groupByFamily, familySummaryCount > 0 {
                tooltipParts.append("\(formattedCount(familySummaryCount)) \(familySummaryCount == 1 ? "family" : "families") in the grouped list.")
            }
            appendBrowseContext(
                to: &tooltipParts,
                searchText: searchText,
                formatFilter: formatFilter,
                sidebarSelection: sidebarSelection,
                sidebarFormats: sidebarFormats
            )
            if showLibraryCounters, excludedFontCount > 0 {
                let ignoredNote = showIgnoredFonts
                    ? " (\(formattedCount(excludedFontCount)) excluded fonts are visible because Show Ignored Fonts is on.)"
                    : " (\(formattedCount(excludedFontCount)) excluded fonts are hidden; turn on Show Ignored Fonts to include them.)"
                tooltipParts.append(ignoredNote)
            }
            return StatusBarVisibleCount(
                glance: glanceCore,
                sourceSuffix: suffix,
                tooltip: tooltipParts.joined(separator: "\n")
            )
        }
    }

    static func selectionGlance(fontCount: Int, totalByteCount: Int64) -> String {
        let sizeText = ByteCountFormatter.string(fromByteCount: totalByteCount, countStyle: .file)
        if fontCount == 1 {
            return "1 sel · \(sizeText)"
        }
        return "\(formattedCount(fontCount)) sel · \(sizeText)"
    }

    static func sidebarSourceSuffix(
        sidebarSelection: SidebarItem,
        sidebarFormats: [(format: FontFormat, filterKey: String, count: Int)]
    ) -> String? {
        switch sidebarSelection {
        case .allFonts:
            return nil
        case .duplicates:
            return "Duplicates"
        case .format(let filterKey):
            if filterKey == FontSidebarFilter.variableOnly {
                return "Variable"
            }
            if let format = sidebarFormats.first(where: { $0.filterKey == filterKey })?.format {
                return format.badgeLabel
            }
            return (FontFormat(rawValue: filterKey) ?? .unknown).badgeLabel
        case .smartFilter(.excludedFonts):
            return AppMenuCopy.smartFilterExcludedFonts
        }
    }

    private static func formattedCount(_ n: Int) -> String {
        n.formatted()
    }

    private static func appendBrowseContext(
        to parts: inout [String],
        searchText: String,
        formatFilter: String?,
        sidebarSelection: SidebarItem,
        sidebarFormats: [(format: FontFormat, filterKey: String, count: Int)]
    ) {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            parts.append("Search: \"\(trimmedSearch)\"")
        }
        if let formatFilter, let format = FontFormat(rawValue: formatFilter) {
            parts.append("Table format filter: \(format.badgeLabel)")
        }
        if let suffix = sidebarSourceSuffix(
            sidebarSelection: sidebarSelection,
            sidebarFormats: sidebarFormats
        ) {
            parts.append("Library source: \(suffix)")
        }
    }
}
