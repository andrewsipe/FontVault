import Foundation

/// Lightweight family row for grouped browse (SQL aggregates for all header columns; styles loaded on demand).
struct FontFamilySummary: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let styleCount: Int
    /// Styles with `excludedFromIndex` in the current browse filter.
    let excludedStyleCount: Int
    let totalSize: Int64
    /// Distinct file extensions / format strings in this family.
    let distinctFormats: [String]
    /// Calendar days among style import dates (`1` → show a single date).
    let distinctImportDays: Int
    let minDateAdded: TimeInterval
    /// Values identical for every style in the family (nil when styles disagree or all empty).
    let uniformValues: FontFamilyUniformValues
    let importDateState: FontFamilyFieldState

    var importDateLabel: String { importDateState.tableText }

    /// Every style in this family (within the current browse filter) is excluded from the index.
    var allStylesExcludedFromIndex: Bool {
        styleCount > 0 && excludedStyleCount == styleCount
    }

    func asSection(with fonts: [FontRecord] = []) -> FontFamilySection {
        FontFamilySection(
            id: id,
            displayName: displayName,
            fonts: fonts,
            cachedStyleCount: styleCount,
            cachedExcludedStyleCount: excludedStyleCount,
            cachedTotalSize: totalSize,
            cachedDistinctFormats: distinctFormats,
            cachedImportDateState: importDateState,
            uniformValues: uniformValues
        )
    }
}
