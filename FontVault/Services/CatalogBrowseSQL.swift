import Foundation
import GRDB

/// Shared SQL fragments for windowed catalog browse (family summaries, flat paths).
enum CatalogBrowseSQL {
    /// Matches `FontDisplayNames.preferredFamily` / `FontListGrouping.familyKey(for:)`.
    static let familyKeyExpression = FontDisplayNames.preferredFamilySQLExpression

    static func filterClause(query: FontTableBrowseQuery) -> (sql: String, arguments: [DatabaseValueConvertible]) {
        var parts: [String] = []
        var args: [DatabaseValueConvertible] = []
        if !query.search.isEmpty {
            let pattern = "%\(query.search)%"
            parts.append("""
                (fullName LIKE ? OR family LIKE ? OR typographicFamily LIKE ? OR psName LIKE ?
                OR foundry LIKE ? OR manufacturer LIKE ? OR designer LIKE ? OR uniqueName LIKE ?
                OR vendorID LIKE ? OR copyright LIKE ?)
                """)
            args.append(contentsOf: Array(repeating: pattern, count: 10))
        }
        if let format = query.format, !format.isEmpty {
            if format == FontSidebarFilter.variableOnly {
                parts.append("isVariable = 1")
            } else {
                parts.append("format = ?")
                args.append(format)
            }
        }
        switch query.tableScope {
        case .excludedFontsOnly:
            parts.append("excludedFromIndex = 1")
        case .allFonts:
            if !query.showIgnoredFonts {
                parts.append("excludedFromIndex = 0")
            }
        }
        guard !parts.isEmpty else { return ("", []) }
        return (" WHERE " + parts.joined(separator: " AND "), args)
    }

    /// Active (non-excluded) rows only — sidebar format chips and similar.
    static func activeOnlyClause() -> (sql: String, arguments: [DatabaseValueConvertible]) {
        (" WHERE excludedFromIndex = 0", [])
    }

    /// Safe column name for ORDER BY (catalog columns only).
    static func validatedSortColumn(_ sortColumn: String) -> String {
        let allowed: Set<String> = [
            "fullName", "family", "preferredFamily", "subfamily", "format", "fileSize", "dateAdded",
            "vaultPath", "psName", "uniqueName", "version", "foundry", "manufacturer", "designer",
            "vendorID", "copyright", "description", "trademark", "typographicFamily",
            "typographicSubfamily", "formatDetailed", "nameTableFullName",
            "license", "licenseURL", "manufacturerURL", "designerURL"
        ]
        return allowed.contains(sortColumn) ? sortColumn : "fullName"
    }

    static func fontSortExpression(sortColumn: String) -> String {
        switch sortColumn {
        case "family", "preferredFamily":
            return familyKeyExpression
        default:
            return validatedSortColumn(sortColumn)
        }
    }

    static func familyOrderExpression(sortColumn: String, ascending: Bool) -> String {
        let col = validatedSortColumn(sortColumn)
        let direction = ascending ? "ASC" : "DESC"
        switch col {
        case "family", "preferredFamily":
            return "familyKey COLLATE NOCASE \(direction)"
        case "format":
            return "MIN(format) COLLATE NOCASE \(direction)"
        case "fileSize":
            return "SUM(fileSize) \(direction)"
        case "dateAdded":
            return "MAX(dateAdded) \(direction)"
        default:
            return "MIN(\(col)) COLLATE NOCASE \(direction)"
        }
    }

    static func fontOrderClause(sortColumn: String, ascending: Bool) -> String {
        let col = fontSortExpression(sortColumn: sortColumn)
        let direction = ascending ? "ASC" : "DESC"
        return "\(col) COLLATE NOCASE \(direction), vaultPath ASC"
    }

    /// Per-field `COUNT DISTINCT` / populated / `MIN` fragments for `fetchFamilySummaries`.
    static func familyUniformAggregateSelectColumns() -> String {
        let fields: [(prefix: String, expression: String)] = [
            ("family", familyKeyExpression),
            ("typographicFamily", "typographicFamily"),
            ("manufacturer", "manufacturer"),
            ("vendorID", "vendorID"),
            ("formatDetailed", "formatDetailed"),
            ("style", "subfamily"),
            ("typographicStyle", "typographicSubfamily"),
            ("postScript", "psName"),
            ("uniqueName", "uniqueName"),
            ("version", "version"),
            ("designer", "designer"),
            ("description", "description"),
            ("trademark", "trademark"),
            ("copyright", "copyright"),
        ]
        return fields.map { field in
            """
            COUNT(DISTINCT NULLIF(TRIM(\(field.expression)), '')) AS \(field.prefix)UniformCount,
            SUM(CASE WHEN NULLIF(TRIM(\(field.expression)), '') IS NOT NULL THEN 1 ELSE 0 END) AS \(field.prefix)PopulatedCount,
            MIN(NULLIF(TRIM(\(field.expression)), '')) AS \(field.prefix)UniformValue
            """
        }.joined(separator: ",\n                ")
    }
}
