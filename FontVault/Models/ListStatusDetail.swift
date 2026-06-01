import Foundation

/// Transient status bar detail (selection or cell hover), separate from `statusMessage` progress text.
struct ListStatusDetail: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case selection
        case hover
    }

    var column: FontListColumn?
    /// Truncated value for the status bar glance line.
    var valueText: String
    /// Full cell value for tooltips.
    var fullValueText: String
    /// Set only when the active column has a metadata field with user-facing issues.
    var metadataWarning: MetadataIssue?
    /// True when the font row (or family) has any user-facing metadata issue — drives status bar icon.
    var rowHasMetadataIssue: Bool = false
    /// Tooltip for the row-level status bar warning icon.
    var rowMetadataIssueTooltip: String = ""
    var showsLinkOpenHint: Bool = false
    var source: Source

    static let maxValueLength = 500

    static func truncated(_ text: String, maxLength: Int = maxValueLength) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)) + "…"
    }

    var glanceLine: String {
        guard let column else { return valueText }
        return "\(column.title): \(valueText)"
    }

    var tooltipLine: String {
        var parts: [String] = []
        if let column {
            parts.append("\(column.title): \(fullValueText)")
        } else {
            parts.append(fullValueText)
        }
        if showsLinkOpenHint {
            parts.append("⌘-click to open")
        }
        return parts.joined(separator: "\n")
    }
}

extension ListStatusDetail {
    /// Builds detail for one font row (status bar / hover).
    static func forFont(
        _ font: FontRecord,
        column: FontListColumn?,
        source: Source
    ) -> ListStatusDetail? {
        let fieldColumn = column ?? .name
        let fullValue = fieldColumn.rawDisplayValue(for: font)
        guard !fullValue.isEmpty else { return nil }

        let warningsEnabled = VaultSettings.metadataWarningsVisible
        let warning = warningsEnabled ? metadataWarning(for: fieldColumn, font: font) : nil
        let rowIssues = warningsEnabled ? activeMetadataIssues(for: font) : []
        var detail = ListStatusDetail(
            column: fieldColumn,
            valueText: truncated(fullValue),
            fullValueText: fullValue,
            metadataWarning: warning,
            rowHasMetadataIssue: !rowIssues.isEmpty,
            rowMetadataIssueTooltip: MetadataIssue.tooltip(for: rowIssues),
            showsLinkOpenHint: false,
            source: source
        )
        if fieldColumn.isWebURLColumn,
           FontListURLParsing.validHTTPURL(from: fullValue) != nil {
            detail.showsLinkOpenHint = true
        }
        return detail
    }

    /// Family header cell under the pointer.
    static func forFamilyHeader(
        column: FontListColumn,
        section: FontFamilySection,
        loadedFonts: [FontRecord],
        source: Source
    ) -> ListStatusDetail? {
        let fullValue = column.familyFieldState(for: section, loadedFonts: loadedFonts).tableText
        guard !fullValue.isEmpty else { return nil }

        let warningsEnabled = VaultSettings.metadataWarningsVisible
        let warning = warningsEnabled
            ? metadataWarningForFamily(column: column, fonts: loadedFonts)
            : nil
        let rowIssues = warningsEnabled
            ? activeMetadataIssues(forFamilyFonts: loadedFonts.isEmpty ? section.fonts : loadedFonts)
            : []
        var detail = ListStatusDetail(
            column: column,
            valueText: truncated(fullValue),
            fullValueText: fullValue,
            metadataWarning: warning,
            rowHasMetadataIssue: !rowIssues.isEmpty,
            rowMetadataIssueTooltip: MetadataIssue.tooltip(for: rowIssues),
            showsLinkOpenHint: false,
            source: source
        )
        if column.isWebURLColumn, FontListURLParsing.validHTTPURL(from: fullValue) != nil {
            detail.showsLinkOpenHint = true
        }
        return detail
    }

    private static func activeMetadataIssues(for font: FontRecord) -> [MetadataIssue] {
        var seen = Set<MetadataIssue>()
        var issues: [MetadataIssue] = []
        for key in FontMetadataFieldKey.allCases {
            for issue in font.activeMetadataIssues(for: key) where issue.countsForUserAttention {
                if seen.insert(issue).inserted {
                    issues.append(issue)
                }
            }
        }
        return issues.sorted { $0.rawValue < $1.rawValue }
    }

    private static func activeMetadataIssues(forFamilyFonts fonts: [FontRecord]) -> [MetadataIssue] {
        var seen = Set<MetadataIssue>()
        var issues: [MetadataIssue] = []
        for font in fonts {
            for issue in activeMetadataIssues(for: font) where seen.insert(issue).inserted {
                issues.append(issue)
            }
        }
        return issues.sorted { $0.rawValue < $1.rawValue }
    }

    private static func metadataWarning(
        for column: FontListColumn,
        font: FontRecord
    ) -> MetadataIssue? {
        guard let key = column.metadataFieldKey else { return nil }
        return font.activeMetadataIssues(for: key).first { $0.countsForUserAttention }
    }

    private static func metadataWarningForFamily(
        column: FontListColumn,
        fonts: [FontRecord]
    ) -> MetadataIssue? {
        guard let key = column.metadataFieldKey, !fonts.isEmpty else { return nil }
        var seen = Set<MetadataIssue>()
        for font in fonts {
            if let issue = font.activeMetadataIssues(for: key).first(where: \.countsForUserAttention),
               seen.insert(issue).inserted {
                return issue
            }
        }
        return nil
    }
}
