import Foundation

/// Resolved vault style-folder title (FEX uses name ID 4 when viable).
struct VaultFolderResolution: Sendable {
    let label: String
    let usedFilenameFallback: Bool
}

/// Computes FEX-style A–Z destination paths inside the vault root.
struct LayoutEngine: Sendable {
    let vaultRoot: URL

    private static let fontExtensions: Set<String> = ["otf", "ttf", "ttc", "otc", "woff", "woff2", "dfont"]

    static func isFontFile(_ url: URL) -> Bool {
        fontExtensions.contains(url.pathExtension.lowercased())
    }

    /// Relative path inside the vault for a new import (reserves a new folder name when the style folder already exists).
    func relativeDestination(
        folderLabel: String,
        fileName: String,
        foundry: String
    ) -> String {
        canonicalRelativeDestination(
            folderLabel: folderLabel,
            fileName: fileName,
            foundry: foundry,
            resolveUniqueFolder: true
        )
    }

    /// Canonical vault path without inventing `Folder 2` names — used when reorganizing existing files.
    func canonicalRelativeDestination(
        folderLabel: String,
        fileName: String,
        foundry: String,
        resolveUniqueFolder: Bool = false
    ) -> String {
        let safeFileName = sanitize(fileName)
        let bucket = fexBucket(for: folderLabel)
        let baseFolder = sanitize(folderLabel)
        let folder: String
        if resolveUniqueFolder {
            folder = uniqueFolderName(
                base: baseFolder,
                under: vaultRoot.appendingPathComponent(bucket, isDirectory: true)
            )
        } else {
            folder = baseFolder
        }
        _ = foundry
        return "\(bucket)/\(folder)/\(safeFileName)"
    }

    /// True when the file is already under the correct bucket/folder for this resolved label.
    func isAlreadyCanonical(relativePath: String, folderLabel: String, foundry: String) -> Bool {
        _ = foundry
        let parts = relativePath.split(separator: "/").map(String.init)
        guard parts.count >= 3 else { return false }
        let bucket = fexBucket(for: folderLabel)
        let folder = sanitize(folderLabel)
        return parts[0] == bucket && parts[1] == folder
    }

    func destinationURL(
        folderLabel: String,
        fileName: String,
        foundry: String
    ) -> URL {
        let relative = relativeDestination(
            folderLabel: folderLabel,
            fileName: fileName,
            foundry: foundry
        )
        return vaultRoot.appendingPathComponent(relative)
    }

    /// Resolves the vault style-folder title from name ID 4 (`fullName`), with filename-stem fallback.
    func resolveVaultFolderLabel(fullName: String, fileName: String) -> VaultFolderResolution {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent

        if let candidate = normalizedVaultLabelCandidate(fullName),
           FontMetadataValidator.isViableVaultFolderLabel(candidate) {
            return VaultFolderResolution(label: sanitize(candidate), usedFilenameFallback: false)
        }

        if let candidate = normalizedVaultLabelCandidate(stem),
           FontMetadataValidator.isViableVaultFolderLabel(candidate) {
            return VaultFolderResolution(label: sanitize(candidate), usedFilenameFallback: true)
        }

        return VaultFolderResolution(label: "Unknown", usedFilenameFallback: true)
    }

    // MARK: - FEX rules

    /// First letter of folder label → A–Z, else OTHER.
    func fexBucket(for folderLabel: String) -> String {
        let trimmed = folderLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "OTHER" }
        if first.isLetter, let scalar = first.unicodeScalars.first {
            let upper = Character(scalar).uppercased()
            if let c = upper.first, c.isASCII && c.isLetter {
                return String(c)
            }
        }
        return "OTHER"
    }

    /// If `base` exists, try `base 2`, `base 3`, …
    func uniqueFolderName(base: String, under parentDirectory: URL) -> String {
        var candidate = base
        var suffix = 2
        while FileManager.default.fileExists(atPath: parentDirectory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\")
        let parts = trimmed.components(separatedBy: invalid).filter { !$0.isEmpty }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? "Unknown" : joined
    }

    private func normalizedVaultLabelCandidate(_ raw: String) -> String? {
        let trimmed = FontMetadataValidator.strippingControlCharactersForVaultLabel(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Character {
    var isASCII: Bool {
        unicodeScalars.allSatisfy { $0.isASCII }
    }
}
