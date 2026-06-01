import XCTest
@testable import FontVault

final class FontMetadataReaderTests: XCTestCase {
    /// OS/2 version is big-endian uint16 at offset 0; version 0 uses `achVendID` at byte 36.
    private func makeOS2Table(version: UInt16 = 1, configure: (inout Data) -> Void) -> Data {
        var data = Data(count: 64)
        data[0] = UInt8(version >> 8)
        data[1] = UInt8(version & 0xFF)
        configure(&data)
        return data
    }

    private func writeVendorID(_ tag: String, at offset: Int, in data: inout Data) {
        let bytes = Array(tag.utf8)
        for (index, byte) in bytes.enumerated() {
            data[offset + index] = byte
        }
    }

    func testParseVendorIDFromOS2Table() {
        let data = makeOS2Table { data in
            writeVendorID("ADOB", at: OpenTypeOS2.vendIDOffset, in: &data)
        }
        XCTAssertEqual(FontMetadataReader.parseVendorID(fromOS2Table: data), "ADOB")
    }

    func testParseVendorIDTrimsSpaces() {
        let data = makeOS2Table { data in
            writeVendorID("1ASC", at: OpenTypeOS2.vendIDOffset, in: &data)
        }
        XCTAssertEqual(FontMetadataReader.parseVendorID(fromOS2Table: data), "1ASC")
    }

    func testParseVendorIDReturnsEmptyForShortTable() {
        XCTAssertEqual(FontMetadataReader.parseVendorID(fromOS2Table: Data(count: 10)), "")
    }

    func testParseVendorIDStripsNullBytes() {
        let data = makeOS2Table { data in
            data[OpenTypeOS2.vendIDOffset] = 0x30
            data[OpenTypeOS2.vendIDOffset + 1] = 0x30
            data[OpenTypeOS2.vendIDOffset + 2] = 0
            data[OpenTypeOS2.vendIDOffset + 3] = 0
        }
        XCTAssertEqual(FontMetadataReader.parseVendorID(fromOS2Table: data), "00")
    }

    func testParseVendorIDFromUniqueName_EckmaniaStyle() {
        XCTAssertEqual(
            FontMetadataReader.parseVendorIDFromUniqueName("1.000;00 ;00_Eckmania-Black"),
            "00"
        )
    }

    func testResolveVendorIDPrefersOS2OverUniqueName() {
        let os2 = makeOS2Table { data in
            writeVendorID("ADOB", at: OpenTypeOS2.vendIDOffset, in: &data)
        }
        XCTAssertEqual(
            FontMetadataReader.resolveVendorID(
                os2Table: os2,
                uniqueName: "1.000;00 ;00_Eckmania-Black"
            ),
            "ADOB"
        )
    }

    func testResolveVendorIDFallsBackToUniqueName() {
        XCTAssertEqual(
            FontMetadataReader.resolveVendorID(
                os2Table: makeOS2Table { _ in },
                uniqueName: "1.000;00 ;00_Eckmania-Regular"
            ),
            "00"
        )
    }

    func testParseVendorIDFindsTagAfterPaddingBytes() {
        let data = makeOS2Table { data in
            // Primary offset 56 must not yield a valid tag (0,0,1,2 would read as "12").
            data[56] = 0xFF
            data[57] = 0xFF
            data[58] = 0xFF
            data[59] = 0xFF
            writeVendorID("1234", at: 58, in: &data)
        }
        XCTAssertEqual(FontMetadataReader.parseVendorID(fromOS2Table: data), "1234")
    }

    func testParseVendorIDVersion0UsesEarlierOffset() {
        let data = makeOS2Table(version: 0) { data in
            writeVendorID("DBZR", at: OpenTypeOS2.vendIDOffsetVersion0, in: &data)
        }
        XCTAssertEqual(FontMetadataReader.parseVendorID(fromOS2Table: data), "DBZR")
    }
}
