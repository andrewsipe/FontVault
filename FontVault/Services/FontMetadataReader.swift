import CoreGraphics
import CoreText
import CryptoKit
import Foundation

struct FontFileMetadata: Sendable {
    var psName: String
    /// Preferred full name (ID 4 + fallbacks) for search, sort, and display.
    var fullName: String
    /// Literal name ID 4 from the name table only.
    var nameTableFullName: String
    var family: String
    var subfamily: String
    /// Name ID 16 — Typographic family (literal; empty when absent).
    var typographicFamily: String
    /// Name ID 17 — Typographic subfamily (literal; empty when absent).
    var typographicSubfamily: String
    var license: String
    var licenseURL: String
    var manufacturerURL: String
    var designerURL: String
    var version: String
    /// Name ID 8 — Manufacturer name.
    var manufacturer: String
    /// OS/2 `achVendID` (4 characters, may be padded with spaces).
    var vendorID: String
    /// Name ID 0 — Copyright notice.
    var copyright: String
    /// Name ID 3 — Unique font identifier.
    var uniqueName: String
    /// Name ID 10 — Description.
    var description: String
    /// Name ID 9 — Designer.
    var designer: String
    /// Name ID 7 — Trademark notice.
    var trademark: String
    var isVariable: Bool
    var format: String
    /// Human-readable format (FEX “Format (detailed)”).
    var formatDetailed: String
    /// Metrics, classification, and extra name-table fields from SFNT tables.
    var extractedDetails: FontExtractedDetails
    /// Per-field validation and derivation markers for list / inspector UI.
    var metadataIssues: FontMetadataIssues

    /// Catalog / search field (manufacturer name); not used for on-disk vault layout.
    var foundry: String { manufacturer }
}

enum FontMetadataReader {
    /// Extensions Font Vault can import and index (Core Text / catalog path).
    static let importableExtensions: Set<String> = ["otf", "otc", "ttf", "ttc", "dfont", "woff", "woff2"]

    private static let fontExtensions = importableExtensions
    private static let os2TableTag = CTFontTableTag(0x4F53_2F32) // 'OS/2'

    /// `kCTFontFormatAttribute` values (Core Text, not always exported to Swift).
    private enum CTFontFormatValue {
        static let openTypePostScript: UInt = 1
        static let openTypeTrueType: UInt = 2
        static let trueType: UInt = 3
        static let postScript: UInt = 4
        static let bitmap: UInt = 5
    }

    static func isFontFile(_ url: URL) -> Bool {
        fontExtensions.contains(url.pathExtension.lowercased())
    }

    static func read(from url: URL) throws -> FontFileMetadata {
        let ext = url.pathExtension.lowercased()
        let format = FontFormat.from(pathExtension: ext).rawValue
        let fallbackName = url.deletingPathExtension().lastPathComponent

        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return emptyMetadata(fallbackName: fallbackName, format: format, ext: ext)
        }

        let font = makeCTFont(from: descriptor)
        var metadataIssues = FontMetadataIssues()

        let psName = readName(
            font: font,
            key: kCTFontPostScriptNameKey,
            nameID: OpenTypeNameID.postScript,
            field: .psName,
            issues: &metadataIssues
        )
        let family = readName(
            font: font,
            key: kCTFontFamilyNameAttribute,
            nameID: OpenTypeNameID.family,
            field: .family,
            issues: &metadataIssues,
            fallback: descriptorString(descriptor, key: kCTFontFamilyNameAttribute) ?? fallbackName
        )
        let subfamily = readName(
            font: font,
            key: kCTFontStyleNameAttribute,
            nameID: OpenTypeNameID.subfamily,
            field: .subfamily,
            issues: &metadataIssues
        )
        let nameTableFullName = literalName(
            font: font,
            nameID: OpenTypeNameID.fullName,
            field: .fullName,
            issues: &metadataIssues
        )
        let fullNameFallback = descriptorString(descriptor, key: kCTFontDisplayNameAttribute)
            ?? descriptorString(descriptor, key: kCTFontNameAttribute)
            ?? composedFullName(family: family, subfamily: subfamily, fallback: psName)
        let fullName: String
        if !nameTableFullName.isEmpty {
            fullName = nameTableFullName
            recordNameValue(
                fullName,
                field: .fullName,
                nameTable: nameTableFullName,
                coreText: fontName(font, key: kCTFontDisplayNameAttribute),
                issues: &metadataIssues
            )
        } else {
            fullName = readName(
                font: font,
                key: kCTFontDisplayNameAttribute,
                nameID: OpenTypeNameID.fullName,
                field: .fullName,
                issues: &metadataIssues,
                fallback: fullNameFallback
            )
        }

