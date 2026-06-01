import Foundation
import GRDB

enum CatalogStoreError: LocalizedError {
    case vaultNotConfigured
    case databaseUnavailable
    case noFormatsSelected

    var errorDescription: String? {
        switch self {
        case .vaultNotConfigured: return "No vault folder is configured."
        case .databaseUnavailable: return "Could not open the font catalog database."
        case .noFormatsSelected: return "Select at least one font format to import."
        }
    }
}

/// SQLite catalog stored beside the vault: `{vault}/.fontvault/catalog.sqlite`
final class CatalogStore: Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// In-memory catalog with production migrations (unit tests).
    static func makeInMemoryForTests() throws -> CatalogStore {
        let queue = try DatabaseQueue()
        let store = CatalogStore(dbQueue: queue)
        try store.migrate()
        return store
    }

    static func open(vaultRoot: URL) throws -> CatalogStore {
        let support = vaultRoot.appendingPathComponent(".fontvault", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let dbURL = support.appendingPathComponent("catalog.sqlite")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(path: dbURL.path, configuration: config)
        let store = CatalogStore(dbQueue: queue)
        try store.migrate()
        return store
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: FontRecord.databaseTableName, ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("vaultPath", .text).notNull().unique()
                t.column("sha256", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("format", .text).notNull()
                t.column("dateAdded", .double).notNull()
                t.column("psName", .text).notNull()
                t.column("fullName", .text).notNull()
                t.column("family", .text).notNull()
                t.column("subfamily", .text).notNull()
                t.column("version", .text).notNull()
                t.column("foundry", .text).notNull()
                t.column("copyright", .text).notNull()
                t.column("isVariable", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_fonts_family", on: FontRecord.databaseTableName, columns: ["family"], ifNotExists: true)
            try db.create(index: "idx_fonts_format", on: FontRecord.databaseTableName, columns: ["format"], ifNotExists: true)
            try db.create(index: "idx_fonts_sha256", on: FontRecord.databaseTableName, columns: ["sha256"], ifNotExists: true)
        }

        migrator.registerMigration("v2_openTypeMetadata") { db in
            let columns = try db.columns(in: FontRecord.databaseTableName).map(\.name)
            if !columns.contains("uniqueName") {
                try db.alter(table: FontRecord.databaseTableName) { t in
                    t.add(column: "uniqueName", .text).notNull().defaults(to: "")
                    t.add(column: "description", .text).notNull().defaults(to: "")
                    t.add(column: "designer", .text).notNull().defaults(to: "")
                    t.add(column: "trademark", .text).notNull().defaults(to: "")
                    t.add(column: "manufacturer", .text).notNull().defaults(to: "")
                    t.add(column: "vendorID", .text).notNull().defaults(to: "")
                    t.add(column: "formatDetailed", .text).notNull().defaults(to: "")
                }
                try db.execute(sql: """
                    UPDATE fonts SET manufacturer = foundry
                    WHERE manufacturer = '' OR manufacturer IS NULL
                    """)
            }
        }

        migrator.registerMigration("v3_typographicNames") { db in
            let columns = try db.columns(in: FontRecord.databaseTableName).map(\.name)
            if !columns.contains("typographicFamily") {
                try db.alter(table: FontRecord.databaseTableName) { t in
                    t.add(column: "typographicFamily", .text).notNull().defaults(to: "")
                    t.add(column: "typographicSubfamily", .text).notNull().defaults(to: "")
                }
            }
        }

        migrator.registerMigration("v4_browseIndexes") { db in
            try db.create(
                index: "idx_fonts_fullName",
                on: FontRecord.databaseTableName,
                columns: ["fullName"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_fonts_dateAdded",
                on: FontRecord.databaseTableName,
                columns: ["dateAdded"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_fonts_fileSize",
                on: FontRecord.databaseTableName,
                columns: ["fileSize"],
                ifNotExists: true
            )
        }

        migrator.registerMigration("v5_excludedFromIndex") { db in
            let columns = try db.columns(in: FontRecord.databaseTableName).map(\.name)
            if !columns.contains("excludedFromIndex") {
                try db.alter(table: FontRecord.databaseTableName) { t in
                    t.add(column: "excludedFromIndex", .boolean).notNull().defaults(to: false)
                }
            }
        }

        migrator.registerMigration("v6_extractedDetails") { db in
            let columns = try db.columns(in: FontRecord.databaseTableName).map(\.name)
            if !columns.contains("extractedDetails") {
                try db.alter(table: FontRecord.databaseTableName) { t in
                    t.add(column: "extractedDetails", .text).notNull().defaults(to: "{}")
                }
            }
        }

        migrator.registerMigration("v7_metadataIssues") { db in
            let columns = try db.columns(in: FontRecord.databaseTableName).map(\.name)
            if !columns.contains("metadataIssues") {
                try db.alter(table: FontRecord.databaseTableName) { t in
                    t.add(column: "metadataIssues", .text).notNull().defaults(to: "{}")
                }
            }
        }

        migrator.registerMigration("v8_nameTableLiterals") { db in
            let columns = try db.columns(in: FontRecord.databaseTableName).map(\.name)
            if !columns.contains("nameTableFullName") {
                try db.alter(table: FontRecord.databaseTableName) { t in
                    t.add(column: "nameTableFullName", .text).notNull().defaults(to: "")
                    t.add(column: "license", .text).notNull().defaults(to: "")
                    t.add(column: "licenseURL", .text).notNull().defaults(to: "")
                    t.add(column: "manufacturerURL", .text).notNull().defaults(to: "")
                    t.add(column: "designerURL", .text).notNull().defaults(to: "")
                }
            }
        }

        try migrator.migrate(dbQueue)
    }

    func fetchAllFonts() throws -> [FontRecord] {
        try dbQueue.read { db in
            try FontRecord.order(Column("fullName")).fetchAll(db)
        }
    }

    /// Extra files beyond one keeper per SHA-256 group (for sidebar/status without loading all rows).
    func duplicateExtraFileCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(cnt - 1), 0) FROM (
                        SELECT COUNT(*) AS cnt FROM fonts
                        WHERE sha256 != '' AND excludedFromIndex = 0
                        GROUP BY sha256
                        HAVING cnt > 1
                    )
                    """
            ) ?? 0
        }
    }

    func insert(_ record: FontRecord) throws -> FontRecord {
        try dbQueue.write { db in
            var copy = record
            try copy.insert(db)
            return copy
        }
    }

    func update(_ record: FontRecord) throws {
        let copy = record
        try dbQueue.write { db in
            try copy.update(db)
        }
    }

    func delete(databaseIDs: [Int64]) throws {
        try dbQueue.write { db in
            for rowID in databaseIDs {
                try FontRecord.deleteOne(db, key: rowID)
            }
        }
    }

    func delete(vaultPaths: [String]) throws {
        guard !vaultPaths.isEmpty else { return }
        try dbQueue.write { db in
            for path in vaultPaths {
                _ = try FontRecord.filter(Column("vaultPath") == path).deleteAll(db)
            }
        }
    }

    func fontCount() throws -> Int {
        try dbQueue.read { db in
            try FontRecord.fetchCount(db)
        }
    }

    func activeFontCount() throws -> Int {
        try dbQueue.read { db in
            try FontRecord.filter(Column("excludedFromIndex") == false).fetchCount(db)
        }
    }

    func excludedFontCount() throws -> Int {
        try dbQueue.read { db in
            try FontRecord.filter(Column("excludedFromIndex") == true).fetchCount(db)
        }
    }

    func setExcludedFromIndex(vaultPaths: [String], excluded: Bool) throws -> Int {
        guard !vaultPaths.isEmpty else { return 0 }
        return try dbQueue.write { db in
            var updated = 0
            for path in vaultPaths {
                try db.execute(
                    sql: "UPDATE fonts SET excludedFromIndex = ? WHERE vaultPath = ?",
                    arguments: [excluded, path]
                )
                updated += db.changesCount
            }
            return updated
        }
    }

    /// Fonts eligible for duplicate detection (non-excluded catalog rows).
    func fetchFontsForDuplicateScan() throws -> [FontRecord] {
        try dbQueue.read { db in
            try FontRecord
                .filter(Column("excludedFromIndex") == false)
                .order(Column("fullName"))
                .fetchAll(db)
        }
    }

    func fetchFonts(
        search: String = "",
        format: String? = nil,
        sortColumn: String = "fullName",
        ascending: Bool = true,
        limit: Int = 500,
        offset: Int = 0
    ) throws -> [FontRecord] {
        try dbQueue.read { db in
            var request = FontRecord.all()
            if !search.isEmpty {
                let pattern = "%\(search)%"
                request = request.filter(
                    sql: """
                    fullName LIKE ? OR family LIKE ? OR psName LIKE ? OR foundry LIKE ?
                    OR manufacturer LIKE ? OR designer LIKE ? OR uniqueName LIKE ?
                    OR vendorID LIKE ? OR copyright LIKE ?
                    """,
                    arguments: [pattern, pattern, pattern, pattern, pattern, pattern, pattern, pattern, pattern]
                )
            }
            if let format, !format.isEmpty {
                request = request.filter(Column("format") == format)
            }

            let column = Column(sortColumn)
            request = ascending ? request.order(column) : request.order(column.desc)

            return try request.limit(limit, offset: offset).fetchAll(db)
        }
    }

    func formatCounts(activeOnly: Bool = true) throws -> [String: Int] {
        let (whereSQL, args) = activeOnly ? CatalogBrowseSQL.activeOnlyClause() : ("", [])
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT format, COUNT(*) AS count FROM fonts\(whereSQL) GROUP BY format",
                arguments: StatementArguments(args)
            )
            var result: [String: Int] = [:]
            for row in rows {
                if let format: String = row["format"], let count: Int = row["count"] {
                    result[format] = count
                }
            }
            return result
        }
    }

    func variableFontCount(activeOnly: Bool = true) throws -> Int {
        let (whereSQL, args) = activeOnly ? CatalogBrowseSQL.activeOnlyClause() : ("", [])
        let variableClause = whereSQL.isEmpty ? " WHERE isVariable = 1" : "\(whereSQL) AND isVariable = 1"
        return try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM fonts\(variableClause)",
                arguments: StatementArguments(args)
            ) ?? 0
        }
    }

    func vaultPathExists(_ vaultPath: String) throws -> Bool {
        try dbQueue.read { db in
            try FontRecord.filter(Column("vaultPath") == vaultPath).fetchCount(db) > 0
        }
    }

    func allVaultPaths() throws -> Set<String> {
        try dbQueue.read { db in
            let paths = try String.fetchAll(db, sql: "SELECT vaultPath FROM fonts")
            return Set(paths)
        }
    }

    func fetchRecord(vaultPath: String) throws -> FontRecord? {
        try dbQueue.read { db in
            try FontRecord.filter(Column("vaultPath") == vaultPath).fetchOne(db)
        }
    }

    func fetchRecords(vaultPaths: [String]) throws -> [FontRecord] {
        guard !vaultPaths.isEmpty else { return [] }
        return try dbQueue.read { db in
            try FontRecord
                .filter(vaultPaths.contains(Column("vaultPath")))
                .fetchAll(db)
        }
    }

    // MARK: - Windowed browse (Phase 0)

    func filteredFontCount(query: FontTableBrowseQuery) throws -> Int {
        let (whereSQL, args) = CatalogBrowseSQL.filterClause(query: query)
        return try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM fonts\(whereSQL)",
                arguments: StatementArguments(args)
            ) ?? 0
        }
    }

    func fetchFamilySummaries(
        query: FontTableBrowseQuery,
        sortColumn: String = "fullName",
        ascending: Bool = true
    ) throws -> [FontFamilySummary] {
        let (whereSQL, args) = CatalogBrowseSQL.filterClause(query: query)
        let orderBy = CatalogBrowseSQL.familyOrderExpression(sortColumn: sortColumn, ascending: ascending)
        let sql = """
            SELECT
                \(CatalogBrowseSQL.familyKeyExpression) AS familyKey,
                COUNT(*) AS styleCount,
                SUM(CASE WHEN excludedFromIndex THEN 1 ELSE 0 END) AS excludedStyleCount,
                SUM(fileSize) AS totalSize,
                GROUP_CONCAT(DISTINCT format) AS formatsJoined,
                COUNT(DISTINCT date(dateAdded, 'unixepoch')) AS distinctImportDays,
                MIN(dateAdded) AS minDateAdded,
                \(CatalogBrowseSQL.familyUniformAggregateSelectColumns())
            FROM fonts
            \(whereSQL)
            GROUP BY familyKey
            ORDER BY \(orderBy)
            """
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.compactMap { Self.summary(from: $0) }
        }
    }

    func fetchFontsForFamily(
        familyKey: String,
        query: FontTableBrowseQuery,
        sortColumn: String = "fullName",
        ascending: Bool = true
    ) throws -> [FontRecord] {
        var (whereSQL, args) = CatalogBrowseSQL.filterClause(query: query)
        let familyClause = "(\(CatalogBrowseSQL.familyKeyExpression)) = ?"
        if whereSQL.isEmpty {
            whereSQL = " WHERE \(familyClause)"
        } else {
            whereSQL += " AND \(familyClause)"
        }
        args.append(familyKey)
        let order = CatalogBrowseSQL.fontOrderClause(sortColumn: sortColumn, ascending: ascending)
        let sql = "SELECT * FROM fonts\(whereSQL) ORDER BY \(order)"
        return try dbQueue.read { db in
            try FontRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    func fetchFontsForFamilies(
        familyKeys: Set<String>,
        query: FontTableBrowseQuery,
        sortColumn: String = "fullName",
        ascending: Bool = true
    ) throws -> [FontRecord] {
        guard !familyKeys.isEmpty else { return [] }
        var (whereSQL, args) = CatalogBrowseSQL.filterClause(query: query)
        let placeholders = Array(repeating: "?", count: familyKeys.count).joined(separator: ", ")
        let familyClause = "(\(CatalogBrowseSQL.familyKeyExpression)) IN (\(placeholders))"
        if whereSQL.isEmpty {
            whereSQL = " WHERE \(familyClause)"
        } else {
            whereSQL += " AND \(familyClause)"
        }
        args.append(contentsOf: familyKeys.sorted())
        let order = CatalogBrowseSQL.fontOrderClause(sortColumn: sortColumn, ascending: ascending)
        let sql = "SELECT * FROM fonts\(whereSQL) ORDER BY \(order)"
        return try dbQueue.read { db in
            try FontRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    func fetchOrderedVaultPaths(
        query: FontTableBrowseQuery,
        sortColumn: String = "fullName",
        ascending: Bool = true,
        limit: Int,
        offset: Int = 0
    ) throws -> [String] {
        let (whereSQL, args) = CatalogBrowseSQL.filterClause(query: query)
        let order = CatalogBrowseSQL.fontOrderClause(sortColumn: sortColumn, ascending: ascending)
        let sql = "SELECT vaultPath FROM fonts\(whereSQL) ORDER BY \(order) LIMIT ? OFFSET ?"
        var allArgs = args
        allArgs.append(limit)
        allArgs.append(offset)
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: sql, arguments: StatementArguments(allArgs))
        }
    }

    func fetchAllFilteredVaultPaths(
        query: FontTableBrowseQuery,
        sortColumn: String = "fullName",
        ascending: Bool = true
    ) throws -> [String] {
        let (whereSQL, args) = CatalogBrowseSQL.filterClause(query: query)
        let order = CatalogBrowseSQL.fontOrderClause(sortColumn: sortColumn, ascending: ascending)
        let sql = "SELECT vaultPath FROM fonts\(whereSQL) ORDER BY \(order)"
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Batch insert/update during vault indexing.
    func applyIndexBatch(_ records: [FontRecord], existingPaths: inout Set<String>) throws {
        guard !records.isEmpty else { return }
        try dbQueue.write { db in
            for var record in records {
                if existingPaths.contains(record.vaultPath) {
                    try record.update(db)
                } else {
                    try record.insert(db)
                    existingPaths.insert(record.vaultPath)
                }
            }
        }
    }

    private static func summary(from row: Row) -> FontFamilySummary? {
        guard let key: String = row["familyKey"],
              let styleCount: Int = row["styleCount"],
              let totalSize: Int64 = row["totalSize"],
              let distinctImportDays: Int = row["distinctImportDays"],
              let minDateAdded: Double = row["minDateAdded"] else { return nil }
        let formatsJoined: String = row["formatsJoined"] ?? ""
        let formats = formatsJoined.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
        let excludedStyleCount = intColumn(row, "excludedStyleCount") ?? 0
        return FontFamilySummary(
            id: key,
            displayName: FontListGrouping.displayFamilyName(for: key),
            styleCount: styleCount,
            excludedStyleCount: excludedStyleCount,
            totalSize: totalSize,
            distinctFormats: formats,
            distinctImportDays: distinctImportDays,
            minDateAdded: minDateAdded,
            uniformValues: uniformValues(from: row, styleCount: styleCount),
            importDateState: importDateState(
                styleCount: styleCount,
                distinctImportDays: distinctImportDays,
                minDateAdded: minDateAdded
            )
        )
    }

    private static func uniformValues(from row: Row, styleCount: Int) -> FontFamilyUniformValues {
        func state(_ prefix: String) -> FontFamilyFieldState {
            uniformFieldState(
                row: row,
                styleCount: styleCount,
                distinctCountColumn: "\(prefix)UniformCount",
                populatedCountColumn: "\(prefix)PopulatedCount",
                valueColumn: "\(prefix)UniformValue"
            )
        }
        return FontFamilyUniformValues(
            family: state("family"),
            typographicFamily: state("typographicFamily"),
            style: state("style"),
            typographicStyle: state("typographicStyle"),
            postScript: state("postScript"),
            uniqueName: state("uniqueName"),
            version: state("version"),
            manufacturer: state("manufacturer"),
            vendorID: state("vendorID"),
            designer: state("designer"),
            description: state("description"),
            trademark: state("trademark"),
            copyright: state("copyright"),
            formatDetailed: state("formatDetailed")
        )
    }

    private static func uniformFieldState(
        row: Row,
        styleCount: Int,
        distinctCountColumn: String,
        populatedCountColumn: String,
        valueColumn: String
    ) -> FontFamilyFieldState {
        let distinctCount = intColumn(row, distinctCountColumn) ?? 0
        let populatedCount = intColumn(row, populatedCountColumn) ?? 0
        if populatedCount == 0 { return .empty }
        if distinctCount > 1 || populatedCount < styleCount { return .mixed }
        guard let value: String = row[valueColumn], !value.isEmpty else { return .empty }
        return .uniform(value)
    }

    private static func importDateState(
        styleCount: Int,
        distinctImportDays: Int,
        minDateAdded: TimeInterval
    ) -> FontFamilyFieldState {
        guard styleCount > 0 else { return .empty }
        guard distinctImportDays == 1 else { return .mixed }
        return .uniform(ImportDateDisplay.format(minDateAdded))
    }

    private static func intColumn(_ row: Row, _ column: String) -> Int? {
        if let value: Int = row[column] { return value }
        if let value: Int64 = row[column] { return Int(value) }
        return nil
    }

    /// On-disk size of `catalog.sqlite` (for compaction reporting).
    func databaseFileSizeBytes() -> Int64? {
        let values = try? FileManager.default.attributesOfItem(atPath: dbQueue.path)
        return values?[.size] as? Int64
    }

    /// Reclaim free pages after catalog row deletes (`VACUUM`).
    func vacuum() throws {
        try dbQueue.vacuum()
    }
}
