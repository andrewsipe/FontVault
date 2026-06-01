import Foundation

/// Inspector rows (FEX Information panel — broader than list columns).
enum InspectorField: String, CaseIterable, Identifiable, Codable, Sendable {
    case postScript
    case uniqueName
    case fullNameLiteral
    case family
    case style
    case typographicFamily
    case typographicStyle
    case version
    case description
    case designer
    case trademark
    case manufacturer
    case vendorID
    case vendor
    case copyright
    case license
    case licenseURL
    case manufacturerURL
    case designerURL
    case formatDetailed
    case vaultPath
    case importDate
    case sha256

    var id: String { rawValue }

    var label: String {
        switch self {
        case .postScript: return "PostScript"
        case .uniqueName: return "Unique Name"
        case .fullNameLiteral: return "Full Name (ID 4)"
        case .family: return "Font Family (ID 1)"
        case .style: return "Style (ID 2)"
        case .typographicFamily: return "Typographic Family (ID 16)"
        case .typographicStyle: return "Typographic Style (ID 17)"
        case .version: return "Version"
        case .description: return "Description"
        case .designer: return "Designer"
        case .trademark: return "Trademark"
        case .manufacturer: return "Manufacturer"
        case .vendorID: return "Vendor ID (OS/2)"
        case .vendor: return "Vendor"
        case .copyright: return "Copyright"
        case .license: return "License (ID 13)"
        case .licenseURL: return "License URL (ID 14)"
        case .manufacturerURL: return "Manufacturer URL (ID 11)"
        case .designerURL: return "Designer URL (ID 12)"
        case .formatDetailed: return "Format"
        case .vaultPath: return "Vault path"
        case .importDate: return "Import Date"
        case .sha256: return "SHA-256"
        }
    }

    var section: InspectorFieldSection {
        switch self {
        case .postScript, .uniqueName, .fullNameLiteral, .family, .style, .typographicFamily,
             .typographicStyle, .version, .description, .designer, .trademark, .license,
             .licenseURL, .manufacturerURL, .designerURL:
            return .nameTable
        case .manufacturer, .vendorID, .vendor, .copyright, .formatDetailed:
            return .origin
        case .vaultPath, .importDate, .sha256:
            return .file
        }
    }

    var metadataFieldKey: FontMetadataFieldKey? {
        switch self {
        case .postScript: return .psName
        case .uniqueName: return .uniqueName
        case .fullNameLiteral: return .fullName
        case .family: return .family
        case .style: return .subfamily
        case .typographicFamily: return .typographicFamily
        case .typographicStyle: return .typographicSubfamily
        case .version: return .version
        case .description: return .description
        case .designer: return .designer
        case .trademark: return .trademark
        case .manufacturer: return .manufacturer
        case .vendorID: return .vendorID
        case .copyright: return .copyright
        case .formatDetailed: return .formatDetailed
        case .vendor, .license, .licenseURL, .manufacturerURL, .designerURL,
             .vaultPath, .importDate, .sha256:
            return nil
        }
    }

    var usesMonospace: Bool {
        switch self {
        case .postScript, .uniqueName, .version, .vendorID, .vaultPath, .sha256,
             .licenseURL, .manufacturerURL, .designerURL:
            return true
        default:
            return false
        }
    }

    static let defaultVisible: [InspectorField] = [
        .postScript, .uniqueName, .fullNameLiteral, .family, .style, .typographicFamily, .typographicStyle,
        .version, .description, .designer, .trademark, .license, .licenseURL, .manufacturerURL, .designerURL,
        .manufacturer, .vendorID, .vendor, .copyright, .formatDetailed,
        .vaultPath, .importDate, .sha256,
    ]

    func value(from font: FontRecord) -> String {
        switch self {
        case .postScript: return font.psName
        case .uniqueName: return font.uniqueName
        case .fullNameLiteral: return font.nameTableFullName
        case .family: return font.family
        case .style: return font.subfamily
        case .typographicFamily: return font.typographicFamily
        case .typographicStyle: return font.typographicSubfamily
        case .version: return font.version
        case .description: return font.description
        case .designer: return font.designer
        case .trademark: return font.trademark
        case .manufacturer: return font.manufacturer
        case .vendorID: return font.vendorID
        case .vendor: return FontDisplayNames.vendorFriendlyName(for: font)
        case .copyright: return font.copyright
        case .license: return font.license
        case .licenseURL: return font.licenseURL
        case .manufacturerURL: return font.manufacturerURL
        case .designerURL: return font.designerURL
        case .formatDetailed: return font.formatDetailed
        case .vaultPath: return font.vaultPath
        case .importDate: return ImportDateDisplay.format(font.dateAdded)
        case .sha256: return font.sha256
        }
    }
}

enum InspectorFieldSection: String, CaseIterable {
    case nameTable = "Name table"
    case origin = "Origin"
    case file = "File"
}
