import XCTest
@testable import FontVault

final class LayoutEngineTests: XCTestCase {
    func testFexBucketLetters() {
        let engine = LayoutEngine(vaultRoot: URL(fileURLWithPath: "/tmp/vault"))
        XCTAssertEqual(engine.fexBucket(for: "Helvetica"), "H")
        XCTAssertEqual(engine.fexBucket(for: "2nd Dance Floor"), "OTHER")
        XCTAssertEqual(engine.fexBucket(for: ""), "OTHER")
    }

    func testResolveVaultFolderLabelUsesFullName() {
        let engine = LayoutEngine(vaultRoot: URL(fileURLWithPath: "/tmp/vault"))
        let thin = engine.resolveVaultFolderLabel(
            fullName: "ABC Honeymoon Thin",
            fileName: "ABC_Honeymoon-Thin.otf"
        )
        XCTAssertEqual(thin.label, "ABC Honeymoon Thin")
        XCTAssertFalse(thin.usedFilenameFallback)

        let bold = engine.resolveVaultFolderLabel(
            fullName: "ABC Honeymoon Bold",
            fileName: "ABC_Honeymoon-Bold.otf"
        )
        XCTAssertEqual(bold.label, "ABC Honeymoon Bold")
        XCTAssertFalse(bold.usedFilenameFallback)
    }

    func testResolveVaultFolderLabelGhostDisplayFallback() {
        let engine = LayoutEngine(vaultRoot: URL(fileURLWithPath: "/tmp/vault"))
        let resolved = engine.resolveVaultFolderLabel(
            fullName: ".\u{7F}",
            fileName: "GhostDisplay.woff2"
        )
        XCTAssertEqual(resolved.label, "GhostDisplay")
        XCTAssertTrue(resolved.usedFilenameFallback)
    }

    func testFexBucketUsesFolderLabel() {
        let engine = LayoutEngine(vaultRoot: URL(fileURLWithPath: "/tmp/vault"))
        XCTAssertEqual(engine.fexBucket(for: "00 Eckmania Variable Thin"), "OTHER")
        XCTAssertEqual(engine.fexBucket(for: "ABC Honeymoon Thin"), "A")
    }

    func testCanonicalDestinationDoesNotAddFolderSuffix() {
        let root = URL(fileURLWithPath: "/tmp/vault")
        let engine = LayoutEngine(vaultRoot: root)
        let bucketDir = root.appendingPathComponent("G")
        try? FileManager.default.createDirectory(at: bucketDir.appendingPathComponent("Gotham Medium"), withIntermediateDirectories: true)

        let path = engine.canonicalRelativeDestination(
            folderLabel: "Gotham Medium",
            fileName: "Gotham-Medium.otf",
            foundry: ""
        )
        XCTAssertEqual(path, "G/Gotham Medium/Gotham-Medium.otf")
    }

    func testCanonicalDestinationABCHoneymoonThin() {
        let engine = LayoutEngine(vaultRoot: URL(fileURLWithPath: "/tmp/vault"))
        let path = engine.canonicalRelativeDestination(
            folderLabel: "ABC Honeymoon Thin",
            fileName: "ABC_Honeymoon-Thin.otf",
            foundry: ""
        )
        XCTAssertEqual(path, "A/ABC Honeymoon Thin/ABC_Honeymoon-Thin.otf")
    }

    func testIsAlreadyCanonical() {
        let engine = LayoutEngine(vaultRoot: URL(fileURLWithPath: "/tmp/vault"))
        XCTAssertTrue(engine.isAlreadyCanonical(
            relativePath: "G/Gotham Medium/Gotham-Medium.otf",
            folderLabel: "Gotham Medium",
            foundry: ""
        ))
        XCTAssertFalse(engine.isAlreadyCanonical(
            relativePath: "G/Gotham Medium 2/Gotham-Medium.otf",
            folderLabel: "Gotham Medium",
            foundry: ""
        ))
        XCTAssertFalse(engine.isAlreadyCanonical(
            relativePath: "A/ABC Honeymoon Bold Italic/ABC_Honeymoon-Bold.otf",
            folderLabel: "ABC Honeymoon Bold",
            foundry: ""
        ))
    }

