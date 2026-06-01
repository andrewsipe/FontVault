import XCTest
@testable import FontVault

final class FontNameTableReaderTests: XCTestCase {
    func testBestNameReadsUniqueNameID3() {
        let data = makeNameTable([
            (nameID: 3, platformID: 3, encodingID: 1, languageID: 0x0409, text: "1.000;00 ;00_Eckmania-Regular"),
        ])
        XCTAssertEqual(FontNameTableReader.bestName(id: 3, in: data), "1.000;00 ;00_Eckmania-Regular")
    }

    func testBestNamePrefersWindowsEnglish() {
        let data = makeNameTable([
            (nameID: 9, platformID: 1, encodingID: 0, languageID: 0, text: "Mac Designer"),
            (nameID: 9, platformID: 3, encodingID: 1, languageID: 0x0409, text: "DOUBLE ZERO"),
        ])
        XCTAssertEqual(FontNameTableReader.bestName(id: 9, in: data), "DOUBLE ZERO")
    }

    private func makeNameTable(
        _ entries: [(nameID: UInt16, platformID: UInt16, encodingID: UInt16, languageID: UInt16, text: String)]
    ) -> Data {
        var storage = Data()
        struct BuiltRecord {
            var platformID: UInt16
            var encodingID: UInt16
            var languageID: UInt16
            var nameID: UInt16
            var length: UInt16
            var offset: UInt16
        }
        var records: [BuiltRecord] = []

        for entry in entries {
            let offset = UInt16(storage.count)
            let bytes: Data
            if entry.platformID == 3 && entry.encodingID == 1 {
                var utf16 = Data()
                for unit in entry.text.utf16 {
                    utf16.append(UInt8((unit >> 8) & 0xFF))
                    utf16.append(UInt8(unit & 0xFF))
                }
                bytes = utf16
            } else {
                bytes = Data(entry.text.utf8)
            }
            storage.append(bytes)
            records.append(BuiltRecord(
                platformID: entry.platformID,
                encodingID: entry.encodingID,
                languageID: entry.languageID,
                nameID: entry.nameID,
                length: UInt16(bytes.count),
                offset: offset
            ))
        }

        let stringOffset = UInt16(6 + records.count * 12)
        var data = Data([0, 0, UInt8(records.count >> 8), UInt8(records.count & 0xFF),
                         UInt8(stringOffset >> 8), UInt8(stringOffset & 0xFF)])

        for record in records {
            appendUInt16(&data, record.platformID)
            appendUInt16(&data, record.encodingID)
            appendUInt16(&data, record.languageID)
            appendUInt16(&data, record.nameID)
            appendUInt16(&data, record.length)
            appendUInt16(&data, record.offset)
        }
        data.append(storage)
        return data
    }

    private func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value >> 8))
        data.append(UInt8(value & 0xFF))
    }
}
