import Foundation

enum FontListContextMenuRowKind: Equatable {
    case family(FontFamilySection)
    case font(FontRecord)
    case none
}

enum FontListContextMenuCopyKind: String {
    case clickedColumn
    case fontName
    case fontFamily
    case fullPath
    case familyHeaderRow
    case fontRows
}

/// Snapshot of the row/column under the pointer when a context menu opens.
struct FontListContextMenuContext: Equatable {
    let rowKind: FontListContextMenuRowKind
    let clickedColumn: FontListColumn?
    let clickedDisplayText: String
    let selectionCount: Int
    let singleFontSelected: Bool
    let browserMode: VaultBrowserMode
    let groupByFamily: Bool
    let showInspector: Bool
    let selectedFonts: [FontRecord]
    let visibleColumns: [FontListColumn]
    let vaultRootURL: URL?
    /// Active sidebar format filter (`nil` = all formats).
    let activeFormatFilter: String?
    /// Same gate as sidebar **Smart Filters → Excluded Fonts** (ignored visible + count > 0).
    let showsExcludedFontsSmartFilter: Bool

    var font: FontRecord? {
        if case .font(let font) = rowKind { return font }
        return nil
    }

    var familySection: FontFamilySection? {
        if case .family(let section) = rowKind { return section }
        return nil
    }

    var isFamilyHeaderRow: Bool {
        familySection != nil
    }

    /// Fonts in the current export selection that belong to one family (for header column copy).
    func selectedFonts(inFamilyID familyID: String) -> [FontRecord] {
        selectedFonts.filter { FontListGrouping.familyKey(for: $0) == familyID }
    }

    /// Fonts included in **Copy N Rows** (family header → that family's styles when known).
    var fontsForFontRowCopy: [FontRecord] {
        if let section = familySection {
            let inFamily = selectedFonts(inFamilyID: section.id)
            if !inFamily.isEmpty { return inFamily }
        }
        return selectedFonts
    }

    var fontRowCopyCount: Int {
        fontsForFontRowCopy.count
    }

    var hasMetadataIssues: Bool {
        if let font {
            return VaultSettings.metadataWarningsVisible && font.hasAnyActiveMetadataIssue
        }
        return VaultSettings.metadataWarningsVisible
            && selectedFonts.contains { $0.hasAnyActiveMetadataIssue }
    }

    var metadataIssuesForClickedField: [MetadataIssue] {
        guard VaultSettings.metadataWarningsVisible else { return [] }
        if let font {
            if let column = clickedColumn, let key = column.metadataFieldKey {
                return font.activeMetadataIssues(for: key)
            }
            return allActiveMetadataIssues(in: font)
        }
        guard let column = clickedColumn, let key = column.metadataFieldKey else {
            return []
        }
        var seen = Set<MetadataIssue>()
        var result: [MetadataIssue] = []
        for font in selectedFonts {
            for issue in font.activeMetadataIssues(for: key) where seen.insert(issue).inserted {
                result.append(issue)
            }
        }
        return result.sorted { $0.rawValue < $1.rawValue }
    }

    var isURLColumn: Bool {
        guard let column = clickedColumn else { return false }
        switch column {
        case .licenseURL, .manufacturerURL, .designerURL:
            return true
        default:
            return false
        }
    }

    /// Single deduped http(s) URL in the clicked URL column (font or family header).
    var urlIfValid: URL? {
        guard isURLColumn else { return nil }
        let lines = uniqueLines(for: .clickedColumn)
        guard lines.count == 1 else { return nil }
        return FontListURLParsing.validHTTPURL(from: lines[0])
    }

    /// Non-empty, non-placeholder value suitable for Find (one distinct value only).
    var canFind: Bool {
        findText != nil
    }

    var findText: String? {
        guard clickedColumn != nil else { return nil }
        let lines = uniqueLines(for: .clickedColumn)
        guard lines.count == 1 else { return nil }
        let value = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != ImportDateDisplay.conflictDisplay else { return nil }
        return value
    }

    var formatFilterMenuOptions: [FontListFormatFilterMenuOption] {
        guard clickedColumn == .format else { return [] }
        switch rowKind {
        case .font(let font):
            let format = FontFormat.from(pathExtension: font.format)
            guard format != .unknown, format != .mixed else { return [] }
            return [FontListFormatFilterMenuOption(filterKey: format.rawValue, badgeLabel: format.badgeLabel)]
        case .family(let section):
            let aggregate = FontFormat.aggregate(forFormatStrings: section.distinctFormats)
            if aggregate == .mixed {
                return FontFormat.mixGradientFormats(fromExtensionStrings: section.distinctFormats).map {
                    FontListFormatFilterMenuOption(filterKey: $0.rawValue, badgeLabel: $0.badgeLabel)
                }
            }
            guard aggregate != .unknown else { return [] }
            return [FontListFormatFilterMenuOption(filterKey: aggregate.rawValue, badgeLabel: aggregate.badgeLabel)]
        case .none:
            return []
        }
    }

