import Foundation

/// Context menu actions beyond copy/metadata (represented on `NSMenuItem.representedObject`).
enum FontListContextMenuActionKind: String {
    case openURL
    case copyURL
    case find
    /// `representedObject` suffix is the format filter key (e.g. `otf`).
    case showOnlyFormat
    case clearFormatFilter
    case smartFilterExcludedFonts
}

extension FontListContextMenuActionKind {
    static func showOnlyFormatKey(_ filterKey: String) -> String {
        "\(FontListContextMenuActionKind.showOnlyFormat.rawValue):\(filterKey)"
    }

    static func parseShowOnlyFormatKey(_ raw: String) -> String? {
        let prefix = "\(FontListContextMenuActionKind.showOnlyFormat.rawValue):"
        guard raw.hasPrefix(prefix) else { return nil }
        let key = String(raw.dropFirst(prefix.count))
        return key.isEmpty ? nil : key
    }
}

struct FontListFormatFilterMenuOption: Equatable {
    let filterKey: String
    let badgeLabel: String
}
