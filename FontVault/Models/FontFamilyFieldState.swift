import Foundation

/// Aggregated column value for a family row (SQL summary or in-memory grouping).
enum FontFamilyFieldState: Equatable, Hashable, Sendable {
    case empty
    case uniform(String)
    case mixed
    /// Display value inferred from another field.
    case derived(String, FontFieldDerivedSource)
    /// Value shown but failed metadata quality checks.
    case flagged(String, issues: [MetadataIssue])
}

extension FontFamilyFieldState {
    /// Text for table / outline cells (`""` when empty, em dash when mixed).
    var tableText: String {
        cellPresentation.text
    }

    /// Uniform string when every style agrees; nil when empty or mixed.
    var uniformValue: String? {
        switch self {
        case .uniform(let value), .derived(let value, _), .flagged(let value, _):
            return value
        case .empty, .mixed:
            return nil
        }
    }
}