        let typographicFamily = literalName(
            font: font,
            nameID: OpenTypeNameID.typographicFamily,
            field: .typographicFamily,
            issues: &metadataIssues
        )
        let typographicSubfamily = literalName(
            font: font,
            nameID: OpenTypeNameID.typographicSubfamily,
            field: .typographicSubfamily,
            issues: &metadataIssues
        )
        let license = nameTableOnly(id: OpenTypeNameID.license, from: font)
        let licenseURL = nameTableOnly(id: OpenTypeNameID.licenseURL, from: font)
        let manufacturerURL = nameTableOnly(id: OpenTypeNameID.manufacturerURL, from: font)
        let designerURL = nameTableOnly(id: OpenTypeNameID.designerURL, from: font)

        let version = readName(
            font: font,
            key: kCTFontVersionNameKey,
            nameID: OpenTypeNameID.version,
            field: .version,
            issues: &metadataIssues
        )
        let manufacturer = readName(
            font: font,
            key: kCTFontManufacturerNameKey,
            nameID: OpenTypeNameID.manufacturer,
            field: .manufacturer,
            issues: &metadataIssues
        )
        let copyright = readName(
            font: font,
            key: kCTFontCopyrightNameKey,
            nameID: OpenTypeNameID.copyright,
            field: .copyright,
            issues: &metadataIssues
        )
        let uniqueName = readName(
            font: font,
            key: kCTFontUniqueNameKey,
            nameID: OpenTypeNameID.unique,
            field: .uniqueName,
            issues: &metadataIssues
        )
        let description = readName(
            font: font,
            key: kCTFontDescriptionNameKey,
            nameID: OpenTypeNameID.description,
            field: .description,
            issues: &metadataIssues
        )
        let designer = readName(
            font: font,
            key: kCTFontDesignerNameKey,
            nameID: OpenTypeNameID.designer,
            field: .designer,
            issues: &metadataIssues
        )
        let trademark = readName(
            font: font,
            key: kCTFontTrademarkNameKey,
            nameID: OpenTypeNameID.trademark,
            field: .trademark,
            issues: &metadataIssues
        )
        let vendorID = readVendorID(from: font, uniqueName: uniqueName, issues: &metadataIssues)

