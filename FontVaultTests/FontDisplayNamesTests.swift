import XCTest
@testable import FontVault

final class FontDisplayNamesTests: XCTestCase {
    func testPreferredFamilyUsesTypographicWhenPresent() {
        XCTAssertEqual(
            FontDisplayNames.preferredFamily(typographicFamily: "ID 16 Windows", family: "ID 1 Windows"),
            "ID 16 Windows"
        )
    }

    func testPreferredFamilyFallsBackToFamily() {
        XCTAssertEqual(
            FontDisplayNames.preferredFamily(typographicFamily: "", family: "ID 1 Windows"),
            "ID 1 Windows"
        )
    }

    func testVendorFriendlyNameRegistry() {
        let tag = "1ASC"
        let expected = FontVendorRegistry.registeredName(forVendorID: tag) ?? "Unknown"
        XCTAssertEqual(FontDisplayNames.vendorFriendlyName(forVendorID: tag), expected)
    }

    func testVendorFriendlyNameUnknownWhenUnregistered() {
        XCTAssertEqual(FontDisplayNames.vendorFriendlyName(forVendorID: "1234"), "Unknown")
    }

    func testVendorFriendlyNameEmptyWhenNoTag() {
        XCTAssertEqual(FontDisplayNames.vendorFriendlyName(forVendorID: ""), "")
    }
}
