import Foundation
import GRDB

/// Extended metadata and metrics parsed from SFNT tables (stored as JSON in the catalog).
struct FontExtractedDetails: Codable, Sendable, Equatable, Hashable {
  var license: String = ""
  var licenseURL: String = ""
  var manufacturerURL: String = ""
  var designerURL: String = ""

  var unitsPerEm: Int?
  var typoAscender: Int?
  var typoDescender: Int?
  var typoLineGap: Int?
  var winAscent: Int?
  var winDescent: Int?
  var capHeight: Int?
  var xHeight: Int?
  var strikeoutPosition: Int?
  var strikeoutSize: Int?
  var hheaAscender: Int?
  var hheaDescender: Int?
  var hheaLineGap: Int?
  var underlinePosition: Int?
  var underlineThickness: Int?

  var glyphCount: Int?
  var weightClass: Int?
  var widthClass: Int?
  var italicAngle: Double?
  var isFixedPitch: Bool?
  var fsSelectionItalic: Bool?
  var fsSelectionBold: Bool?
  var fsSelectionRegular: Bool?
  var fsSelectionUseTypoMetrics: Bool?
  var fsType: Int?
  var fsTypeInterpreted: String = ""
  var fontRevision: Double?
  var headCreated: String = ""
  var headModified: String = ""
  var availableTables: [String] = []
  var variableAxisCount: Int?

  static let empty = FontExtractedDetails()

  var isEmpty: Bool {
    self == FontExtractedDetails.empty
  }

  /// Inspector sections (always shown when non-empty values exist).
  func inspectorSections() -> [(title: String, rows: [(label: String, value: String)])] {
    var sections: [(title: String, rows: [(label: String, value: String)])] = []

    let metricRows: [(String, String?)] = [
      ("Units per em", int(unitsPerEm)),
      ("Typo ascender", int(typoAscender)),
      ("Typo descender", int(typoDescender)),
      ("Typo line gap", int(typoLineGap)),
      ("Win ascent", int(winAscent)),
      ("Win descent", int(winDescent)),
      ("Cap height", int(capHeight)),
      ("x-height", int(xHeight)),
      ("Strikeout position", int(strikeoutPosition)),
      ("Strikeout size", int(strikeoutSize)),
      ("HHEA ascender", int(hheaAscender)),
      ("HHEA descender", int(hheaDescender)),
      ("HHEA line gap", int(hheaLineGap)),
      ("Underline position", int(underlinePosition)),
      ("Underline thickness", int(underlineThickness)),
    ]
    let metrics = metricRows.compactMap { label, value -> (String, String)? in
      guard let value else { return nil }
      return (label, value)
    }
    if !metrics.isEmpty {
      sections.append((title: "Metrics", rows: metrics))
    }

    var classification: [(String, String)] = []
    if let glyphCount { classification.append(("Glyph count", "\(glyphCount)")) }
    if let weightClass { classification.append(("Weight class", "\(weightClass)")) }
    if let widthClass { classification.append(("Width class", "\(widthClass)")) }
    if let italicAngle { classification.append(("Italic angle", String(format: "%.2f°", italicAngle))) }
    if let isFixedPitch { classification.append(("Fixed pitch", isFixedPitch ? "Yes" : "No")) }
    if fsSelectionItalic == true { classification.append(("fsSelection: Italic", "Yes")) }
    if fsSelectionBold == true { classification.append(("fsSelection: Bold", "Yes")) }
    if fsSelectionRegular == true { classification.append(("fsSelection: Regular", "Yes")) }
    if fsSelectionUseTypoMetrics == true { classification.append(("fsSelection: Use typo metrics", "Yes")) }
    if let fsType { classification.append(("fsType", "0x\(String(fsType, radix: 16, uppercase: true))")) }
    if !fsTypeInterpreted.isEmpty { classification.append(("Embedding", fsTypeInterpreted)) }
    if let fontRevision { classification.append(("Font revision", String(format: "%.3f", fontRevision))) }
    if !headCreated.isEmpty { classification.append(("Head created", headCreated)) }
    if !headModified.isEmpty { classification.append(("Head modified", headModified)) }
    if let variableAxisCount { classification.append(("Variable axes", "\(variableAxisCount)")) }
    if !classification.isEmpty {
      sections.append((title: "Classification", rows: classification))
    }

    if !availableTables.isEmpty {
      sections.append((
        title: "Tables",
        rows: [("Available tables", availableTables.sorted().joined(separator: ", "))]
      ))
    }

    return sections
  }

  private func int(_ value: Int?) -> String? {
    guard let value else { return nil }
    return "\(value)"
  }
}

// MARK: - GRDB JSON column

extension FontExtractedDetails: DatabaseValueConvertible {
  public var databaseValue: DatabaseValue {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(self),
          let json = String(data: data, encoding: .utf8) else {
      return "{}".databaseValue
    }
    return json.databaseValue
  }

  public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> FontExtractedDetails? {
    guard let json = String.fromDatabaseValue(dbValue), !json.isEmpty else {
      return .empty
    }
    guard let data = json.data(using: .utf8) else { return .empty }
    return (try? JSONDecoder().decode(FontExtractedDetails.self, from: data)) ?? .empty
  }
}
