import XCTest
@testable import FontVault

final class ImportFormatOptionsTests: XCTestCase {
    func testAllowsOnlyImportableExtensions() {
        let formats = ImportFormatOptions(openType: true, trueType: true, webFonts: true)
        XCTAssertTrue(formats.allows(url: URL(fileURLWithPath: "/a/font.otf")))
        XCTAssertTrue(formats.allows(url: URL(fileURLWithPath: "/a/font.woff2")))
        XCTAssertFalse(formats.allows(url: URL(fileURLWithPath: "/a/font.pfb")))
        XCTAssertFalse(formats.allows(url: URL(fileURLWithPath: "/a/font.eot")))
        XCTAssertFalse(formats.allows(url: URL(fileURLWithPath: "/a/font.svg")))
    }

    func testPostScriptExtensionNotOffered() {
        var formats = ImportFormatOptions()
        formats.selectAll()
        let url = URL(fileURLWithPath: "/legacy/Type1.pfb")
        XCTAssertFalse(formats.allows(url: url))
    }

    func testEnabledExtensionsFollowCheckboxes() {
        let desktop = ImportFormatOptions(openType: true, trueType: true, webFonts: false)
        XCTAssertTrue(desktop.enabledExtensions().contains("otf"))
        XCTAssertTrue(desktop.enabledExtensions().contains("ttf"))
        XCTAssertFalse(desktop.enabledExtensions().contains("woff2"))

        var webOnly = ImportFormatOptions()
        webOnly.selectNone()
        webOnly.webFonts = true
        XCTAssertEqual(webOnly.enabledExtensions(), Set(["woff", "woff2"]))
    }

    func testAllowedContentTypesMatchEnabledExtensions() {
        let formats = ImportFormatOptions(openType: true, trueType: false, webFonts: false)
        let types = formats.allowedContentTypes()
        XCTAssertFalse(types.isEmpty)
        XCTAssertTrue(
            types.contains { $0.preferredFilenameExtension == "otf" || $0.conforms(to: .font) }
        )
    }
}

final class ImportResultSummaryTests: XCTestCase {
    func testSummaryIncludesIgnoredFormatFiles() {
        var result = ImportResult()
        result.imported = 2
        result.scanned = 2
        result.ignoredUnsupportedFormat = 1
        result.ignoredFilteredFormat = 2
        let text = ImportResult.summaryText(for: result, move: false)
        XCTAssertTrue(text.contains("3 files ignored"))
    }
}
