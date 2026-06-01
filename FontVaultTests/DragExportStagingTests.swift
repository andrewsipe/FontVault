import XCTest
@testable import FontVault

final class DragExportStagingTests: XCTestCase {
    func testSingleFileUsesFlatLayout() {
        let fonts = [sample(family: "Aero", path: "A/a.otf")]
        XCTAssertEqual(DragExportStaging.layout(for: fonts), .singleFile)
    }

    func testSingleFamilyMultipleFilesUsesFamilyFolder() {
        let fonts = [
            sample(family: "Aero", path: "A/a.otf"),
            sample(family: "Aero", path: "A/b.otf"),
        ]
        XCTAssertEqual(DragExportStaging.layout(for: fonts), .singleFamilyMultiFile)
    }

    func testMultipleFamiliesUsesExportRoot() {
        let fonts = [
            sample(family: "Aero", path: "A/a.otf"),
            sample(family: "Gotham", path: "G/g.otf"),
        ]
        XCTAssertEqual(DragExportStaging.layout(for: fonts), .multipleFamilies)
    }

    func testPrepareSingleFamilyCreatesFamilyDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("Aero-Regular.otf")
        try Data("font".utf8).write(to: source)

        let fonts = [
            sample(family: "Aero", path: "vault/Aero-Regular.otf"),
            sample(family: "Aero", path: "vault/Aero-Bold.otf"),
        ]
        let second = tmp.appendingPathComponent("Aero-Bold.otf")
        try Data("font".utf8).write(to: second)

        let plan = try XCTUnwrap(DragExportStaging.prepare(
            fonts: fonts,
            mode: .byFamily,
            sourceURL: { record in
                record.vaultPath.contains("Bold") ? second : source
            },
            fileName: fileName
        ))

        XCTAssertEqual(plan.fileCount, 2)
        XCTAssertEqual(plan.dragURLs.count, 1)
        XCTAssertEqual(plan.dragURLs[0].lastPathComponent, "Aero (2)")
        let contents = try FileManager.default.contentsOfDirectory(atPath: plan.dragURLs[0].path)
        XCTAssertEqual(contents.count, 2)

