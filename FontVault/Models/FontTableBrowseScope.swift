import Foundation

/// Built-in Smart Filter entries (Phase 2a). User-defined filters are Phase 2b+.
enum SmartFilterID: String, Hashable, CaseIterable {
    case excludedFonts
}

/// Which rows the font table query returns (composed with search/format in `FontTableBrowseQuery`).
enum FontTableBrowseScope: Equatable {
    case allFonts
    case excludedFontsOnly
}

/// Parameters for windowed catalog browse (list, counts, family summaries).
struct FontTableBrowseQuery: Equatable {
    var search: String = ""
    var format: String? = nil
    var tableScope: FontTableBrowseScope = .allFonts
    /// When `tableScope` is `.allFonts`, excluded rows are hidden unless this is true.
    var showIgnoredFonts: Bool = false
}
