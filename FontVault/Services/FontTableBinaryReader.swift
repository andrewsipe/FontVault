import CoreText
import Foundation

/// Parses SFNT table bytes for catalog metrics and classification (no glyph outlines).
enum FontTableBinaryReader {
  private static let headTag = CTFontTableTag(0x68656164) // 'head'
  private static let hheaTag = CTFontTableTag(0x68686561) // 'hhea'
  private static let os2Tag = CTFontTableTag(0x4F53_2F32) // 'OS/2'
  private static let postTag = CTFontTableTag(0x706F7374) // 'post'
  private static let maxpTag = CTFontTableTag(0x6D617870) // 'maxp'

  static func extract(from font: CTFont, fileURL: URL, isVariable: Bool) -> FontExtractedDetails {
    var details = FontExtractedDetails()

    if let head = copyTable(font, tag: headTag) {
      applyHead(head, to: &details)
    }
    if let hhea = copyTable(font, tag: hheaTag) {
      applyHhea(hhea, to: &details)
    }
    if let os2 = copyTable(font, tag: os2Tag) {
      applyOS2(os2, to: &details)
    }
    if let post = copyTable(font, tag: postTag) {
      applyPost(post, to: &details)
    }
    if let maxp = copyTable(font, tag: maxpTag) {
      applyMaxp(maxp, to: &details)
    }

    details.availableTables = availableTableTags(fileURL: fileURL)
    if isVariable {
      details.variableAxisCount = variationAxisCount(from: font)
    }

    return details
  }

  // MARK: - head

  private static func applyHead(_ data: Data, to details: inout FontExtractedDetails) {
    guard data.count >= 18 else { return }
    let revisionFixed = readInt32(data, 4)
    details.fontRevision = Double(revisionFixed) / 65536.0
    details.unitsPerEm = Int(readUInt16(data, 18))
    if data.count >= 28 {
      details.headCreated = formatLongDateTime(readUInt32(data, 20), readUInt32(data, 24))
    }
    if data.count >= 36 {
      details.headModified = formatLongDateTime(readUInt32(data, 28), readUInt32(data, 32))
    }
    // head v1+ underline fields at 46/48 when present
    if data.count >= 50 {
      if details.underlinePosition == nil {
        details.underlinePosition = Int(readInt16(data, 46))
      }
      if details.underlineThickness == nil {
        details.underlineThickness = Int(readUInt16(data, 48))
      }
    }
  }

  // MARK: - hhea

  private static func applyHhea(_ data: Data, to details: inout FontExtractedDetails) {
    guard data.count >= 10 else { return }
    details.hheaAscender = Int(readInt16(data, 4))
    details.hheaDescender = Int(readInt16(data, 6))
    details.hheaLineGap = Int(readInt16(data, 8))
  }

  // MARK: - OS/2

  private static func applyOS2(_ data: Data, to details: inout FontExtractedDetails) {
    guard data.count >= 10 else { return }
    details.weightClass = Int(readUInt16(data, 4))
    details.widthClass = Int(readUInt16(data, 6))
    let fsType = Int(readUInt16(data, 8))
    details.fsType = fsType
    details.fsTypeInterpreted = interpretFsType(fsType)

    if data.count >= 30 {
      details.strikeoutSize = Int(readInt16(data, 26))
      details.strikeoutPosition = Int(readInt16(data, 28))
    }
    if data.count >= 64 {
      let fsSelection = readUInt16(data, 62)
      details.fsSelectionItalic = (fsSelection & 0x0001) != 0
      details.fsSelectionBold = (fsSelection & 0x0020) != 0
      details.fsSelectionRegular = (fsSelection & 0x0040) != 0
      details.fsSelectionUseTypoMetrics = (fsSelection & 0x0080) != 0
    }
    if data.count >= 78 {
      details.typoAscender = Int(readInt16(data, 68))
      details.typoDescender = Int(readInt16(data, 70))
      details.typoLineGap = Int(readInt16(data, 72))
      details.winAscent = Int(readUInt16(data, 74))
      details.winDescent = Int(readUInt16(data, 76))
    }
    // OS/2 version 2+ cap/x height
    if data.count >= 90 {
      details.xHeight = Int(readInt16(data, 86))
      details.capHeight = Int(readInt16(data, 88))
    }
  }

  // MARK: - post

  private static func applyPost(_ data: Data, to details: inout FontExtractedDetails) {
    guard data.count >= 32 else { return }
    let angleFixed = readInt32(data, 4)
    details.italicAngle = Double(angleFixed) / 65536.0
    details.underlinePosition = Int(readInt16(data, 8))
    details.underlineThickness = Int(readUInt16(data, 10))
    details.isFixedPitch = readInt32(data, 12) != 0
  }

  // MARK: - maxp

  private static func applyMaxp(_ data: Data, to details: inout FontExtractedDetails) {
    guard data.count >= 6 else { return }
    details.glyphCount = Int(readUInt16(data, 4))
  }

  // MARK: - Helpers

