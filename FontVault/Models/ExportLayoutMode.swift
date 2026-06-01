import Foundation

/// Export layout modes. Settings holds the persistent default; File → Export can override per run.
/// Drag-out export currently always uses family grouping (see NOTES — export persistence).
enum ExportLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case byFamily
    case vaultStructure
    case flat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .byFamily: return "Group by family"
        case .vaultStructure: return "Maintain vault layout (A–Z buckets)"
        case .flat: return "Flat (file names only)"
        }
    }

    /// Longer copy for Settings.
    var detail: String {
        switch self {
        case .byFamily:
            return """
            One family: Family Name (count)/font files. Several families: FontVault Export/Family Name (count)/… \
            (same as dragging out of the list). A single font is copied without a folder.
            """
        case .vaultStructure:
            return "Preserves letter buckets and style folders from the vault."
        case .flat:
            return "Copies all files into the destination folder using their file names."
        }
    }

}
