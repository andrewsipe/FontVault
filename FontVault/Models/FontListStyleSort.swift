import Foundation

/// In-memory typographic style ordering (mirrors `CatalogBrowseSQL.styleOrderClause`).
enum FontListStyleSort {
    static func compare(_ lhs: FontRecord, _ rhs: FontRecord, ascending: Bool) -> Bool {
        let ordered: Bool
        if lhs.sortWidthClass != rhs.sortWidthClass {
            ordered = lhs.sortWidthClass < rhs.sortWidthClass
        } else if lhs.sortWeightClass != rhs.sortWeightClass {
            ordered = lhs.sortWeightClass < rhs.sortWeightClass
        } else if lhs.sortSlope != rhs.sortSlope {
            ordered = lhs.sortSlope < rhs.sortSlope
        } else {
            ordered = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
        return ascending ? ordered : !ordered
    }
}
