import Foundation

/// Sidebar navigation selection (drives browser mode and format filter).
enum SidebarItem: Hashable, Identifiable {
    case allFonts
    case duplicates
    case format(filterKey: String)
    case smartFilter(SmartFilterID)

    var id: String {
        switch self {
        case .allFonts: return "allFonts"
        case .duplicates: return "duplicates"
        case .format(let key): return "format-\(key)"
        case .smartFilter(let filter): return "smartFilter-\(filter.rawValue)"
        }
    }
}
