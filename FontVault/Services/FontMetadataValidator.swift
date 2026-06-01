import Foundation

enum FontMetadataValidator {
    private static let placeholderTokens: Set<String> = [
        "unknown", "undefined", "untitled", "font", ".notdef", "n/a", "na", "none",
    ]

    private static let forbiddenVaultLabelLeading: Set<Character> = ["/", ":", ".", "_", "-", "&"]

    /// Strips control characters (including DEL) for vault folder label resolution; does not mutate catalog values.
    static func strippingControlCharactersForVaultLabel(_ value: String) -> String {
        String(value.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                || scalar == "\n" || scalar == "\t" || scalar == "\r"
        })
    }

    /// Whether a name is safe to use as an on-disk vault folder title (FEX uses name ID 4 when viable).
    static func isViableVaultFolderLabel(_ value: String) -> Bool {
        let trimmed = strippingControlCharactersForVaultLabel(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed == "." || trimmed == ".." { return false }
        guard trimmed.contains(where: { $0.isLetter || $0.isNumber }) else { return false }
        if let first = trimmed.first, forbiddenVaultLabelLeading.contains(first) { return false }
        if isPlaceholderOnly(trimmed) { return false }
        return true
    }

    /// Value-only checks (no name-table / Core Text comparison).
    static func issues(for value: String, field: FontMetadataFieldKey) -> [MetadataIssue] {
        guard !value.isEmpty else { return [] }
        var found: [MetadataIssue] = []

        if value.unicodeScalars.contains(where: \.isReplacementCharacter) {
            found.append(.decodeReplacement)
        }
        for scalar in value.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar),
               scalar != "\n", scalar != "\t", scalar != "\r" {
                found.append(.controlCharacter)
                break
            }
        }

        if isPlaceholderOnly(value) {
            found.append(.placeholderOnly)
        }

        switch field {
        case .vendorID:
            if !isValidVendorID(value) {
                found.append(.vendorIDMalformed)
            }
        default:
            break
        }

        return Array(Set(found)).sorted { $0.rawValue < $1.rawValue }
    }

    /// Value checks at import; name-table vs Core Text comparison is intentionally omitted (too noisy).
    static func issues(
        for value: String,
        field: FontMetadataFieldKey,
        nameTable: String?,
        coreText: String?
    ) -> [MetadataIssue] {
        issues(for: value, field: field)
    }

    /// Warn when the PostScript name does not match the on-disk file name (without extension).
    static func postScriptFilenameIssues(psName: String, fileStem: String) -> [MetadataIssue] {
        let stem = fileStem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !psName.isEmpty, !stem.isEmpty else { return [] }
        guard postScriptMatchesFilename(psName: psName, fileStem: stem) else {
            return [.postScriptNameFilenameMismatch]
        }
        return []
    }

    static func postScriptFilenameIssues(psName: String, fileURL: URL) -> [MetadataIssue] {
        postScriptFilenameIssues(
            psName: psName,
            fileStem: fileURL.deletingPathExtension().lastPathComponent
        )
    }

    private static func postScriptMatchesFilename(psName: String, fileStem: String) -> Bool {
        normalizeFilenameToken(psName) == normalizeFilenameToken(fileStem)
    }

    private static func normalizeFilenameToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func isPlaceholderOnly(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let token = trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return placeholderTokens.contains(token)
    }

    /// OS/2 `achVendID` is four bytes, often space-padded; catalog stores the trimmed tag (e.g. `00`).
    private static func isValidVendorID(_ value: String) -> Bool {
        let stripped = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty, stripped.count <= 4 else { return false }
        let allowed = CharacterSet.alphanumerics
        return stripped.unicodeScalars.allSatisfy { $0.isASCII && allowed.contains($0) }
    }

}

private extension UnicodeScalar {
    var isReplacementCharacter: Bool { self == "\u{FFFD}" }
}