        let variationAxes = CTFontCopyVariationAxes(font) as? [Any]
        let variationAttribute = CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAttribute) as? [Any]
        let isVariable = !(variationAxes?.isEmpty ?? true) || !(variationAttribute?.isEmpty ?? true)

        let formatDetailed = formatDescription(descriptor: descriptor, extension: ext)
        if formatDetailed == formatDescription(descriptor: nil, extension: ext) {
            metadataIssues.markDerived(.formatDetailed)
        }
        recordValue(formatDetailed, field: .formatDetailed, issues: &metadataIssues)

        let extractedDetails = FontTableBinaryReader.extract(from: font, fileURL: url, isVariable: isVariable)
        mergePostScriptFilenameIssues(psName: psName, fileURL: url, issues: &metadataIssues)

        return FontFileMetadata(
            psName: psName,
            fullName: fullName,
            nameTableFullName: nameTableFullName,
            family: family,
            subfamily: subfamily,
            typographicFamily: typographicFamily,
            typographicSubfamily: typographicSubfamily,
            license: license,
            licenseURL: licenseURL,
            manufacturerURL: manufacturerURL,
            designerURL: designerURL,
            version: version,
            manufacturer: manufacturer,
            vendorID: vendorID,
            copyright: copyright,
            uniqueName: uniqueName,
            description: description,
            designer: designer,
            trademark: trademark,
            isVariable: isVariable,
            format: format,
            formatDetailed: formatDetailed,
            extractedDetails: extractedDetails,
            metadataIssues: metadataIssues
        )
    }

    static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Parses OS/2 `achVendID` using table version and a short forward scan for misaligned tags.
    static func parseVendorID(fromOS2Table data: Data) -> String {
        guard data.count >= OpenTypeOS2.vendIDLength else { return "" }
        let version = Int(readUInt16(data, 0))
        let primaryOffset = version == 0 ? OpenTypeOS2.vendIDOffsetVersion0 : OpenTypeOS2.vendIDOffset
        if let tag = vendorTag(at: primaryOffset, in: data) { return tag }
        if version > 0, data.count >= OpenTypeOS2.vendIDOffset + OpenTypeOS2.vendIDLength + 2 {
            for offset in OpenTypeOS2.vendIDOffset...(OpenTypeOS2.vendIDOffset + 2) {
                if let tag = vendorTag(at: offset, in: data) { return tag }
            }
        }
        return ""
    }

    private static func vendorTag(at offset: Int, in data: Data) -> String? {
        guard offset + OpenTypeOS2.vendIDLength <= data.count else { return nil }
        let slice = data[offset..<(offset + OpenTypeOS2.vendIDLength)]
        let raw = String(bytes: slice, encoding: .ascii) ?? ""
        let sanitized = sanitizeVendorID(raw)
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    /// Adobe-style unique name (name ID 3): `version;vendorID;uniqueSuffix` — used when OS/2 is blank.
    static func parseVendorIDFromUniqueName(_ uniqueName: String) -> String {
        let trimmed = uniqueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let parts = trimmed.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return "" }
        return sanitizeVendorID(String(parts[1]))
    }

    /// Prefer OS/2 `achVendID`; fall back to the vendor field embedded in name ID 3.
    static func resolveVendorID(os2Table: Data?, uniqueName: String) -> String {
        if let os2Table, !os2Table.isEmpty {
            let fromOS2 = parseVendorID(fromOS2Table: os2Table)
            if !fromOS2.isEmpty { return fromOS2 }
        }
        return parseVendorIDFromUniqueName(uniqueName)
    }

    static func sanitizeVendorID(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty, stripped.count <= OpenTypeOS2.vendIDLength else { return "" }
        let allowed = CharacterSet.alphanumerics
        guard stripped.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else { return "" }
        return stripped
    }

    private static func readVendorID(
        from font: CTFont,
        uniqueName: String,
        issues: inout FontMetadataIssues
    ) -> String {
        let table = CTFontCopyTable(font, os2TableTag, []) as Data?
        let resolved = resolveVendorID(os2Table: table, uniqueName: uniqueName)
        issues.setIssues(FontMetadataValidator.issues(for: resolved, field: .vendorID), for: .vendorID)
        return resolved
    }

    private static func emptyMetadata(fallbackName: String, format: String, ext: String) -> FontFileMetadata {
        FontFileMetadata(
            psName: fallbackName,
            fullName: fallbackName,
            nameTableFullName: "",
            family: fallbackName,
            subfamily: "",
            typographicFamily: "",
            typographicSubfamily: "",
            license: "",
            licenseURL: "",
            manufacturerURL: "",
            designerURL: "",
            version: "",
            manufacturer: "",
            vendorID: "",
            copyright: "",
            uniqueName: "",
            description: "",
            designer: "",
            trademark: "",
            isVariable: false,
            format: format,
            formatDetailed: formatDescription(descriptor: nil, extension: ext),
            extractedDetails: .empty,
            metadataIssues: .empty
        )
    }

    private static func makeCTFont(from descriptor: CTFontDescriptor) -> CTFont {
        CTFontCreateWithFontDescriptor(descriptor, 12.0, nil)
    }

    private static func descriptorString(_ descriptor: CTFontDescriptor, key: CFString) -> String? {
        guard let value = CTFontDescriptorCopyAttribute(descriptor, key) else { return nil }
        return value as? String
    }

    private static func fontName(_ font: CTFont, key: CFString) -> String? {
        CTFontCopyName(font, key) as String?
    }

    private static func readName(
        font: CTFont,
        key: CFString,
        nameID: Int,
        field: FontMetadataFieldKey,
        issues: inout FontMetadataIssues,
        fallback: String? = nil
    ) -> String {
        let fromTable = FontNameTableReader.name(id: nameID, from: font)
        let fromCoreText = fontName(font, key: key)
        let value: String
        if let fromTable, !fromTable.isEmpty {
            value = fromTable
        } else if let fromCoreText, !fromCoreText.isEmpty {
            value = fromCoreText
        } else {
            value = fallback ?? ""
        }
        recordNameValue(
            value,
            field: field,
            nameTable: fromTable,
            coreText: fromCoreText,
            issues: &issues
        )
        return value
    }

    private static func literalName(
        font: CTFont,
        nameID: Int,
        field: FontMetadataFieldKey,
        issues: inout FontMetadataIssues
    ) -> String {
        let fromTable = FontNameTableReader.name(id: nameID, from: font)
        let value = fromTable ?? ""
        recordNameValue(
            value,
            field: field,
            nameTable: fromTable,
            coreText: nil,
            issues: &issues
        )
        return value
    }

    private static func nameTableOnly(id: Int, from font: CTFont) -> String {
        FontNameTableReader.name(id: id, from: font) ?? ""
    }

    private static func mergePostScriptFilenameIssues(
        psName: String,
        fileURL: URL,
        issues: inout FontMetadataIssues
    ) {
        var merged = issues.issues(for: .psName).filter {
            $0 != .postScriptNameInvalid && $0 != .postScriptNameFilenameMismatch
        }
        merged.append(contentsOf: FontMetadataValidator.postScriptFilenameIssues(psName: psName, fileURL: fileURL))
        issues.setIssues(
            Array(Set(merged)).sorted { $0.rawValue < $1.rawValue },
            for: .psName
        )
    }

    private static func recordNameValue(
        _ value: String,
        field: FontMetadataFieldKey,
        nameTable: String?,
        coreText: String?,
        issues: inout FontMetadataIssues,
        extraDerived: FontFieldDerivedSource? = nil
    ) {
        let fieldIssues = FontMetadataValidator.issues(
            for: value,
            field: field,
            nameTable: nameTable,
            coreText: coreText
        )
        issues.setIssues(fieldIssues, for: field)
        if extraDerived != nil {
            issues.markDerived(field)
        }
    }

    private static func recordValue(
        _ value: String,
        field: FontMetadataFieldKey,
        issues: inout FontMetadataIssues
    ) {
        issues.setIssues(FontMetadataValidator.issues(for: value, field: field), for: field)
    }

    private static func formatDescription(descriptor: CTFontDescriptor?, extension ext: String) -> String {
        if let descriptor,
           let raw = CTFontDescriptorCopyAttribute(descriptor, kCTFontFormatAttribute) {
            let value = (raw as? NSNumber)?.uintValue ?? (raw as? UInt)
            if let value {
                switch value {
                case CTFontFormatValue.openTypePostScript:
                    return "OpenType (PostScript Flavored)"
                case CTFontFormatValue.openTypeTrueType:
                    return "OpenType (TrueType Flavored)"
                case CTFontFormatValue.trueType:
                    return "TrueType"
                case CTFontFormatValue.postScript:
                    return "PostScript"
                case CTFontFormatValue.bitmap:
                    return "Bitmap"
                default:
                    break
                }
            }
        }
        switch ext.lowercased() {
        case "otf": return "OpenType"
        case "ttf": return "TrueType"
        case "ttc", "otc": return "TrueType Collection"
        case "woff": return "WOFF"
        case "woff2": return "WOFF2"
        default: return ext.uppercased()
        }
    }

    private static func composedFullName(family: String, subfamily: String, fallback: String) -> String {
        if subfamily.isEmpty || subfamily.caseInsensitiveCompare("regular") == .orderedSame {
            return family.isEmpty ? fallback : family
        }
        if family.isEmpty { return subfamily }
        return "\(family) \(subfamily)"
    }
}

