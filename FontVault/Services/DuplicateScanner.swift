import Foundation

enum DuplicateScanner {
    /// Groups catalog rows with the same SHA-256 (FEX “Duplicates → File / matching file content”).
    static func findGroups(in fonts: [FontRecord]) -> [DuplicateGroup] {
        let grouped = Dictionary(grouping: fonts, by: \.sha256)
        return grouped
            .filter { $0.value.count > 1 }
            .map { hash, records in
                DuplicateGroup(
                    sha256: hash,
                    fonts: records.sorted {
                        $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
    }

    /// Default keeper: earliest import date, then shortest vault path.
    static func defaultKeeperPath(in fonts: [FontRecord]) -> String {
        fonts
            .sorted {
                if $0.dateAdded != $1.dateAdded { return $0.dateAdded < $1.dateAdded }
                return $0.vaultPath.localizedCaseInsensitiveCompare($1.vaultPath) == .orderedAscending
            }
            .first?
            .vaultPath ?? fonts[0].vaultPath
    }

    static func fontsToRemove(from group: DuplicateGroup, keeperPath: String) -> [FontRecord] {
        group.fonts.filter { $0.vaultPath != keeperPath }
    }
}
