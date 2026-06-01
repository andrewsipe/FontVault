import Foundation

struct FontFamilySection: Identifiable, Hashable {
    let id: String
    let displayName: String
    let fonts: [FontRecord]
    private let cachedStyleCount: Int?
    private let cachedExcludedStyleCount: Int?
    private let cachedTotalSize: Int64?
    private let cachedDistinctFormats: [String]?
    private let cachedImportDateState: FontFamilyFieldState?
    let uniformValues: FontFamilyUniformValues

    init(
        id: String,
        displayName: String,
        fonts: [FontRecord],
        cachedStyleCount: Int? = nil,
        cachedExcludedStyleCount: Int? = nil,
        cachedTotalSize: Int64? = nil,
        cachedDistinctFormats: [String]? = nil,
        cachedImportDateState: FontFamilyFieldState? = nil,
        uniformValues: FontFamilyUniformValues? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.fonts = fonts
        self.cachedStyleCount = cachedStyleCount
        self.cachedExcludedStyleCount = cachedExcludedStyleCount
        self.cachedTotalSize = cachedTotalSize
        self.cachedDistinctFormats = cachedDistinctFormats
        self.cachedImportDateState = cachedImportDateState
        self.uniformValues = uniformValues ?? FontFamilyUniformValues.aggregate(from: fonts)
    }

    var styleCount: Int { cachedStyleCount ?? fonts.count }

    /// True when every style in the family is excluded from the index (loaded fonts or SQL summary).
    var allStylesExcludedFromIndex: Bool {
        if !fonts.isEmpty {
            return fonts.allSatisfy(\.excludedFromIndex)
        }
        if let cachedStyleCount, let cachedExcludedStyleCount, cachedStyleCount > 0 {
            return cachedExcludedStyleCount == cachedStyleCount
        }
        return false
    }

    var totalSize: Int64 {
        if let cachedTotalSize { return cachedTotalSize }
        return fonts.reduce(0) { $0 + $1.fileSize }
    }

    var distinctFormats: [String] {
        if let cachedDistinctFormats { return cachedDistinctFormats }
        return Array(Set(fonts.map(\.format)))
    }

    var importDateState: FontFamilyFieldState {
        if let cachedImportDateState { return cachedImportDateState }
        return ImportDateDisplay.familyHeaderState(importDates: fonts.map(\.dateAdded))
    }
}

enum FontListDisplayRow: Identifiable {
    case family(FontFamilySection)
    case font(FontRecord)

    var id: String {
        switch self {
        case .family(let section):
            return "family:\(section.id)"
        case .font(let font):
            return font.vaultPath
        }
    }
}

/// One selectable outline row (family header or font style).
enum FontListSelectionRow: Hashable {
    case family(String)
    case font(String)
}

enum FontListGrouping {
    /// Group key: preferred family (ID 16 when present, else ID 1).
    static func familyKey(for font: FontRecord) -> String {
        let name = FontDisplayNames.preferredFamily(for: font)
        return name.isEmpty ? "_Unknown" : name
    }

    static func displayFamilyName(for key: String) -> String {
        key == "_Unknown" ? "Unknown family" : key
    }

    /// Family row title in the list, e.g. `00 Eckmania (6)`.
    static func familyRowTitle(displayName: String, styleCount: Int) -> String {
        "\(displayName) (\(styleCount))"
    }

    /// Export / drag folder name for a family, e.g. `00 Eckmania (6)`.
    static func exportFolderName(displayName: String, styleCount: Int) -> String {
        DragExportStaging.sanitizedFolderName(familyRowTitle(displayName: displayName, styleCount: styleCount))
    }

    /// Ordered family sections for outline / disclosure tables (no flattened child rows).
    static func buildFamilySections(
        fonts: [FontRecord],
        sortColumn: String,
        ascending: Bool
    ) -> [FontFamilySection] {
        guard !fonts.isEmpty else { return [] }

        var grouped: [String: [FontRecord]] = [:]
        for font in fonts {
            let key = familyKey(for: font)
            grouped[key, default: []].append(font)
        }

        for key in grouped.keys {
            grouped[key] = sortFonts(grouped[key]!, column: sortColumn, ascending: ascending)
        }

        let orderedKeys = grouped.keys.sorted { lhs, rhs in
            compareFamilies(
                lhs: lhs,
                rhs: rhs,
                grouped: grouped,
                sortColumn: sortColumn,
                ascending: ascending
            )
        }

        return orderedKeys.compactMap { key in
            guard let members = grouped[key] else { return nil }
            return FontFamilySection(
                id: key,
                displayName: displayFamilyName(for: key),
                fonts: members
            )
        }
    }

    static func displayedFontPaths(
        sections: [FontFamilySection],
        collapsedFamilies: Set<String>
    ) -> [String] {
        sections.flatMap { section -> [String] in
            if collapsedFamilies.contains(section.id) { return [] }
            return section.fonts.map(\.vaultPath)
        }
    }

