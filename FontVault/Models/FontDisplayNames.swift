import Foundation

/// FEX-aligned display strings derived from catalog name-table fields.
enum FontDisplayNames {
    /// Preferred family for list / grouping: ID 16 when present, else ID 1.
    static func preferredFamily(typographicFamily: String, family: String) -> String {
        let typo = typographicFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typo.isEmpty { return typo }
        return family.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func preferredFamily(for font: FontRecord) -> String {
        preferredFamily(typographicFamily: font.typographicFamily, family: font.family)
    }

    /// SQL expression matching `preferredFamily(typographicFamily:family:)`.
    static let preferredFamilySQLExpression = """
        CASE
            WHEN NULLIF(TRIM(typographicFamily), '') IS NOT NULL THEN TRIM(typographicFamily)
            WHEN NULLIF(TRIM(family), '') IS NOT NULL THEN TRIM(family)
            ELSE '_Unknown'
        END
        """

    /// Registry vendor name, or `Unknown` when tag is set but not registered (FEX-style).
    static func vendorFriendlyName(forVendorID vendorID: String) -> String {
        let tag = vendorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return "" }
        if let name = FontVendorRegistry.registeredName(forVendorID: tag) {
            return name
        }
        return "Unknown"
    }

    static func vendorFriendlyName(for font: FontRecord) -> String {
        vendorFriendlyName(forVendorID: font.vendorID)
    }
}

extension FontRecord {
    var preferredFamily: String {
        FontDisplayNames.preferredFamily(for: self)
    }

    var preferredFullName: String {
        fullName
    }
}
