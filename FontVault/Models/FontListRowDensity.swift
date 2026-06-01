import Foundation

/// Vertical spacing for font list rows (independent of column visibility).
enum FontListRowDensity: String, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .comfortable: return "Comfortable"
        }
    }

    var detail: String {
        switch self {
        case .compact:
            return "Tighter row height for dense browsing."
        case .comfortable:
            return """
            Extra vertical padding on every row. With grouping off and the Family column hidden, \
            the family name appears above the font name in the Name column.
            """
        }
    }
}
