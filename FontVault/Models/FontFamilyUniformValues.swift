import Foundation

/// Column values shared by every style in a family (from SQL aggregates or loaded fonts).
struct FontFamilyUniformValues: Hashable, Sendable {
    var family: FontFamilyFieldState = .empty
    var typographicFamily: FontFamilyFieldState = .empty
    var style: FontFamilyFieldState = .empty
    var typographicStyle: FontFamilyFieldState = .empty
    var postScript: FontFamilyFieldState = .empty
    var uniqueName: FontFamilyFieldState = .empty
    var version: FontFamilyFieldState = .empty
    var manufacturer: FontFamilyFieldState = .empty
    var vendorID: FontFamilyFieldState = .empty
    var designer: FontFamilyFieldState = .empty
    var description: FontFamilyFieldState = .empty
    var trademark: FontFamilyFieldState = .empty
    var copyright: FontFamilyFieldState = .empty
    var formatDetailed: FontFamilyFieldState = .empty

    /// SQL / in-memory aggregate for a catalog-backed family column.
    func fieldState(for column: FontListColumn) -> FontFamilyFieldState? {
        switch column {
        case .family: return family
        case .typographicFamily: return typographicFamily
        case .style: return style
        case .typographicStyle: return typographicStyle
        case .postScript: return postScript
        case .uniqueName: return uniqueName
        case .version: return version
        case .manufacturer: return manufacturer
        case .vendorID: return vendorID
        case .designer: return designer
        case .description: return description
        case .trademark: return trademark
        case .copyright: return copyright
        case .formatDetailed: return formatDetailed
        case .name, .fontFamily, .fullNameLiteral, .vendor, .license, .licenseURL,
             .manufacturerURL, .designerURL, .format, .size, .importDate, .path:
            return nil
        }
    }

    // MARK: - In-memory aggregation (grouped browse without SQL summaries)

    static func aggregate(from fonts: [FontRecord]) -> FontFamilyUniformValues {
        FontFamilyUniformValues(
            family: fieldState(
                from: fonts,
                value: { FontDisplayNames.preferredFamily(for: $0) },
                field: .family
            ),
            typographicFamily: fieldState(from: fonts, value: \.typographicFamily, field: .typographicFamily),
            style: fieldState(from: fonts, value: \.subfamily, field: .subfamily),
            typographicStyle: fieldState(from: fonts, value: \.typographicSubfamily, field: .typographicSubfamily),
            postScript: fieldState(from: fonts, value: \.psName, field: .psName),
            uniqueName: fieldState(from: fonts, value: \.uniqueName, field: .uniqueName),
            version: fieldState(from: fonts, value: \.version, field: .version),
            manufacturer: fieldState(from: fonts, value: \.manufacturer, field: .manufacturer),
            vendorID: fieldState(from: fonts, value: \.vendorID, field: .vendorID),
            designer: fieldState(from: fonts, value: \.designer, field: .designer),
            description: fieldState(from: fonts, value: \.description, field: .description),
            trademark: fieldState(from: fonts, value: \.trademark, field: .trademark),
            copyright: fieldState(from: fonts, value: \.copyright, field: .copyright),
            formatDetailed: fieldState(from: fonts, value: \.formatDetailed, field: .formatDetailed)
        )
    }

    static func aggregateFieldState(from fonts: [FontRecord], column: FontListColumn) -> FontFamilyFieldState {
        let texts = fonts.map { column.rawDisplayValue(for: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return combineRawTexts(texts, styleCount: fonts.count, column: column, fonts: fonts)
    }

    /// Aggregate display strings (not per-row UI state) so family headers reflect value conflicts.
    private static func combineRawTexts(
        _ texts: [String],
        styleCount: Int,
        column: FontListColumn,
        fonts: [FontRecord]
    ) -> FontFamilyFieldState {
        guard styleCount > 0 else { return .empty }

        let populated = texts.enumerated().filter { !$0.element.isEmpty }
        if populated.isEmpty { return .empty }

        let distinct = Set(populated.map(\.element))
        if distinct.count > 1 || populated.count < styleCount {
            return .mixed
        }

        let value = distinct.first!
        if VaultSettings.metadataWarningsVisible, let field = column.metadataFieldKey {
            let issues = fonts.flatMap { $0.activeMetadataIssues(for: field) }
            if !issues.isEmpty {
                return .flagged(value, issues: Array(Set(issues)).sorted { $0.rawValue < $1.rawValue })
            }
            if fonts.contains(where: { $0.metadataIssues.isDerived(field) }),
               let font = fonts.first,
               let source = derivedSource(for: font, field: field) {
                return .derived(value, source)
            }
        }
        return .uniform(value)
    }

    private static func fieldState(
        from fonts: [FontRecord],
        value: (FontRecord) -> String,
        field: FontMetadataFieldKey
    ) -> FontFamilyFieldState {
        let states = fonts.map { font -> FontFamilyFieldState in
            let text = value(font).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return .empty }
            if VaultSettings.metadataWarningsVisible {
                let issues = font.activeMetadataIssues(for: field)
                if !issues.isEmpty { return .flagged(text, issues: issues) }
            }
            if font.metadataIssues.isDerived(field), let source = derivedSource(for: font, field: field) {
                return .derived(text, source)
            }
            return .uniform(text)
        }
        return combineStates(states)
    }

    static func fieldState(
        from fonts: [FontRecord],
        column: FontListColumn
    ) -> FontFamilyFieldState {
        guard let field = column.metadataFieldKey else {
            return aggregateFieldState(from: fonts, column: column)
        }
        return fieldState(from: fonts, value: columnValueReader(for: column), field: field)
    }

    private static func columnValueReader(for column: FontListColumn) -> (FontRecord) -> String {
        { column.rawDisplayValue(for: $0) }
    }

    private static func derivedSource(for font: FontRecord, field: FontMetadataFieldKey) -> FontFieldDerivedSource? {
        switch field {
        case .formatDetailed where font.formatDetailed.isEmpty:
            return .formatDetailedFromExtension
        default:
            return nil
        }
    }

    private static func combineStates(_ states: [FontFamilyFieldState]) -> FontFamilyFieldState {
        guard !states.isEmpty else { return .empty }

        let nonEmpty = states.filter {
            if case .empty = $0 { return false }
            return true
        }
        if nonEmpty.isEmpty { return .empty }

        if nonEmpty.contains(where: { if case .mixed = $0 { return true }; return false }) {
            return .mixed
        }

        let displayTexts = nonEmpty.map(displayText(for:))
        let populatedCount = nonEmpty.count
        let distinct = Set(displayTexts)

        if distinct.count > 1 || populatedCount < states.count {
            return .mixed
        }

        let representative = nonEmpty[0]
        switch representative {
        case .flagged(let value, _):
            let merged = nonEmpty.flatMap { state -> [MetadataIssue] in
                if case .flagged(_, let issues) = state { return issues }
                return []
            }
            return .flagged(value, issues: Array(Set(merged)).sorted { $0.rawValue < $1.rawValue })
        case .derived(let value, let source):
            return .derived(value, source)
        case .uniform(let value):
            return .uniform(value)
        case .mixed, .empty:
            return .mixed
        }
    }

    private static func displayText(for state: FontFamilyFieldState) -> String {
        switch state {
        case .empty: return ""
        case .uniform(let value), .derived(let value, _), .flagged(let value, _):
            return value
        case .mixed:
            return ImportDateDisplay.conflictDisplay
        }
    }
}
