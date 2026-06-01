import XCTest
@testable import FontVault

final class FontMetadataValidatorTests: XCTestCase {
    func testVendorIDMalformedWhenTooLongOrInvalid() {
        XCTAssertTrue(FontMetadataValidator.issues(for: "ABCDE", field: .vendorID).contains(.vendorIDMalformed))
        XCTAssertTrue(FontMetadataValidator.issues(for: "AB@C", field: .vendorID).contains(.vendorIDMalformed))
    }

    func testVendorIDTwoCharactersIsValid() {
        XCTAssertTrue(FontMetadataValidator.issues(for: "00", field: .vendorID).isEmpty)
    }

    func testPostScriptSkipsNameTableMismatch() {
        let issues = FontMetadataValidator.issues(
            for: "00_Eckmania-Variable",
            field: .psName,
            nameTable: "Different-Name",
            coreText: "00_Eckmania-Variable"
        )
        XCTAssertFalse(issues.contains(.nameTableCoreTextMismatch))
    }

    func testControlCharacterDetected() {
        let issues = FontMetadataValidator.issues(for: "Acme\u{0000}Corp", field: .manufacturer)
        XCTAssertTrue(issues.contains(.controlCharacter))
    }

    func testPlaceholderOnly() {
        let issues = FontMetadataValidator.issues(for: "Unknown", field: .family)
        XCTAssertTrue(issues.contains(.placeholderOnly))
    }

    func testNameTableMismatchNotEmitted() {
        let issues = FontMetadataValidator.issues(
            for: "Acme",
            field: .copyright,
            nameTable: "Acme",
            coreText: "ACME"
        )
        XCTAssertFalse(issues.contains(.nameTableCoreTextMismatch))
    }

    func testPostScriptFilenameMismatch() {
        let issues = FontMetadataValidator.postScriptFilenameIssues(
            psName: "ID_6_Windows",
            fileStem: "Test-Font3"
        )
        XCTAssertEqual(issues, [.postScriptNameFilenameMismatch])
    }

    func testPostScriptFilenameMismatchRenamedOnDisk() {
        let issues = FontMetadataValidator.postScriptFilenameIssues(
            psName: "AcrylicMonoTRIAL-Black",
            fileStem: "AcrylicMono-Black copy"
        )
        XCTAssertEqual(issues, [.postScriptNameFilenameMismatch])
    }

    func testPostScriptFilenameMatchesStem() {
        let url = URL(fileURLWithPath: "/tmp/00_Eckmania-Variable.ttf")
        XCTAssertTrue(
            FontMetadataValidator.postScriptFilenameIssues(
                psName: "00_Eckmania-Variable",
                fileURL: url
            ).isEmpty
        )
    }

    func testPostScriptFilenameTreatsUnderscoreAsHyphen() {
        let url = URL(fileURLWithPath: "/tmp/ABC_Honeymoon-Thin.otf")
        XCTAssertTrue(
            FontMetadataValidator.postScriptFilenameIssues(
                psName: "ABC-Honeymoon-Thin",
                fileURL: url
            ).isEmpty
        )
    }

    func testPostScriptNoLongerFlagsInvalidCharacters() {
        let issues = FontMetadataValidator.issues(for: "ID 6 Windows", field: .psName)
        XCTAssertFalse(issues.contains(.postScriptNameInvalid))
    }

    func testEmptyValueHasNoIssues() {
        XCTAssertTrue(FontMetadataValidator.issues(for: "", field: .designer).isEmpty)
    }

    func testViableVaultFolderLabel() {
        XCTAssertTrue(FontMetadataValidator.isViableVaultFolderLabel("ABC Honeymoon Thin"))
        XCTAssertTrue(FontMetadataValidator.isViableVaultFolderLabel("GhostDisplay"))
        XCTAssertFalse(FontMetadataValidator.isViableVaultFolderLabel("."))
        XCTAssertFalse(FontMetadataValidator.isViableVaultFolderLabel(".."))
        XCTAssertFalse(FontMetadataValidator.isViableVaultFolderLabel("none"))
        XCTAssertFalse(FontMetadataValidator.isViableVaultFolderLabel("Unknown"))
        XCTAssertFalse(FontMetadataValidator.isViableVaultFolderLabel("_Hidden"))
        XCTAssertFalse(FontMetadataValidator.isViableVaultFolderLabel("\u{7F}"))
    }

    func testStrippingControlCharactersForVaultLabel() {
        XCTAssertEqual(
            FontMetadataValidator.strippingControlCharactersForVaultLabel(".\u{7F}"),
            "."
        )
    }
}
