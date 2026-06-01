import Foundation

/// When to compact `catalog.sqlite` (SQLite `VACUUM`) during Clean Vault — not on every launch.
enum CatalogOptimizationPolicy {
    /// Time-based compaction when the user runs Clean Vault and the vault is already consistent.
    static let daysBetweenCompaction = 30

    static func shouldOptimize(after cleanResult: CleanVaultResult, lastOptimizedAt: Date?) -> Bool {
        if cleanResult.removedFromCatalog >= 1 {
            return true
        }
        guard let lastOptimizedAt else { return false }
        let days = Calendar.current.dateComponents([.day], from: lastOptimizedAt, to: Date()).day ?? 0
        return days >= daysBetweenCompaction
    }
}