  private static func copyTable(_ font: CTFont, tag: CTFontTableTag) -> Data? {
    CTFontCopyTable(font, tag, []) as Data?
  }

  /// Reads the SFNT / WOFF table directory from the file (avoids `CTFontCopyAvailableTables`, which can crash).
  private static func availableTableTags(fileURL: URL) -> [String] {
    let readLength = 44 + maxTableDirectoryEntries * 20
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: readLength), !data.isEmpty else { return [] }
    return parseTableTags(from: data)
  }

  private static let maxTableDirectoryEntries = 128

  private static func parseTableTags(from data: Data) -> [String] {
    guard data.count >= 12 else { return [] }
    switch readUInt32(data, 0) {
    case 0x774F_4646: // 'wOFF'
      return parseWOFFTableTags(data)
    case 0x774F_4632: // 'wOF2' — directory layout differs; skip listing for now
      return []
    case 0x7474_6366: // 'ttcf' collection — offsets vary per face
      return []
    default:
      return parseSFNTTableTags(data)
    }
  }

  private static func parseSFNTTableTags(_ data: Data) -> [String] {
    let numTables = Int(readUInt16(data, 4))
    guard numTables > 0, numTables <= maxTableDirectoryEntries else { return [] }
    let directoryEnd = 12 + numTables * 16
    guard data.count >= directoryEnd else { return [] }
    var tags: [String] = []
    tags.reserveCapacity(numTables)
    for index in 0..<numTables {
      let entryOffset = 12 + index * 16
      if let tag = tagStringFromBytes(data, offset: entryOffset) {
        tags.append(tag)
      }
    }
    return tags
  }

  private static func parseWOFFTableTags(_ data: Data) -> [String] {
    guard data.count >= 44 else { return [] }
    let numTables = Int(readUInt16(data, 12))
    guard numTables > 0, numTables <= maxTableDirectoryEntries else { return [] }
    let directoryEnd = 44 + numTables * 20
    guard data.count >= directoryEnd else { return [] }
    var tags: [String] = []
    tags.reserveCapacity(numTables)
    for index in 0..<numTables {
      let entryOffset = 44 + index * 20
      if let tag = tagStringFromBytes(data, offset: entryOffset) {
        tags.append(tag)
      }
    }
    return tags
  }

  private static func tagStringFromBytes(_ data: Data, offset: Int) -> String? {
    guard offset + 4 <= data.count else { return nil }
    let bytes: [UInt8] = [
      data[offset],
      data[offset + 1],
      data[offset + 2],
      data[offset + 3],
    ]
    guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
    return String(bytes: bytes, encoding: .ascii)
  }

  private static func variationAxisCount(from font: CTFont) -> Int? {
    guard let axes = CTFontCopyVariationAxes(font) else { return nil }
    let count = CFArrayGetCount(axes)
    return count > 0 ? count : nil
  }

  static func interpretFsType(_ fsType: Int) -> String {
    if fsType == 0 { return "Installable" }
    var parts: [String] = []
    if fsType & 0x0002 != 0 { parts.append("Restricted") }
    if fsType & 0x0004 != 0 { parts.append("Preview & Print") }
    if fsType & 0x0008 != 0 { parts.append("Editable") }
    if fsType & 0x0100 != 0 { parts.append("No subsetting") }
    if fsType & 0x0200 != 0 { parts.append("Bitmap only") }
    return parts.isEmpty ? "Installable" : parts.joined(separator: ", ")
  }

  /// Mac LONGDATETIME (seconds since 1904-01-01 00:00:00 UTC).
  private static func formatLongDateTime(_ high: UInt32, _ low: UInt32) -> String {
    let seconds = (UInt64(high) << 32) | UInt64(low)
    guard seconds > 0 else { return "" }
    let macEpoch: TimeInterval = -2_085_984_000 // 1904 → 1970 offset
    let unix = TimeInterval(seconds) + macEpoch
    let date = Date(timeIntervalSince1970: unix)
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    guard offset + 2 <= data.count else { return 0 }
    return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
  }

  private static func readInt16(_ data: Data, _ offset: Int) -> Int16 {
    Int16(bitPattern: readUInt16(data, offset))
  }

  private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    guard offset + 4 <= data.count else { return 0 }
    return UInt32(data[offset]) << 24
      | UInt32(data[offset + 1]) << 16
      | UInt32(data[offset + 2]) << 8
      | UInt32(data[offset + 3])
  }

  private static func readInt32(_ data: Data, _ offset: Int) -> Int32 {
    Int32(bitPattern: readUInt32(data, offset))
  }
}

#if DEBUG
extension FontTableBinaryReader {
  enum Testing {
    static func applyOS2Table(_ data: Data, to details: inout FontExtractedDetails) {
      applyOS2(data, to: &details)
    }

    static func applyMaxpTable(_ data: Data, to details: inout FontExtractedDetails) {
      applyMaxp(data, to: &details)
    }

    static func parseTableTags(from data: Data) -> [String] {
      FontTableBinaryReader.parseTableTags(from: data)
    }
  }
}
#endif
