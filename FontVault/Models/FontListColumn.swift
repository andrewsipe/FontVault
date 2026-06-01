import Foundation
import SwiftUI

/// Columns available in the font list (FEX-style header context menu).
enum FontListColumn: String, CaseIterable, Identifiable, Codable, Sendable {
    case name
    case family
    case fontFamily
    case fullNameLiteral
    case style
    case typographicFamily
    case typographicStyle
    case postScript
    case uniqueName
    case format
    case formatDetailed
    case size
    case importDate
    case path
    case version
    case manufacturer
    case vendorID
    case vendor
    case designer
    case description
    case trademark
    case copyright
    case license
    case licenseURL
    case manufacturerURL
    case designerURL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .family: return "Family"
        case .fontFamily: return "Font Family (ID 1)"
        case .fullNameLiteral: return "Full Name (ID 4)"
        case .style: return "Style"
        case .typographicFamily: return "Typographic Family"
        case .typographicStyle: return "Typographic Style"
        case .postScript: return "PostScript"
        case .uniqueName: return "Unique Name"
        case .format: return "Format"
        case .formatDetailed: return "Format (detailed)"
        case .size: return "Size"
        case .importDate: return "Import Date"
        case .path: return "Path"
        case .version: return "Version"
        case .manufacturer: return "Manufacturer"
        case .vendorID: return "Vendor ID"
        case .vendor: return "Vendor"
        case .designer: return "Designer"
        case .description: return "Description"
        case .trademark: return "Trademark"
        case .copyright: return "Copyright"
        case .license: return "License"
        case .licenseURL: return "License URL"
        case .manufacturerURL: return "Manufacturer URL"
        case .designerURL: return "Designer URL"
        }
    }

    var isRequired: Bool { self == .name }

    var defaultWidth: CGFloat {
        switch self {
        case .name: return 220
        case .format: return 88
        case .size: return 72
        case .importDate: return 96
        case .path: return 200
        case .uniqueName, .postScript: return 160
        case .formatDetailed: return 180
        case .vendorID: return 64
        case .vendor: return 100
        default: return 120
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .name: return 120
        case .format: return 72
        default: return 56
        }
    }

    var maxWidth: CGFloat { 640 }

    /// Resolves width from persisted values without touching main-actor state.
    func resolvedWidth(stored: CGFloat?) -> CGFloat {
        guard let stored else { return defaultWidth }
        return min(maxWidth, max(minWidth, stored))
    }

    var isTrailing: Bool { false }

    var customizationID: String { rawValue }

    /// Catalog / `AppState.sortColumn` identifier.
    var databaseSortColumn: String {
        switch self {
        case .name: return "fullName"
        case .family: return "family"
        case .fontFamily: return "family"
        case .fullNameLiteral: return "nameTableFullName"
        case .style: return "subfamily"
        case .typographicFamily: return "typographicFamily"
        case .typographicStyle: return "typographicSubfamily"
        case .postScript: return "psName"
        case .uniqueName: return "uniqueName"
        case .format: return "format"
        case .formatDetailed: return "formatDetailed"
        case .size: return "fileSize"
        case .importDate: return "dateAdded"
        case .path: return "vaultPath"
        case .version: return "version"
        case .manufacturer: return "manufacturer"
        case .vendorID: return "vendorID"
        case .vendor: return "vendorID"
        case .designer: return "designer"
        case .description: return "description"
        case .trademark: return "trademark"
        case .copyright: return "copyright"
        case .license: return "license"
        case .licenseURL: return "licenseURL"
        case .manufacturerURL: return "manufacturerURL"
        case .designerURL: return "designerURL"
        }
    }

    static func from(databaseSortColumn: String) -> FontListColumn? {
        allCases.first { $0.databaseSortColumn == databaseSortColumn }
    }

    /// Stable string for matching `KeyPathComparator.keyPath` from table header clicks.
    var sortKeyPathDescription: String {
        String(describing: sortComparator(ascending: true).keyPath)
    }

    static func from(sortComparator comparator: KeyPathComparator<FontRecord>) -> FontListColumn? {
        let description = String(describing: comparator.keyPath)
        return allCases.first { $0.sortKeyPathDescription == description }
    }

    func sortComparator(ascending: Bool) -> KeyPathComparator<FontRecord> {
        let order: SortOrder = ascending ? .forward : .reverse
        switch self {
        case .name: return KeyPathComparator(\.fullName, order: order)
        case .family: return KeyPathComparator(\FontRecord.preferredFamily, order: order)
        case .fontFamily: return KeyPathComparator(\.family, order: order)
        case .fullNameLiteral: return KeyPathComparator(\.nameTableFullName, order: order)
        case .style: return KeyPathComparator(\.subfamily, order: order)
        case .typographicFamily: return KeyPathComparator(\.typographicFamily, order: order)
        case .typographicStyle: return KeyPathComparator(\.typographicSubfamily, order: order)
        case .postScript: return KeyPathComparator(\.psName, order: order)
        case .uniqueName: return KeyPathComparator(\.uniqueName, order: order)
        case .format: return KeyPathComparator(\.format, order: order)
        case .formatDetailed: return KeyPathComparator(\.formatDetailed, order: order)
        case .size: return KeyPathComparator(\.fileSize, order: order)
        case .importDate: return KeyPathComparator(\.dateAdded, order: order)
        case .path: return KeyPathComparator(\.vaultPath, order: order)
        case .version: return KeyPathComparator(\.version, order: order)
        case .manufacturer: return KeyPathComparator(\.manufacturer, order: order)
        case .vendorID: return KeyPathComparator(\.vendorID, order: order)
        case .vendor: return KeyPathComparator(\.vendorID, order: order)
        case .designer: return KeyPathComparator(\.designer, order: order)
        case .description: return KeyPathComparator(\.description, order: order)
        case .trademark: return KeyPathComparator(\.trademark, order: order)
        case .copyright: return KeyPathComparator(\.copyright, order: order)
        case .license: return KeyPathComparator(\.license, order: order)
        case .licenseURL: return KeyPathComparator(\.licenseURL, order: order)
        case .manufacturerURL: return KeyPathComparator(\.manufacturerURL, order: order)
        case .designerURL: return KeyPathComparator(\.designerURL, order: order)
        }
    }

    static let defaultVisible: [FontListColumn] = [.name, .family, .format, .size, .importDate]

    func widthConstraints(storedWidth: CGFloat?) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        let ideal = resolvedWidth(stored: storedWidth)
        return (minWidth, ideal, maxWidth)
    }

    /// Raw catalog value for a column.
    func cellText(for font: FontRecord) -> String {
        switch self {
        case .name: return font.preferredFullName
        case .family: return font.preferredFamily
        case .fontFamily: return font.family
        case .fullNameLiteral: return font.nameTableFullName
        case .style: return font.subfamily
        case .typographicFamily: return font.typographicFamily
        case .typographicStyle: return font.typographicSubfamily
        case .postScript: return font.psName
        case .uniqueName: return font.uniqueName
        case .format: return FontFormat.from(pathExtension: font.format).badgeLabel
        case .formatDetailed: return font.formatDetailed
        case .size: return ByteCountFormatter.string(fromByteCount: font.fileSize, countStyle: .file)
        case .importDate: return ImportDateDisplay.format(font.dateAdded)
        case .path: return font.vaultPath
        case .version: return font.version
        case .manufacturer: return font.manufacturer
        case .vendorID: return font.vendorID
        case .vendor: return FontDisplayNames.vendorFriendlyName(for: font)
        case .designer: return font.designer
        case .description: return font.description
        case .trademark: return font.trademark
        case .copyright: return font.copyright
        case .license: return font.license
        case .licenseURL: return font.licenseURL
        case .manufacturerURL: return font.manufacturerURL
        case .designerURL: return font.designerURL
        }
    }

    /// Catalog-backed metadata field for this column, when applicable.
    var metadataFieldKey: FontMetadataFieldKey? {
        switch self {
        case .name: return .fullName
        case .family, .fontFamily: return .family
        case .fullNameLiteral: return .fullName
        case .style: return .subfamily
        case .typographicFamily: return .typographicFamily
        case .typographicStyle: return .typographicSubfamily
        case .postScript: return .psName
        case .uniqueName: return .uniqueName
        case .formatDetailed: return .formatDetailed
        case .version: return .version
        case .manufacturer: return .manufacturer
        case .vendorID: return .vendorID
        case .designer: return .designer
        case .description: return .description
        case .trademark: return .trademark
        case .copyright: return .copyright
        case .vendor, .license, .licenseURL, .manufacturerURL, .designerURL,
             .format, .size, .importDate, .path:
            return nil
        }
    }

    /// Value shown in the table for one font row (empty string when the field has no data).
    func tableDisplayText(for font: FontRecord) -> String {
        fontFieldState(for: font).tableText
    }

    func fontCellPresentation(for font: FontRecord) -> FontListCellPresentation {
        fontFieldState(for: font)
            .cellPresentation(columnTitle: title)
            .applyingLinkStyleIfNeeded(column: self)
    }

    func familyCellPresentation(
        for section: FontFamilySection,
        loadedFonts: [FontRecord] = []
    ) -> FontListCellPresentation {
        familyFieldState(for: section, loadedFonts: loadedFonts).cellPresentation(columnTitle: title)
    }

    func fontFieldState(for font: FontRecord) -> FontFamilyFieldState {
        let display = rawDisplayValue(for: font)
        if display.isEmpty { return .empty }

        if VaultSettings.metadataWarningsVisible, let key = metadataFieldKey {
            let issues = font.activeMetadataIssues(for: key)
            if !issues.isEmpty {
                return .flagged(display, issues: issues)
            }
            if font.metadataIssues.isDerived(key), let source = derivedSource(for: font, field: key) {
                return .derived(display, source)
            }
        }
        return .uniform(display)
    }

    func familyCellText(for section: FontFamilySection) -> String {
        familyFieldState(for: section).tableText
    }

    func familyFieldState(
        for section: FontFamilySection,
        loadedFonts: [FontRecord] = []
    ) -> FontFamilyFieldState {
        let childFonts = loadedFonts.isEmpty ? section.fonts : loadedFonts
        if !childFonts.isEmpty, metadataFieldKey != nil {
            return FontFamilyUniformValues.fieldState(from: childFonts, column: self)
        }
        switch self {
        case .name:
            return .uniform(section.displayName)
        case .family:
            switch section.uniformValues.family {
            case .uniform(let value): return .uniform(value)
            case .mixed: return .mixed
            case .empty: return .uniform(section.displayName)
            case .derived(let value, let source): return .derived(value, source)
            case .flagged(let value, let issues): return .flagged(value, issues: issues)
            }
        case .typographicFamily:
            return section.uniformValues.typographicFamily
        case .format:
            return .uniform(FontFormat.aggregate(forFormatStrings: section.distinctFormats).badgeLabel)
        case .formatDetailed:
            return section.uniformValues.formatDetailed
        case .manufacturer:
            return section.uniformValues.manufacturer
        case .vendorID:
            return section.uniformValues.vendorID
        case .vendor:
            return vendorFamilyState(for: section, loadedFonts: childFonts)
        case .size:
            return .uniform(ByteCountFormatter.string(fromByteCount: section.totalSize, countStyle: .file))
        case .importDate:
            return section.importDateState
        case .path:
            return .empty
        default:
            return section.uniformValues.fieldState(for: self) ?? .empty
        }
    }

    func rawDisplayValue(for font: FontRecord) -> String {
        switch self {
        case .formatDetailed:
            if !font.formatDetailed.isEmpty { return font.formatDetailed }
            return FontFormat.from(pathExtension: font.format).badgeLabel
        default:
            return cellText(for: font)
        }
    }

    private func derivedSource(for font: FontRecord, field: FontMetadataFieldKey) -> FontFieldDerivedSource? {
        switch field {
        case .formatDetailed where font.formatDetailed.isEmpty:
            return .formatDetailedFromExtension
        default:
            return nil
        }
    }

    private func vendorFamilyState(for section: FontFamilySection, loadedFonts: [FontRecord]) -> FontFamilyFieldState {
        let texts = loadedFonts.map { FontDisplayNames.vendorFriendlyName(for: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let populated = texts.filter { !$0.isEmpty }
        guard !populated.isEmpty else { return .empty }
        let distinct = Set(populated)
        if distinct.count > 1 || populated.count < loadedFonts.count {
            return .mixed
        }
        return .uniform(distinct.first!)
    }
}
