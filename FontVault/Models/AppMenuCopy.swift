import Foundation

/// Shared menu and command titles (macOS ellipsis `…` for actions that open a sheet or panel).
enum AppMenuCopy {
    static let importFonts = "Import Fonts…"
    static let exportFonts = "Export Fonts…"
    static let moveToTrash = "Move to Trash…"
    static let deleteImmediately = "Delete Immediately…"
    static let excludeFromIndex = "Exclude from Index…"
    static let includeInIndex = "Include in Index"
    static let showIgnoredFonts = "Show Ignored Fonts"
    static let hideIgnoredFonts = "Hide Ignored Fonts"
    static let showMetadataWarnings = "Show Metadata Warnings"
    static let hideMetadataWarnings = "Hide Metadata Warnings"

    static let viewImportDetails = "View Details…"
    static let importDetailsTitle = "Import Details"
    static let copyImportFailureList = "Copy Failure List"
    static let saveImportFailureList = "Save Failure List…"
    static let copyImportIssueList = "Copy Issue List"
    static let saveImportIssueList = "Save Issue Report…"
    static func importReportFailedSection(_ count: Int) -> String {
        "Failed (\(count))"
    }
    static func importReportSkippedSection(_ count: Int) -> String {
        "Skipped (\(count))"
    }
    static func importReportNamingSection(_ count: Int) -> String {
        "Review naming (\(count))"
    }
    static let excludeIgnoredFontsFromIndex = "Exclude Ignored Fonts from Index"
    static let smartFilterExcludedFonts = "Excluded Fonts"
    static let rebuildCatalog = "Rebuild Catalog…"
    static let reorganizeLayout = "Reorganize to A–Z Layout…"
    static let cleanVault = "Clean Vault…"
    static let findDuplicates = "Find Duplicates…"
    static let fontTable = "Font Table…"
    static let resetColumnWidths = "Reset Column Widths"
    /// Selected font files (row context menu).
    static let revealInFinder = "Reveal in Finder"
    static let openInInspectorWindow = "Open in Inspector Window"
    static let inspectorWindowTitle = "Font Inspector"
    static let inspectorPreviousTab = "Show Previous Tab"
    static let inspectorNextTab = "Show Next Tab"
    /// Vault root folder (sidebar footer, Settings).
    static let revealVaultInFinder = "Reveal Vault in Finder"

    static let importFontsToolbar = "Import Fonts"
    static let rebuildCatalogToolbar = "Rebuild Catalog"

    static let showLibrary = "Show Font Library"
    static let hideLibrary = "Hide Font Library"
    static let showInformation = "Show Information"
    static let hideInformation = "Hide Information"
    static let showCounters = "Show Counters"
    static let hideCounters = "Hide Counters"
    static let find = "Find…"
    static let groupByFamily = "Group by Family"

    static let selectAllFamilies = "Select All Families"
    static let selectAllFonts = "Select All Fonts"
    static let deselectAll = "Deselect All"
    static let expandAllFamilies = "Expand All Families"
    static let collapseAllFamilies = "Collapse All Families"

    static let showInInformation = "Show in Information"
    static let hideInInformation = "Hide in Information"
    static let copySubmenu = "Copy"
    static let copyFontName = "Copy Font Name"
    static let copyFontFamily = "Copy Font Family"
    static let copyFullPath = "Copy Full Path"
    static let copyRow = "Copy Row"
    static let copyFamilyRow = "Copy Family Row"

    static func copyRows(_ count: Int) -> String {
        "Copy \(count) Rows"
    }
    static let metadataSubmenu = "Metadata"
    static let showIssueInInformation = "Show Issue in Information"
    static let copyIssueSummary = "Copy Issue Summary"

    static func copyColumn(_ title: String) -> String {
        "Copy “\(title)”"
    }

    /// Plural menu title when multiple **distinct** values will be copied.
    static func copyFontNames(_ uniqueCount: Int) -> String {
        "Copy \(uniqueCount) Font Names"
    }

    static func copyFontFamilies(_ uniqueCount: Int) -> String {
        "Copy \(uniqueCount) Font Families"
    }

    static func copyFullPaths(_ uniqueCount: Int) -> String {
        "Copy \(uniqueCount) Full Paths"
    }

    static func copyColumnValues(_ columnTitle: String, uniqueCount: Int) -> String {
        "Copy \(uniqueCount) “\(columnTitle)”"
    }

    static let openURL = "Open URL"
    static let copyURL = "Copy URL"
    static let filterSubmenu = "Filter"
    static let clearFormatFilter = "Clear Format Filter"

    static func showOnlyFormat(_ badgeLabel: String) -> String {
        "Show Only \(badgeLabel)"
    }

    static func findValue(_ value: String) -> String {
        let preview = value.count > 48 ? String(value.prefix(45)) + "…" : value
        return "Find “\(preview)”"
    }

    static func showOnlySmartFilter(_ title: String) -> String {
        "Show Only \(title)"
    }
}