    /// Outline row order for ⇧-click range (families + visible children).
    static func displayedSelectionRows(
        sections: [FontFamilySection],
        collapsedFamilies: Set<String>
    ) -> [FontListSelectionRow] {
        sections.flatMap { section -> [FontListSelectionRow] in
            var rows: [FontListSelectionRow] = [.family(section.id)]
            if !collapsedFamilies.contains(section.id) {
                rows.append(contentsOf: section.fonts.map { .font($0.vaultPath) })
            }
            return rows
        }
    }

    /// FEX-style export: whole selected families + individual fonts not covered by a selected family.
    static func fontsForExport(
        selectedFamilyIDs: Set<String>,
        selectedVaultPaths: Set<String>,
        sections: [FontFamilySection],
        fontsByVaultPath: [String: FontRecord]
    ) -> [FontRecord] {
        var byPath: [String: FontRecord] = [:]

        for section in sections where selectedFamilyIDs.contains(section.id) {
            for font in section.fonts {
                byPath[font.vaultPath] = font
            }
        }

        for path in selectedVaultPaths {
            guard let font = fontsByVaultPath[path] else { continue }
            let familyID = familyKey(for: font)
            if selectedFamilyIDs.contains(familyID) { continue }
            byPath[path] = font
        }

        return Array(byPath.values)
    }

    /// Builds family headers and child font rows for the list.
    static func buildDisplayRows(
        fonts: [FontRecord],
        sortColumn: String,
        ascending: Bool,
        collapsedFamilies: Set<String>
    ) -> [FontListDisplayRow] {
        guard !fonts.isEmpty else { return [] }

        var grouped: [String: [FontRecord]] = [:]
        for font in fonts {
            let key = familyKey(for: font)
            grouped[key, default: []].append(font)
        }

        for key in grouped.keys {
            grouped[key] = sortFonts(grouped[key]!, column: sortColumn, ascending: ascending)
        }

        let orderedKeys = grouped.keys.sorted { lhs, rhs in
            compareFamilies(
                lhs: lhs,
                rhs: rhs,
                grouped: grouped,
                sortColumn: sortColumn,
                ascending: ascending
            )
        }

        var rows: [FontListDisplayRow] = []
        for key in orderedKeys {
            guard let members = grouped[key] else { continue }
            let section = FontFamilySection(
                id: key,
                displayName: displayFamilyName(for: key),
                fonts: members
            )
            rows.append(.family(section))
            if !collapsedFamilies.contains(key) {
                for font in members {
                    rows.append(.font(font))
                }
            }
        }
        return rows
    }

    static func displayedFontPaths(from rows: [FontListDisplayRow]) -> [String] {
        rows.compactMap { row in
            if case .font(let font) = row { return font.vaultPath }
            return nil
        }
    }

    private static func sortFonts(
        _ fonts: [FontRecord],
        column: String,
        ascending: Bool
    ) -> [FontRecord] {
        fonts.sorted { lhs, rhs in
            let ordered: Bool
            switch column {
            case "family":
                ordered = lhs.family.localizedCaseInsensitiveCompare(rhs.family) == .orderedAscending
            case "format":
                ordered = lhs.format.localizedCaseInsensitiveCompare(rhs.format) == .orderedAscending
            case "fileSize":
                ordered = lhs.fileSize < rhs.fileSize
            case "dateAdded":
                ordered = lhs.dateAdded < rhs.dateAdded
            default:
                ordered = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
            return ascending ? ordered : !ordered
        }
    }

    private static func compareFamilies(
        lhs: String,
        rhs: String,
        grouped: [String: [FontRecord]],
        sortColumn: String,
        ascending: Bool
    ) -> Bool {
        let leftFonts = grouped[lhs] ?? []
        let rightFonts = grouped[rhs] ?? []
        let leftName = displayFamilyName(for: lhs)
        let rightName = displayFamilyName(for: rhs)

        let ordered: Bool
        switch sortColumn {
        case "family":
            ordered = leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        case "format":
            let lf = leftFonts.first?.format ?? ""
            let rf = rightFonts.first?.format ?? ""
            ordered = lf.localizedCaseInsensitiveCompare(rf) == .orderedAscending
        case "fileSize":
            let ls = leftFonts.reduce(Int64(0)) { $0 + $1.fileSize }
            let rs = rightFonts.reduce(Int64(0)) { $0 + $1.fileSize }
            ordered = ls < rs
        case "dateAdded":
            let ld = leftFonts.map(\.dateAdded).max() ?? 0
            let rd = rightFonts.map(\.dateAdded).max() ?? 0
            ordered = ld < rd
        default:
            let ln = leftFonts.first?.fullName ?? leftName
            let rn = rightFonts.first?.fullName ?? rightName
            ordered = ln.localizedCaseInsensitiveCompare(rn) == .orderedAscending
        }
        return ascending ? ordered : !ordered
    }
}
