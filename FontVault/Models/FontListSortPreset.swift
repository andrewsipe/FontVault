import Foundation

/// Default font-table sort presets (distinct from per-column header overrides).
enum FontListSortPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case byName
    case styleOrder

    var id: String { rawValue }

    /// Reserved `AppState.sortColumn` value for width → weight → slope → name ordering.
    static let styleOrderSortColumn = "styleOrder"

    var sortColumn: String {
        switch self {
        case .byName: return "fullName"
        case .styleOrder: return Self.styleOrderSortColumn
        }
    }

    static func isPresetSortColumn(_ column: String) -> Bool {
        column == "fullName" || column == styleOrderSortColumn
    }

    var label: String {
        switch self {
        case .byName: return "By name"
        case .styleOrder: return "Style order"
        }
    }

    var detail: String {
        switch self {
        case .byName:
            return "Alphabetical on the display name."
        case .styleOrder:
            return "Width, then weight, then upright before italic, then name."
        }
    }
}
