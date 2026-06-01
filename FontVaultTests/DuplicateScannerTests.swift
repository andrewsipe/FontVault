import XCTest
@testable import FontVault

final class DuplicateScannerTests: XCTestCase {
    func testFindGroupsBySHA256() {
        let fonts = [
            sample(path: "A/a.otf", hash: "same", name: "Aero"),
            sample(path: "B/b.otf", hash: "same", name: "Aero Copy"),
            sample(path: "C/c.otf", hash: "other", name: "Helvetica"),
        ]

        let groups = DuplicateScanner.findGroups(in: fonts)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].copyCount, 2)
        XCTAssertEqual(groups[0].sha256, "same")
    }

    func testDefaultKeeperPrefersEarliestImport() {
        let older = sample(path: "B/b.otf", hash: "x", name: "B", dateAdded: 100)
        let newer = sample(path: "A/a.otf", hash: "x", name: "A", dateAdded: 200)
        XCTAssertEqual(DuplicateScanner.defaultKeeperPath(in: [newer, older]), "B/b.otf")
    }

    func testFontsToRemoveExcludesKeeper() {
        let a = sample(path: "A/a.otf", hash: "h", name: "A")
        let b = sample(path: "B/b.otf", hash: "h", name: "B")
        let group = DuplicateGroup(sha256: "h", fonts: [a, b])
        let removed = DuplicateScanner.fontsToRemove(from: group, keeperPath: "A/a.otf")
        XCTAssertEqual(removed.map(\.vaultPath), ["B/b.otf"])
    }

    private func sample(
        path: String,
        hash: String,
        name: String,
        dateAdded: TimeInterval = 1_700_000_000
    ) -> FontRecord {
        FontRecord(
            databaseID: nil,
            vaultPath: path,
            sha256: hash,
            fileSize: 100,
            format: "otf",
            dateAdded: dateAdded,
            psName: name,
            fullName: name,
            nameTableFullName: name,
            family: "Family",
            subfamily: "Regular",
            typographicFamily: "",
            typographicSubfamily: "",
            license: "",
            licenseURL: "",
            manufacturerURL: "",
            designerURL: "",
            version: "1",
            foundry: "",
            copyright: "",
            uniqueName: "",
            description: "",
            designer: "",
            trademark: "",
            manufacturer: "",
            vendorID: "",
            formatDetailed: "",
            isVariable: false,
            excludedFromIndex: false,
            extractedDetails: .empty,
            metadataIssues: .empty
        )
    }
}
