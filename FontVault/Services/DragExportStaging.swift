import Foundation

/// Builds a temporary folder layout for drag-out export to Finder.
enum DragExportStaging {
    static let multiFamilyRootFolderName = "FontVault Export"

    struct Plan {
        /// URLs to place on the drag pasteboard (one folder or individual files).
        let dragURLs: [URL]
        /// Temp directory to remove after the drag session ends (nil when dragging vault files directly).
        let stagingRoot: URL?
        let fileCount: Int
    }

    /// Decides family-grouping shape from selection (used by `.byFamily` path layout).
    static func layout(for fonts: [FontRecord]) -> ExportLayout {
        guard !fonts.isEmpty else { return .empty }

        if fonts.count == 1 {
            return .singleFile
        }

        let grouped = Dictionary(grouping: fonts) { FontListGrouping.familyKey(for: $0) }
        if grouped.count == 1 {
            return .singleFamilyMultiFile
        }
        return .multipleFamilies
    }

    enum ExportLayout: Equatable {
        case empty
        case singleFile
        case singleFamilyMultiFile
        case multipleFamilies
    }

    /// Copies font files into a temp directory (or uses vault paths directly) for drag export.
    /// Honors `ExportLayoutMode` from Settings (same path rules as File → Export).
    static func prepare(
        fonts: [FontRecord],
        mode: ExportLayoutMode,
        sourceURL: (FontRecord) -> URL?,
        fileName: (FontRecord) -> String
    ) throws -> Plan? {
        guard !fonts.isEmpty else { return nil }

        let pathMap = relativeExportPaths(for: fonts, mode: mode, fileName: fileName)

        if fonts.count == 1,
           let font = fonts.first,
           let relative = pathMap[font.vaultPath],
           !relative.contains("/"),
           let source = sourceURL(font) {
            return Plan(dragURLs: [source], stagingRoot: nil, fileCount: 1)
        }

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FontVault-Drag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        for font in fonts {
            guard let source = sourceURL(font), let relative = pathMap[font.vaultPath] else { continue }
            let dest = stagingRoot.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try copyFile(from: source, to: dest)
        }

        let dragURLs = dragURLs(stagingRoot: stagingRoot, pathMap: pathMap)
        return Plan(dragURLs: dragURLs, stagingRoot: stagingRoot, fileCount: fonts.count)
    }

    /// Relative paths under the export destination (menu export and drag staging).
    static func relativeExportPaths(
        for selection: [FontRecord],
        mode: ExportLayoutMode,
        fileName: (FontRecord) -> String
    ) -> [String: String] {
        guard !selection.isEmpty else { return [:] }

        switch mode {
        case .vaultStructure:
            return Dictionary(uniqueKeysWithValues: selection.map { ($0.vaultPath, $0.vaultPath) })
        case .flat:
            var used = Set<String>()
            var map: [String: String] = [:]
            for font in selection {
                let unique = uniqueFileName(fileName(font), used: &used)
                map[font.vaultPath] = unique
            }
            return map
        case .byFamily:
            return familyRelativePaths(for: selection, fileName: fileName)
        }
    }

    /// Pasteboard URLs after files are staged under `stagingRoot`.
    static func dragURLs(stagingRoot: URL, pathMap: [String: String]) -> [URL] {
        let relatives = pathMap.values.sorted()
        guard !relatives.isEmpty else { return [] }

        if relatives.count == 1, let relative = relatives.first {
            let dest = stagingRoot.appendingPathComponent(relative)
            if !relative.contains("/") {
                return [dest]
            }
            if relative.hasPrefix("\(multiFamilyRootFolderName)/") {
                return [stagingRoot.appendingPathComponent(multiFamilyRootFolderName)]
            }
            return [dest.deletingLastPathComponent()]
        }

        let topLevels = Set(relatives.map { ($0 as NSString).pathComponents.first ?? $0 })
        if topLevels.count == 1, let top = topLevels.first,
           relatives.allSatisfy({ ($0 as NSString).pathComponents.first == top }) {
            return [stagingRoot.appendingPathComponent(top)]
        }

        if relatives.allSatisfy({ !$0.contains("/") }) {
            return relatives.map { stagingRoot.appendingPathComponent($0) }
        }

        return [stagingRoot]
    }

    private static func familyRelativePaths(
        for selection: [FontRecord],
        fileName: (FontRecord) -> String
    ) -> [String: String] {
        var map: [String: String] = [:]

        switch layout(for: selection) {
        case .empty:
            break
        case .singleFile:
            let font = selection[0]
            map[font.vaultPath] = fileName(font)
        case .singleFamilyMultiFile:
            let key = FontListGrouping.familyKey(for: selection[0])
            let family = FontListGrouping.exportFolderName(
                displayName: FontListGrouping.displayFamilyName(for: key),
                styleCount: selection.count
            )
            var used = Set<String>()
            for font in selection {
                let unique = uniqueFileName(fileName(font), used: &used)
                map[font.vaultPath] = "\(family)/\(unique)"
            }
        case .multipleFamilies:
            let grouped = Dictionary(grouping: selection) { FontListGrouping.familyKey(for: $0) }
            for key in grouped.keys.sorted() {
                guard let members = grouped[key] else { continue }
                let family = FontListGrouping.exportFolderName(
                    displayName: FontListGrouping.displayFamilyName(for: key),
                    styleCount: members.count
                )
                var used = Set<String>()
                for font in members {
                    let unique = uniqueFileName(fileName(font), used: &used)
                    map[font.vaultPath] = "\(multiFamilyRootFolderName)/\(family)/\(unique)"
                }
            }
        }

        return map
    }

    static func uniqueFileName(_ baseName: String, used: inout Set<String>) -> String {
        if !used.contains(baseName) {
            used.insert(baseName)
            return baseName
        }
        let ext = (baseName as NSString).pathExtension
        let stem = (baseName as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate: String
            if ext.isEmpty {
                candidate = "\(stem) \(n)"
            } else {
                candidate = "\(stem) \(n).\(ext)"
            }
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
            n += 1
        }
    }

    static func sanitizedFolderName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Unknown family" : cleaned
    }

    private static func copyFile(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
    }
}
