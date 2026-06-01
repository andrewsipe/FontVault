import Foundation

/// Stable outline row node (`NSOutlineView` matches rows by object identity).
final class FontListOutlineNode: NSObject {
    let payload: FontListOutlineItem
    private(set) var childNodes: [FontListOutlineNode]?
    /// Cached family-header field states after child rows load (cleared when children change).
    private var familyFieldStateByColumn: [String: FontFamilyFieldState]?

    init(family section: FontFamilySection) {
        payload = .family(section)
        if section.fonts.isEmpty {
            childNodes = nil
        } else {
            childNodes = section.fonts.map { FontListOutlineNode(font: $0) }
        }
        super.init()
    }

    init(font: FontRecord) {
        payload = .font(font)
        childNodes = nil
        super.init()
    }

    /// Flat list row before `FontRecord` is resolved from SQL.
    init(vaultPath: String) {
        payload = .fontPath(vaultPath)
        childNodes = nil
        super.init()
    }

    var children: [FontListOutlineNode]? { childNodes }

    var isChildrenLoaded: Bool { childNodes != nil }

    var childCount: Int {
        guard isFamily, case .family(let section) = payload else { return 0 }
        return childNodes?.count ?? section.styleCount
    }

    func setChildNodes(_ nodes: [FontListOutlineNode]) {
        childNodes = nodes
        familyFieldStateByColumn = nil
    }

    func familyFieldState(
        column: FontListColumn,
        section: FontFamilySection,
        loadedFonts: [FontRecord]
    ) -> FontFamilyFieldState {
        if !loadedFonts.isEmpty, let cached = familyFieldStateByColumn?[column.rawValue] {
            return cached
        }
        let state = column.familyFieldState(for: section, loadedFonts: loadedFonts)
        if !loadedFonts.isEmpty {
            if familyFieldStateByColumn == nil {
                familyFieldStateByColumn = [:]
            }
            familyFieldStateByColumn?[column.rawValue] = state
        }
        return state
    }

    var familySection: FontFamilySection? { payload.familySection }

    var isFamily: Bool { payload.isFamily }
    var vaultPath: String? { payload.vaultPath }
    var familyID: String? {
        if case .family(let section) = payload { return section.id }
        return nil
    }
}

/// Row payload for AppKit `NSOutlineView` (family header or font style).
enum FontListOutlineItem: Hashable {
    case family(FontFamilySection)
    case font(FontRecord)
    case fontPath(String)

    var isFamily: Bool {
        if case .family = self { return true }
        return false
    }

    /// Stable outline identity (family rows use `family:` prefix like SwiftUI table).
    var outlineID: String {
        switch self {
        case .family(let section):
            return "family:\(section.id)"
        case .font(let font):
            return font.vaultPath
        case .fontPath(let path):
            return path
        }
    }

    /// Vault path when this row represents a font file.
    var vaultPath: String? {
        switch self {
        case .font(let font):
            return font.vaultPath
        case .fontPath(let path):
            return path
        case .family:
            return nil
        }
    }

    var familySection: FontFamilySection? {
        if case .family(let section) = self { return section }
        return nil
    }
}

extension FontListColumn {
    /// Name column content for styled AppKit cells.
    func nameCellPresentation(
        for item: FontListOutlineItem,
        showFamilySubtitle: Bool
    ) -> (primary: String, secondary: String?, isFamilyHeader: Bool)? {
        guard self == .name else { return nil }
        switch item {
        case .family(let section):
            return (
                FontListGrouping.familyRowTitle(
                    displayName: section.displayName,
                    styleCount: section.styleCount
                ),
                nil,
                true
            )
        case .font(let font):
            let secondary = showFamilySubtitle && !font.preferredFamily.isEmpty ? font.preferredFamily : nil
            return (font.preferredFullName, secondary, false)
        case .fontPath:
            return nil
        }
    }

    /// Cell text for AppKit outline rows (plain text fallback).
    func outlineText(for item: FontListOutlineItem, showFamilySubtitle: Bool) -> String {
        switch item {
        case .family(let section):
            let familyText = familyCellText(for: section)
            if self == .name {
                return FontListGrouping.familyRowTitle(
                    displayName: section.displayName,
                    styleCount: section.styleCount
                )
            }
            return familyText
        case .font(let font):
            if self == .name, showFamilySubtitle, !font.preferredFamily.isEmpty {
                return "\(font.preferredFullName)\n\(font.preferredFamily)"
            }
            return tableDisplayText(for: font)
        case .fontPath(let path):
            return path
        }
    }
}
