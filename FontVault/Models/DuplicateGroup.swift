import Foundation

/// Fonts that share identical file content (SHA-256).
struct DuplicateGroup: Identifiable, Hashable, Sendable {
    var id: String { sha256 }
    let sha256: String
    let fonts: [FontRecord]

    var copyCount: Int { fonts.count }

    var displayTitle: String {
        let names = Set(fonts.map(\.fullName))
        if names.count == 1, let name = names.first {
            return name
        }
        return fonts.first?.family ?? "Duplicate files"
    }
}
