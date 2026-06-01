import XCTest
@testable import FontVault

final class FontTableBinaryReaderTests: XCTestCase {
    func testInterpretFsTypeInstallable() {
        XCTAssertEqual(FontTableBinaryReader.interpretFsType(0), "Installable")
    }

    func testInterpretFsTypeRestricted() {
        XCTAssertEqual(FontTableBinaryReader.interpretFsType(0x0002), "Restricted")
    }

    func testParseOS2WeightAndFsSelection() {
        var data = Data(count: 90)
        data[4] = 0x03
        data[5] = 0xE8 // weight 1000
        data[6] = 0x00
        data[7] = 0x05 // width 5
        data[62] = 0x00
        data[63] = 0x21 // italic + bold bits

        var details = FontExtractedDetails()
        FontTableBinaryReader.Testing.applyOS2Table(data, to: &details)

        XCTAssertEqual(details.weightClass, 1000)
        XCTAssertEqual(details.widthClass, 5)
        XCTAssertEqual(details.fsSelectionItalic, true)
        XCTAssertEqual(details.fsSelectionBold, true)
    }

    func testParseSFNTTableDirectoryTags() {
        var data = Data(count: 12 + 16 * 2)
        data[4] = 0
        data[5] = 2 // numTables
        let head = Array("head".utf8)
        let os2 = Array("OS/2".utf8)
        for (index, byte) in head.enumerated() { data[12 + index] = byte }
        for (index, byte) in os2.enumerated() { data[12 + 16 + index] = byte }

        let tags = FontTableBinaryReader.Testing.parseTableTags(from: data)
        XCTAssertEqual(tags, ["head", "OS/2"])
    }

    func testParseMaxpGlyphCount() {
        var data = Data(count: 6)
        data[4] = 0x04
        data[5] = 0xD2 // 1234 glyphs

        var details = FontExtractedDetails()
        FontTableBinaryReader.Testing.applyMaxpTable(data, to: &details)
        XCTAssertEqual(details.glyphCount, 1234)
    }
}
