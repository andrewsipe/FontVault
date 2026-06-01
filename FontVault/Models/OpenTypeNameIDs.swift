import Foundation

/// OpenType `name` table name IDs (Microsoft spec).
/// https://learn.microsoft.com/en-us/typography/opentype/spec/name#name-ids
enum OpenTypeNameID {
    static let copyright = 0
    static let family = 1
    static let subfamily = 2
    static let unique = 3
    static let fullName = 4
    static let version = 5
    static let postScript = 6
    static let trademark = 7
    static let manufacturer = 8
    static let designer = 9
    static let description = 10
    static let manufacturerURL = 11
    static let designerURL = 12
    static let license = 13
    static let licenseURL = 14
    static let typographicFamily = 16
    static let typographicSubfamily = 17
}

/// OS/2 `achVendID` — four-byte registered vendor ID.
/// https://learn.microsoft.com/en-us/typography/opentype/spec/os2#achvendid
/// Registry: https://learn.microsoft.com/en-us/typography/vendors/
enum OpenTypeOS2 {
    static let vendIDLength = 4
    /// `achVendID` offset for OS/2 version 1 and later.
    static let vendIDOffset = 56
    /// `achVendID` offset for OS/2 version 0.
    static let vendIDOffsetVersion0 = 36
}
