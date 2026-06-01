import Foundation
import UniformTypeIdentifiers

/// Which file types to include when importing (Settings default + import panel one-shot).
/// Extensions match `FontMetadataReader.importableExtensions` — only formats Core Text can catalog today.
struct ImportFormatOptions: Equatable, Sendable {
    var openType: Bool = true
    var trueType: Bool = true
    var webFonts: Bool = false

    static let desktopDefaults = ImportFormatOptions()

    private static let openTypeExtensions: Set<String> = ["otf", "otc"]
    private static let trueTypeExtensions: Set<String> = ["ttf", "ttc", "dfont"]
    private static let webExtensions: Set<String> = ["woff", "woff2"]

    func allows(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard FontMetadataReader.importableExtensions.contains(ext) else { return false }
        if openType, Self.openTypeExtensions.contains(ext) { return true }
        if trueType, Self.trueTypeExtensions.contains(ext) { return true }
        if webFonts, Self.webExtensions.contains(ext) { return true }
        return false
    }

    func allowsAnyFontFile() -> Bool {
        openType || trueType || webFonts
    }

    /// Extensions enabled by the current format checkboxes (subset of `importableExtensions`).
    func enabledExtensions() -> Set<String> {
        var exts = Set<String>()
        if openType { exts.formUnion(Self.openTypeExtensions) }
        if trueType { exts.formUnion(Self.trueTypeExtensions) }
        if webFonts { exts.formUnion(Self.webExtensions) }
        return exts
    }

    /// Content types for `NSOpenPanel.allowedContentTypes` (file picker filter).
    func allowedContentTypes() -> [UTType] {
        let extensions = enabledExtensions().sorted()
        var types: [UTType] = []
        var seen = Set<String>()
        for ext in extensions {
            guard let type = UTType(filenameExtension: ext) else { continue }
            guard seen.insert(type.identifier).inserted else { continue }
            types.append(type)
        }
        if types.isEmpty, allowsAnyFontFile() {
            return [.font]
        }
        return types
    }

    mutating func selectAll() {
        openType = true
        trueType = true
        webFonts = true
    }

    mutating func selectNone() {
        openType = false
        trueType = false
        webFonts = false
    }
}

enum ImportFileOperation: String, CaseIterable, Identifiable {
    case copy
    case move

    var id: String { rawValue }

    var label: String {
        switch self {
        case .copy: return "Copy into vault"
        case .move: return "Move into vault"
        }
    }

    var detail: String {
        switch self {
        case .copy: return "Original files stay in place."
        case .move: return "Original files are removed after a successful import."
        }
    }
}
