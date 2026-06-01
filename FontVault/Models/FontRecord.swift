import AppKit
import Foundation
import GRDB

struct FontRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var databaseID: Int64?
    var vaultPath: String
    var sha256: String
    var fileSize: Int64
    var format: String
    var dateAdded: TimeInterval
    var psName: String
    /// Preferred full name (ID 4 + fallbacks).
    var fullName: String
    /// Literal name ID 4 from the name table.
    var nameTableFullName: String
    var family: String
    var subfamily: String
    var typographicFamily: String
    var typographicSubfamily: String
    var license: String
    var licenseURL: String
    var manufacturerURL: String
    var designerURL: String
    var version: String
    /// Manufacturer / foundry name for catalog and search (same as `manufacturer` in metadata).
    var foundry: String
    var copyright: String
    var uniqueName: String
    var description: String
    var designer: String
    var trademark: String
    var manufacturer: String
    /// OS/2 `achVendID` (4-character registered vendor ID).
    var vendorID: String
    var formatDetailed: String
    var isVariable: Bool
    /// When true, vault scan can skip this path (if enforcement is on). Independent of table visibility.
    var excludedFromIndex: Bool
    /// Extended SFNT metrics and classification (JSON column).
    var extractedDetails: FontExtractedDetails
    /// Per-field quality flags and derivation markers (JSON column).
    var metadataIssues: FontMetadataIssues

    static let databaseTableName = "fonts"

    enum CodingKeys: String, CodingKey {
        case databaseID = "id"
        case vaultPath, sha256, fileSize, format, dateAdded
        case psName, fullName, nameTableFullName, family, subfamily, typographicFamily, typographicSubfamily
        case license, licenseURL, manufacturerURL, designerURL
        case version, foundry, copyright
        case uniqueName, description, designer, trademark, manufacturer, vendorID, formatDetailed
        case isVariable
        case excludedFromIndex
        case extractedDetails
        case metadataIssues
    }

    enum Columns: String, ColumnExpression {
        case databaseID = "id"
        case vaultPath, sha256, fileSize, format, dateAdded
        case psName, fullName, nameTableFullName, family, subfamily, typographicFamily, typographicSubfamily
        case license, licenseURL, manufacturerURL, designerURL
        case version, foundry, copyright
        case uniqueName, description, designer, trademark, manufacturer, vendorID, formatDetailed
        case isVariable
        case excludedFromIndex
        case extractedDetails
        case metadataIssues
    }

    var id: String { vaultPath }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        databaseID = inserted.rowID
    }

    /// Applies file metadata to an existing catalog row (keeps `dateAdded` and `vaultPath`).
    mutating func apply(metadata: FontFileMetadata, sha256: String, fileSize: Int64) {
        self.sha256 = sha256
        self.fileSize = fileSize
        self.format = metadata.format
        psName = metadata.psName
        fullName = metadata.fullName
        nameTableFullName = metadata.nameTableFullName
        family = metadata.family
        subfamily = metadata.subfamily
        typographicFamily = metadata.typographicFamily
        typographicSubfamily = metadata.typographicSubfamily
        license = metadata.license
        licenseURL = metadata.licenseURL
        manufacturerURL = metadata.manufacturerURL
        designerURL = metadata.designerURL
        version = metadata.version
        foundry = metadata.foundry
        copyright = metadata.copyright
        uniqueName = metadata.uniqueName
        description = metadata.description
        designer = metadata.designer
        trademark = metadata.trademark
        manufacturer = metadata.manufacturer
        vendorID = metadata.vendorID
        formatDetailed = metadata.formatDetailed
        isVariable = metadata.isVariable
        extractedDetails = metadata.extractedDetails
        metadataIssues = metadata.metadataIssues
    }

    static func from(metadata: FontFileMetadata, vaultPath: String, sha256: String, fileSize: Int64, dateAdded: TimeInterval) -> FontRecord {
        var record = FontRecord(
            databaseID: nil,
            vaultPath: vaultPath,
            sha256: sha256,
            fileSize: fileSize,
            format: metadata.format,
            dateAdded: dateAdded,
            psName: metadata.psName,
            fullName: metadata.fullName,
            nameTableFullName: metadata.nameTableFullName,
            family: metadata.family,
            subfamily: metadata.subfamily,
            typographicFamily: metadata.typographicFamily,
            typographicSubfamily: metadata.typographicSubfamily,
            license: metadata.license,
            licenseURL: metadata.licenseURL,
            manufacturerURL: metadata.manufacturerURL,
            designerURL: metadata.designerURL,
            version: metadata.version,
            foundry: metadata.foundry,
            copyright: metadata.copyright,
            uniqueName: metadata.uniqueName,
            description: metadata.description,
            designer: metadata.designer,
            trademark: metadata.trademark,
            manufacturer: metadata.manufacturer,
            vendorID: metadata.vendorID,
            formatDetailed: metadata.formatDetailed,
            isVariable: metadata.isVariable,
            excludedFromIndex: false,
            extractedDetails: metadata.extractedDetails,
            metadataIssues: metadata.metadataIssues
        )
        record.reconcilePostScriptFilenameIssues()
        return record
    }

    /// File name in the vault (no directory), without extension — used for PostScript vs disk checks.
    var vaultFileNameStem: String {
        let fileName = (vaultPath as NSString).lastPathComponent
        return (fileName as NSString).deletingPathExtension
    }

    /// Stored issues plus live checks (e.g. PostScript vs current vault file name).
    func activeMetadataIssues(for field: FontMetadataFieldKey) -> [MetadataIssue] {
        var issues = metadataIssues.activeIssues(for: field)
        if field == .psName {
            let live = FontMetadataValidator.postScriptFilenameIssues(
                psName: psName,
                fileStem: vaultFileNameStem
            )
            issues = Array(Set(issues + live)).sorted { $0.rawValue < $1.rawValue }
        }
        return issues
    }

    var hasAnyActiveMetadataIssue: Bool {
        FontMetadataFieldKey.allCases.contains { !activeMetadataIssues(for: $0).isEmpty }
    }

    /// Persists PostScript vs vault file name into catalog metadata issues.
    mutating func reconcilePostScriptFilenameIssues() {
        var merged = metadataIssues.issues(for: .psName).filter {
            $0 != .postScriptNameInvalid && $0 != .postScriptNameFilenameMismatch
        }
        merged.append(contentsOf: FontMetadataValidator.postScriptFilenameIssues(
            psName: psName,
            fileStem: vaultFileNameStem
        ))
        metadataIssues.setIssues(
            Array(Set(merged)).sorted { $0.rawValue < $1.rawValue },
            for: .psName
        )
    }
}