        if let staging = plan.stagingRoot {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    func testMenuExportByFamilySingleFamilyPaths() {
        let fonts = [
            sample(family: "Aero", path: "A/Aero.otf"),
            sample(family: "Aero", path: "A/Aero-Bold.otf"),
        ]
        let paths = DragExportStaging.relativeExportPaths(for: fonts, mode: .byFamily, fileName: fileName)
        XCTAssertEqual(paths["A/Aero.otf"], "Aero (2)/Aero.otf")
        XCTAssertEqual(paths["A/Aero-Bold.otf"], "Aero (2)/Aero-Bold.otf")
    }

    func testMenuExportByFamilyMultipleFamiliesPaths() {
        let fonts = [
            sample(family: "Aero", path: "A/a.otf", file: "a.otf"),
            sample(family: "Gotham", path: "G/g.otf", file: "g.otf"),
        ]
        let paths = DragExportStaging.relativeExportPaths(for: fonts, mode: .byFamily, fileName: fileName)
        XCTAssertEqual(paths["A/a.otf"], "FontVault Export/Aero (1)/a.otf")
        XCTAssertEqual(paths["G/g.otf"], "FontVault Export/Gotham (1)/g.otf")
    }

    func testMenuExportVaultStructureUsesVaultPaths() {
        let fonts = [sample(family: "Aero", path: "A/Aero Bold/Aero.otf", file: "Aero.otf")]
        let paths = DragExportStaging.relativeExportPaths(for: fonts, mode: .vaultStructure, fileName: fileName)
        XCTAssertEqual(paths["A/Aero Bold/Aero.otf"], "A/Aero Bold/Aero.otf")
    }

    func testPrepareMultipleFamiliesUsesFontVaultExportRoot() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let aero = tmp.appendingPathComponent("a.otf")
        let gotham = tmp.appendingPathComponent("g.otf")
        try Data("a".utf8).write(to: aero)
        try Data("g".utf8).write(to: gotham)

        let fonts = [
            sample(family: "Aero", path: "A/a.otf"),
            sample(family: "Gotham", path: "G/g.otf"),
        ]

        let plan = try XCTUnwrap(DragExportStaging.prepare(
            fonts: fonts,
            mode: .byFamily,
            sourceURL: { record in
                record.family == "Aero" ? aero : gotham
            },
            fileName: fileName
        ))

        XCTAssertEqual(plan.dragURLs[0].lastPathComponent, DragExportStaging.multiFamilyRootFolderName)
        let families = try FileManager.default.contentsOfDirectory(atPath: plan.dragURLs[0].path).sorted()
        XCTAssertEqual(families, ["Aero (1)", "Gotham (1)"])

        if let staging = plan.stagingRoot {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    func testPrepareStagedFilesAreCopiesNotSymlinks() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let regular = tmp.appendingPathComponent("Regular.otf")
        let bold = tmp.appendingPathComponent("Bold.otf")
        try Data("regular".utf8).write(to: regular)
        try Data("bold".utf8).write(to: bold)

        let fonts = [
            sample(family: "Aero", path: "vault/Regular.otf"),
            sample(family: "Aero", path: "vault/Bold.otf"),
        ]

        let plan = try XCTUnwrap(DragExportStaging.prepare(
            fonts: fonts,
            mode: .byFamily,
            sourceURL: { record in
                record.vaultPath.contains("Bold") ? bold : regular
            },
            fileName: fileName
        ))

        let folder = plan.dragURLs[0]
        let stagedFiles = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(stagedFiles.count, 2)
        for file in stagedFiles {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey])
            XCTAssertFalse(values.isSymbolicLink ?? false, "\(file.lastPathComponent) should be a copy, not a symlink")
        }

        if let staging = plan.stagingRoot {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    func testDragPrepareFlatModeUsesIndividualFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let a = tmp.appendingPathComponent("a.otf")
        let b = tmp.appendingPathComponent("b.otf")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)

        let fonts = [
            sample(family: "Aero", path: "vault/a.otf"),
            sample(family: "Gotham", path: "vault/b.otf"),
        ]

        let plan = try XCTUnwrap(DragExportStaging.prepare(
            fonts: fonts,
            mode: .flat,
            sourceURL: { $0.vaultPath.contains("b") ? b : a },
            fileName: fileName
        ))

        XCTAssertEqual(plan.dragURLs.count, 2)
        XCTAssertEqual(Set(plan.dragURLs.map(\.lastPathComponent)), Set(["a.otf", "b.otf"]))
        if let staging = plan.stagingRoot {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    func testDragPrepareVaultStructurePreservesBuckets() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("Aero.otf")
        try Data("font".utf8).write(to: source)

        let fonts = [sample(family: "Aero", path: "A/Aero Bold/Aero.otf", file: "Aero.otf")]
        let plan = try XCTUnwrap(DragExportStaging.prepare(
            fonts: fonts,
            mode: .vaultStructure,
            sourceURL: { _ in source },
            fileName: fileName
        ))

        XCTAssertEqual(plan.dragURLs.count, 1)
        let staged = plan.dragURLs[0].appendingPathComponent("Aero.otf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        if let staging = plan.stagingRoot {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    private func fileName(_ record: FontRecord) -> String {
        (record.vaultPath as NSString).lastPathComponent
    }

    private func sample(family: String, path: String, file: String? = nil) -> FontRecord {
        FontRecord(
            databaseID: nil,
            vaultPath: path,
            sha256: "x",
            fileSize: 1,
            format: "otf",
            dateAdded: 0,
            psName: "p",
            fullName: file ?? "Full",
            nameTableFullName: file ?? "Full",
            family: family,
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