    var showsClearFormatFilter: Bool {
        clickedColumn == .format && activeFormatFilter != nil
    }

    /// Menu title for a copy action: singular when one distinct value, else count of distinct values.
    func copyMenuTitle(
        singular: String,
        plural: (Int) -> String,
        uniqueCount: Int
    ) -> String {
        uniqueCount <= 1 ? singular : plural(uniqueCount)
    }

    func uniqueCount(for kind: FontListContextMenuCopyKind) -> Int {
        uniqueLines(for: kind).count
    }

    func uniqueLines(for kind: FontListContextMenuCopyKind) -> [String] {
        switch kind {
        case .clickedColumn:
            return uniqueNonEmpty(rawValuesForClickedColumn())
        case .fontName:
            return uniqueNonEmpty(selectedFonts.map(\.fullName))
        case .fontFamily:
            if !selectedFonts.isEmpty {
                return uniqueNonEmpty(
                    selectedFonts.map { FontDisplayNames.preferredFamily(for: $0) }
                )
            }
            if let section = familySection {
                let name = section.displayName
                return name.isEmpty ? [] : [name]
            }
            return []
        case .fullPath:
            return uniqueNonEmpty(selectedFonts.compactMap { filePath(for: $0) })
        case .familyHeaderRow, .fontRows:
            return []
        }
    }

    func copyText(for kind: FontListContextMenuCopyKind) -> String? {
        switch kind {
        case .familyHeaderRow:
            guard let section = familySection else { return nil }
            let loaded = selectedFonts(inFamilyID: section.id)
            let header = visibleColumns.map(\.title).joined(separator: "\t")
            let row = visibleColumns.map {
                $0.familyFieldState(for: section, loadedFonts: loaded).tableText
            }.joined(separator: "\t")
            guard !row.isEmpty else { return nil }
            return ([header, row]).joined(separator: "\n")
        case .fontRows:
            let fonts = fontsForFontRowCopy
            guard !fonts.isEmpty else { return nil }
            let header = visibleColumns.map(\.title).joined(separator: "\t")
            let rows = fonts.map { font in
                visibleColumns.map { $0.rawDisplayValue(for: font) }.joined(separator: "\t")
            }
            return ([header] + rows).joined(separator: "\n")
        default:
            let lines = uniqueLines(for: kind)
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
    }

    private func rawValuesForClickedColumn() -> [String] {
        guard let column = clickedColumn else { return [] }

        if let section = familySection, usesFamilyHeaderColumnText(for: section) {
            let loaded = selectedFonts(inFamilyID: section.id)
            let cellText = column.familyFieldState(for: section, loadedFonts: loaded).tableText
            if !cellText.isEmpty {
                return [cellText]
            }
        }

        return uniqueNonEmpty(selectedFonts.map { column.rawDisplayValue(for: $0) })
    }

    /// Use the grouped header cell string when one family is in scope (matches what the row displays).
    private func usesFamilyHeaderColumnText(for section: FontFamilySection) -> Bool {
        if selectedFonts.isEmpty { return true }
        let familyIDs = Set(selectedFonts.map { FontListGrouping.familyKey(for: $0) })
        return familyIDs.count == 1 && familyIDs.contains(section.id)
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

    private func filePath(for font: FontRecord) -> String? {
        if let vaultRootURL {
            return vaultRootURL.appendingPathComponent(font.vaultPath).path
        }
        return font.vaultPath.isEmpty ? nil : font.vaultPath
    }

    func metadataIssueSummary() -> String? {
        var issues: [MetadataIssue]
        if let font {
            if let column = clickedColumn, let key = column.metadataFieldKey {
                issues = font.activeMetadataIssues(for: key)
            } else {
                issues = allActiveMetadataIssues(in: font)
            }
        } else {
            issues = metadataIssuesForClickedField
            if issues.isEmpty {
                var seen = Set<MetadataIssue>()
                var all: [MetadataIssue] = []
                for font in selectedFonts {
                    for issue in allActiveMetadataIssues(in: font) where seen.insert(issue).inserted {
                        all.append(issue)
                    }
                }
                issues = all
            }
        }
        guard !issues.isEmpty else { return nil }
        return MetadataIssue.tooltip(for: issues)
    }

    private func allActiveMetadataIssues(in font: FontRecord) -> [MetadataIssue] {
        var seen = Set<MetadataIssue>()
        var result: [MetadataIssue] = []
        for field in FontMetadataFieldKey.allCases {
            for issue in font.activeMetadataIssues(for: field) where seen.insert(issue).inserted {
                result.append(issue)
            }
        }
        return result.sorted { $0.rawValue < $1.rawValue }
    }
}