    func testImportSummaryIncludesVaultFolderFallback() {
        var result = ImportResult()
        result.imported = 2
        result.scanned = 2
        result.vaultFolderFallbackCount = 1
        let line = ImportResult.summaryText(for: result, move: false)
        XCTAssertTrue(line.contains("1 used filename for vault folder"))
    }

    func testUniqueFolderSuffix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bucket = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: bucket.appendingPathComponent("Aero Bold"), withIntermediateDirectories: true)

        let engine = LayoutEngine(vaultRoot: root)
        let name = engine.uniqueFolderName(base: "Aero Bold", under: bucket)
        XCTAssertEqual(name, "Aero Bold 2")
    }

    func testPruneEmptyDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let styleDir = root.appendingPathComponent("A/Aero Bold")
        try FileManager.default.createDirectory(at: styleDir, withIntermediateDirectories: true)
        let font = styleDir.appendingPathComponent("Aero-Bold.otf")
        try Data("x".utf8).write(to: font)
        try FileManager.default.removeItem(at: font)

        VaultMaintenance.pruneEmptyDirectories(from: styleDir, stopBefore: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: styleDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("A").path))
    }

    func testPruneAfterMoveImport() throws {
        let downloads = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fontPack = downloads.appendingPathComponent("FontPack")
        let styleDir = fontPack.appendingPathComponent("Aero Bold")
        try FileManager.default.createDirectory(at: styleDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: downloads) }

        let font = styleDir.appendingPathComponent("Aero-Bold.otf")
        try Data("x".utf8).write(to: font)

        // Simulate move: file gone, empty folders remain.
        try FileManager.default.removeItem(at: font)

        VaultMaintenance.pruneAfterMovingFiles(sources: [font], importRoots: [fontPack])

        XCTAssertFalse(FileManager.default.fileExists(atPath: styleDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fontPack.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.path))
    }

    func testImportStopBeforeForSingleFile() {
        let file = URL(fileURLWithPath: "/Users/me/Downloads/font.otf")
        let stop = VaultMaintenance.importStopBefore(for: file, importRoots: [file])
        XCTAssertEqual(stop.path, "/Users/me/Downloads")
    }

    func testOrphanScanFindsFilesNotInCatalog() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let catalogPath = root.appendingPathComponent("A/Aero/Aero.otf")
        try FileManager.default.createDirectory(at: catalogPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: catalogPath)

        let orphanPath = root.appendingPathComponent("B/Orphan.otf")
        try FileManager.default.createDirectory(at: orphanPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("b".utf8).write(to: orphanPath)

        let scan = VaultMaintenance.scanVaultIntegrity(
            vaultRoot: root,
            catalogPaths: ["A/Aero/Aero.otf"]
        )

        XCTAssertEqual(scan.orphanFiles.count, 1)
        XCTAssertEqual(scan.orphanFiles.first?.lastPathComponent, "Orphan.otf")
        XCTAssertTrue(scan.missingCatalogPaths.isEmpty)
    }

    func testOrphanScanDetectsMissingCatalogFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let scan = VaultMaintenance.scanVaultIntegrity(
            vaultRoot: root,
            catalogPaths: ["A/Missing.otf"]
        )

        XCTAssertTrue(scan.orphanFiles.isEmpty)
        XCTAssertEqual(scan.missingCatalogPaths, ["A/Missing.otf"])
    }

    func testPruneAllEmptyDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let emptyStyle = root.appendingPathComponent("T/Taurus Grotesk Medium Italic")
        try FileManager.default.createDirectory(at: emptyStyle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let removed = VaultMaintenance.pruneAllEmptyDirectories(vaultRoot: root)
        XCTAssertGreaterThan(removed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyStyle.path))
    }
}
