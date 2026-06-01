import Foundation

/// Catalog field keys for metadata quality / derivation tracking.
enum FontMetadataFieldKey: String, Codable, CaseIterable, Sendable {
    case psName
    case fullName
    case family
    case subfamily
    case typographicFamily
    case typographicSubfamily
    case version
    case manufacturer
    case vendorID
    case copyright
    case uniqueName
    case description
    case designer
    case trademark
    case formatDetailed
}

/// Why a stored metadata value is suspicious (value is still shown).
enum MetadataIssue: String, Codable, CaseIterable, Hashable, Sendable {
    case controlCharacter
    case decodeReplacement
    case nonPrintableCharacter
    case vendorIDMalformed
    case postScriptNameInvalid
    case postScriptNameFilenameMismatch
    case nameTableCoreTextMismatch
    case placeholderOnly
}

extension MetadataIssue {
    /// Issues still decoded from older catalogs but no longer shown or re-imported.
    var countsForUserAttention: Bool {
        switch self {
        case .nameTableCoreTextMismatch, .postScriptNameInvalid:
            return false
        default:
            return true
        }
    }

    static func userFacing(_ issues: [MetadataIssue]) -> [MetadataIssue] {
        issues.filter(\.countsForUserAttention)
    }

    var label: String {
        switch self {
        case .controlCharacter: return "Contains control characters"
        case .decodeReplacement: return "Contains replacement characters (decode error)"
        case .nonPrintableCharacter: return "Contains non-printable characters"
        case .vendorIDMalformed: return "Vendor ID is not four ASCII letters or digits"
        case .postScriptNameInvalid: return "PostScript name has invalid characters"
        case .postScriptNameFilenameMismatch:
            return "PostScript name does not match the file name on disk"
        case .nameTableCoreTextMismatch:
            return "Name table string differs from what macOS reports for this font"
        case .placeholderOnly: return "Value looks like a placeholder"
        }
    }

    static func tooltip(for issues: [MetadataIssue]) -> String {
        let unique = Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
        return unique.map(\.label).joined(separator: "\n")
    }

    /// Tooltip for the metadata warning icon in list cells.
    static func metadataWarningTooltip(columnTitle: String, issues: [MetadataIssue]) -> String {
        let reasons = tooltip(for: issues)
        guard !reasons.isEmpty else { return columnTitle }
        return "\(columnTitle)\n\(reasons)"
    }
}

/// Per-field issues and derivation flags stored in the catalog (JSON column).
struct FontMetadataIssues: Codable, Sendable, Equatable, Hashable {
    var issuesByField: [String: [MetadataIssue]] = [:]
    var derivedFields: [String] = []

    static let empty = FontMetadataIssues()

    func issues(for field: FontMetadataFieldKey) -> [MetadataIssue] {
        issuesByField[field.rawValue] ?? []
    }

    /// Issues that should flag cells, show gradients, or display warning icons.
    func activeIssues(for field: FontMetadataFieldKey) -> [MetadataIssue] {
        MetadataIssue.userFacing(issues(for: field))
    }

    func activeIssues(for column: FontListColumn) -> [MetadataIssue] {
        guard let key = column.metadataFieldKey else { return [] }
        return activeIssues(for: key)
    }

    func issues(for column: FontListColumn) -> [MetadataIssue] {
        guard let key = column.metadataFieldKey else { return [] }
        return issues(for: key)
    }

    func isDerived(_ field: FontMetadataFieldKey) -> Bool {
        derivedFields.contains(field.rawValue)
    }

    func isDerived(column: FontListColumn) -> Bool {
        guard let key = column.metadataFieldKey else { return false }
        return isDerived(key)
    }

    mutating func setIssues(_ issues: [MetadataIssue], for field: FontMetadataFieldKey) {
        if issues.isEmpty {
            issuesByField.removeValue(forKey: field.rawValue)
        } else {
            issuesByField[field.rawValue] = issues
        }
    }

    mutating func markDerived(_ field: FontMetadataFieldKey) {
        if !derivedFields.contains(field.rawValue) {
            derivedFields.append(field.rawValue)
        }
    }

    var hasAnyIssue: Bool {
        !issuesByField.isEmpty
    }

    var hasAnyActiveIssue: Bool {
        issuesByField.values.contains { !MetadataIssue.userFacing($0).isEmpty }
    }
}

/// Fallback source when the displayed value comes from another field.
enum FontFieldDerivedSource: String, Codable, Hashable, Sendable {
    case typographicFamilyFromFamily
    case typographicStyleFromSubfamily
    case formatDetailedFromExtension
}

extension FontFieldDerivedSource {
    var label: String {
        switch self {
        case .typographicFamilyFromFamily: return "From Family name"
        case .typographicStyleFromSubfamily: return "From Style name"
        case .formatDetailedFromExtension: return "From file extension"
        }
    }
}