// MARK: - OpenType `name` table (by name ID)

enum FontNameTableReader {
    private static let nameTableTag = CTFontTableTag(0x6E616D65) // 'name'

    static func name(id: Int, from font: CTFont) -> String? {
        guard let data = CTFontCopyTable(font, nameTableTag, []) as Data? else { return nil }
        return bestName(id: id, in: data)
    }

    static func bestName(id: Int, in data: Data) -> String? {
        let records = parseRecords(data).filter { $0.nameID == id }
        guard !records.isEmpty, data.count >= 6 else { return nil }

        let stringOffset = Int(readUInt16(data, 4))
        let sorted = records.sorted { preferenceScore($0) < preferenceScore($1) }
        for record in sorted {
            if let value = decode(record: record, in: data, stringOffset: stringOffset), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private struct NameRecord {
        var platformID: UInt16
        var encodingID: UInt16
        var languageID: UInt16
        var nameID: UInt16
        var length: UInt16
        var offset: UInt16
    }

    private static func parseRecords(_ data: Data) -> [NameRecord] {
        guard data.count >= 6 else { return [] }
        let count = Int(readUInt16(data, 2))
        guard count > 0 else { return [] }

        var records: [NameRecord] = []
        var pos = 6
        for _ in 0..<count {
            guard pos + 12 <= data.count else { break }
            records.append(NameRecord(
                platformID: readUInt16(data, pos),
                encodingID: readUInt16(data, pos + 2),
                languageID: readUInt16(data, pos + 4),
                nameID: readUInt16(data, pos + 6),
                length: readUInt16(data, pos + 8),
                offset: readUInt16(data, pos + 10)
            ))
            pos += 12
        }
        return records
    }

    private static func decode(record: NameRecord, in data: Data, stringOffset: Int) -> String? {
        let start = stringOffset + Int(record.offset)
        let length = Int(record.length)
        guard start >= 0, length > 0, start + length <= data.count else { return nil }
        let slice = data[start..<(start + length)]

        switch (record.platformID, record.encodingID) {
        case (3, 1), (3, 10), (0, 3):
            return decodeUTF16BE(slice)
        case (1, 0), (1, 25):
            return String(bytes: slice, encoding: .macOSRoman)
        case (3, 0):
            return String(bytes: slice, encoding: .windowsCP1252)
        default:
            return decodeUTF16BE(slice) ?? String(bytes: slice, encoding: .macOSRoman)
        }
    }

    private static func decodeUTF16BE(_ slice: Data.SubSequence) -> String? {
        guard !slice.isEmpty, slice.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(slice.count)
        for byte in slice { bytes.append(byte) }
        return String(data: Data(bytes), encoding: .utf16BigEndian)
    }

    private static func preferenceScore(_ record: NameRecord) -> Int {
        if record.platformID == 3 {
            if record.languageID == 0x0409 { return 0 }
            if record.languageID == 0 { return 1 }
            return 2
        }
        if record.platformID == 1 {
            if record.languageID == 0 { return 3 }
            return 4
        }
        return 10
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
}