enum FontFormat: String {
    case otf, ttf, ttc, woff, woff2, mixed, unknown

    static func from(pathExtension: String) -> FontFormat {
        switch pathExtension.lowercased() {
        case "otf": return .otf
        case "ttf": return .ttf
        case "ttc", "otc": return .ttc
        case "woff": return .woff
        case "woff2": return .woff2
        default: return .unknown
        }
    }

    var badgeLabel: String {
        switch self {
        case .otf: return "OTF"
        case .ttf: return "TTF"
        case .ttc: return "TTC"
        case .woff: return "WOFF"
        case .woff2: return "WOFF2"
        case .mixed: return "MIXED"
        case .unknown: return "?"
        }
    }

    /// Fixed width for all format pills (matches WOFF2 — the widest standard label).
    static let uniformBadgeWidth: CGFloat = 56

    var preferredBadgeWidth: CGFloat {
        switch self {
        case .unknown: return 30
        default: return Self.uniformBadgeWidth
        }
    }

    /// Format badge for a family row (MIXED when the family contains multiple formats).
    static func aggregate(for fonts: [FontRecord]) -> FontFormat {
        aggregate(forFormatStrings: fonts.map(\.format))
    }

    static func aggregate(forFormatStrings formatStrings: [String]) -> FontFormat {
        let formats = Set(formatStrings.map { from(pathExtension: $0) }.filter { $0 != .unknown })
        if formats.count > 1 { return .mixed }
        return formats.first ?? .unknown
    }

    /// Colored pill for list / inspector format badges (readable on light and dark backgrounds).
    var badgeColors: (background: NSColor, foreground: NSColor) {
        switch self {
        case .mixed:
            return (NSColor.systemIndigo, .black)
        case .otf:
            return (NSColor.systemGreen, .black)
        case .ttf:
            return (NSColor.systemCyan, .black)
        case .woff:
            return (NSColor.systemYellow, .black)
        case .woff2:
            return (NSColor.systemOrange, .black)
        case .ttc:
            return (NSColor.systemGray, .black)
        case .unknown:
            return (NSColor.tertiaryLabelColor, .secondaryLabelColor)
        }
    }
}
