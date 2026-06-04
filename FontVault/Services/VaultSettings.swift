import AppKit
import Foundation

/// User defaults for vault location and layout. Non-sandboxed: plain file URLs.
@MainActor
final class VaultSettings: ObservableObject {
    static let shared = VaultSettings()

    enum Keys {
        static let vaultRootPath = "vaultRootPath"
        static let layoutMode = "layoutMode"
        static let organizesVaultFiles = "organizesVaultFiles"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let importOpenType = "importOpenType"
        static let importTrueType = "importTrueType"
        static let importWebFonts = "importWebFonts"
        static let importMoveToVault = "importMoveToVault"
        static let exportMaintainStructure = "exportMaintainStructure"
        static let exportLayoutMode = "exportLayoutMode"
        static let visibleListColumns = "visibleListColumns"
        static let visibleInspectorFields = "visibleInspectorFields"
        static let listColumnWidths = "listColumnWidths"
        static let listColumnOrder = "listColumnOrder"
        static let listRowDensity = "listRowDensity"
        static let groupedListSortPreset = "groupedListSortPreset"
        static let flatListSortPreset = "flatListSortPreset"
        static let catalogMetadataVersion = "catalogMetadataVersion"
        static let showLibraryCounters = "showLibraryCounters"
        static let lastCatalogOptimization = "lastCatalogOptimization"
        static let showIgnoredFonts = "showIgnoredFonts"
        static let showMetadataWarnings = "showMetadataWarnings"
        static let excludeIgnoredFontsFromIndex = "excludeIgnoredFontsFromIndex"
        static let suppressExcludeFromIndexConfirmation = "suppressExcludeFromIndexConfirmation"
    }

    /// Bump when catalog columns or metadata extraction changes; prompts re-index.
    static let currentCatalogMetadataVersion = 10

    @Published var vaultRootURL: URL? {
        didSet {
            if let url = vaultRootURL {
                UserDefaults.standard.set(url.path, forKey: Keys.vaultRootPath)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.vaultRootPath)
            }
        }
    }

    /// When true, Font Vault imports into A–Z buckets and offers Reorganize. When false, user adds files in Finder and scans the catalog.
    @Published var organizesVaultFiles: Bool {
        didSet {
            UserDefaults.standard.set(organizesVaultFiles, forKey: Keys.organizesVaultFiles)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    @Published var importFormats: ImportFormatOptions {
        didSet { persistImportFormats() }
    }

    @Published var importOperation: ImportFileOperation {
        didSet {
            UserDefaults.standard.set(importOperation == .move, forKey: Keys.importMoveToVault)
        }
    }

    @Published var exportLayoutMode: ExportLayoutMode {
        didSet {
            UserDefaults.standard.set(exportLayoutMode.rawValue, forKey: Keys.exportLayoutMode)
        }
    }

    @Published var visibleListColumns: [FontListColumn] {
        didSet {
            Task { @MainActor in persistColumnPreferences() }
        }
    }

    /// Master column order (all columns). Drives Font Table settings and table column order.
    @Published var listColumnOrder: [FontListColumn] = FontListColumn.allCases {
        didSet {
            let normalized = Self.dedupedColumnOrder(listColumnOrder)
            if normalized != listColumnOrder {
                listColumnOrder = normalized
                return
            }
            persistListColumnOrder()
        }
    }

    @Published var visibleInspectorFields: [InspectorField] {
        didSet { persistInspectorPreferences() }
    }

    @Published var listColumnWidths: [String: CGFloat] = [:] {
        didSet { persistListColumnWidths() }
    }

    @Published var listRowDensity: FontListRowDensity {
        didSet {
            UserDefaults.standard.set(listRowDensity.rawValue, forKey: Keys.listRowDensity)
        }
    }

    /// Default sort within each family when **Group by Family** is on.
    @Published var groupedListSortPreset: FontListSortPreset {
        didSet {
            guard groupedListSortPreset != oldValue else { return }
            UserDefaults.standard.set(groupedListSortPreset.rawValue, forKey: Keys.groupedListSortPreset)
            onListSortPresetChanged?()
        }
    }

    /// Default sort for the flat (ungrouped) font list.
    @Published var flatListSortPreset: FontListSortPreset {
        didSet {
            guard flatListSortPreset != oldValue else { return }
            UserDefaults.standard.set(flatListSortPreset.rawValue, forKey: Keys.flatListSortPreset)
            onListSortPresetChanged?()
        }
    }

    /// Called when grouped/flat list sort presets change (wired from `AppState`).
    var onListSortPresetChanged: (@MainActor () -> Void)?

    /// Trailing counts on Library rows (All fonts, Duplicates, format badges).
    @Published var showLibraryCounters: Bool {
        didSet {
            UserDefaults.standard.set(showLibraryCounters, forKey: Keys.showLibraryCounters)
        }
    }

    /// When true, excluded fonts are visible in the font table (with distinct styling).
    @Published var showIgnoredFonts: Bool {
        didSet {
            UserDefaults.standard.set(showIgnoredFonts, forKey: Keys.showIgnoredFonts)
        }
    }

    /// When true, show metadata quality warnings in the list, status bar, and inspector.
    @Published var showMetadataWarnings: Bool {
        didSet {
            UserDefaults.standard.set(showMetadataWarnings, forKey: Keys.showMetadataWarnings)
        }
    }

    /// UserDefaults-backed read for model code off the main actor.
    nonisolated static var metadataWarningsVisible: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Keys.showMetadataWarnings) == nil
            ? true
            : defaults.bool(forKey: Keys.showMetadataWarnings)
    }

    /// When true, vault scan skips paths marked `excludedFromIndex`.
    @Published var excludeIgnoredFontsFromIndex: Bool {
        didSet {
            UserDefaults.standard.set(excludeIgnoredFontsFromIndex, forKey: Keys.excludeIgnoredFontsFromIndex)
        }
    }

    /// When true, **Exclude from Index…** runs without a confirmation sheet.
    @Published var suppressExcludeFromIndexConfirmation: Bool {
        didSet {
            UserDefaults.standard.set(
                suppressExcludeFromIndexConfirmation,
                forKey: Keys.suppressExcludeFromIndexConfirmation
            )
        }
    }

    private init() {
        if let path = UserDefaults.standard.string(forKey: Keys.vaultRootPath) {
            vaultRootURL = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            vaultRootURL = nil
        }

        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)

        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.organizesVaultFiles) == nil {
            organizesVaultFiles = true
        } else {
            organizesVaultFiles = defaults.bool(forKey: Keys.organizesVaultFiles)
        }

        if defaults.object(forKey: Keys.importOpenType) == nil {
            importFormats = .desktopDefaults
            importOperation = .copy
            exportLayoutMode = .byFamily
            visibleListColumns = FontListColumn.defaultVisible
            visibleInspectorFields = InspectorField.defaultVisible
            listColumnWidths = [:]
            listColumnOrder = FontListColumn.allCases
            listRowDensity = .compact
            groupedListSortPreset = .styleOrder
            flatListSortPreset = .byName
        } else {
            importFormats = ImportFormatOptions(
                openType: defaults.bool(forKey: Keys.importOpenType),
                trueType: defaults.bool(forKey: Keys.importTrueType),
                webFonts: defaults.bool(forKey: Keys.importWebFonts)
            )
            importOperation = defaults.bool(forKey: Keys.importMoveToVault) ? .move : .copy
            if let raw = defaults.string(forKey: Keys.exportLayoutMode),
               let mode = ExportLayoutMode(rawValue: raw) {
                exportLayoutMode = mode
            } else if defaults.object(forKey: Keys.exportMaintainStructure) != nil {
                exportLayoutMode = defaults.bool(forKey: Keys.exportMaintainStructure) ? .vaultStructure : .flat
            } else {
                exportLayoutMode = .byFamily
            }
            visibleListColumns = Self.loadColumns()
            visibleInspectorFields = Self.loadInspectorFields()
            listColumnWidths = Self.loadListColumnWidths()
            listColumnOrder = Self.dedupedColumnOrder(Self.loadListColumnOrder())
            if let raw = defaults.string(forKey: Keys.listRowDensity),
               let density = FontListRowDensity(rawValue: raw) {
                listRowDensity = density
            } else {
                listRowDensity = .compact
            }
            groupedListSortPreset = Self.loadListSortPreset(
                forKey: Keys.groupedListSortPreset,
                default: .styleOrder
            )
            flatListSortPreset = Self.loadListSortPreset(
                forKey: Keys.flatListSortPreset,
                default: .byName
            )
        }
        showLibraryCounters = defaults.object(forKey: Keys.showLibraryCounters) == nil
            ? true
            : defaults.bool(forKey: Keys.showLibraryCounters)

        showIgnoredFonts = defaults.bool(forKey: Keys.showIgnoredFonts)
        showMetadataWarnings = defaults.object(forKey: Keys.showMetadataWarnings) == nil
            ? true
            : defaults.bool(forKey: Keys.showMetadataWarnings)
        if defaults.object(forKey: Keys.excludeIgnoredFontsFromIndex) == nil {
            excludeIgnoredFontsFromIndex = true
        } else {
            excludeIgnoredFontsFromIndex = defaults.bool(forKey: Keys.excludeIgnoredFontsFromIndex)
        }
        suppressExcludeFromIndexConfirmation = defaults.bool(forKey: Keys.suppressExcludeFromIndexConfirmation)
    }

    func resetExcludeFromIndexConfirmation() {
        suppressExcludeFromIndexConfirmation = false
    }

    /// One entry per column; Name stays first when present.
    static func dedupedColumnOrder(_ order: [FontListColumn]) -> [FontListColumn] {
        var seen = Set<FontListColumn>()
        var result: [FontListColumn] = []
        for column in order {
            guard seen.insert(column).inserted else { continue }
            result.append(column)
        }
        if let nameIndex = result.firstIndex(of: .name), nameIndex != 0 {
            result.removeAll { $0 == .name }
            result.insert(.name, at: 0)
        }
        return result
    }

    func columnWidth(for column: FontListColumn) -> CGFloat {
        column.resolvedWidth(stored: listColumnWidths[column.rawValue])
    }

    func setColumnWidth(_ column: FontListColumn, width: CGFloat) {
        let value = min(column.maxWidth, max(column.minWidth, width))
        let key = column.rawValue
        // Column resize runs during layout; defer so SwiftUI does not warn about publishing in view updates.
        Task { @MainActor in
            listColumnWidths[key] = value
        }
    }

    func resetListColumnWidths() {
        listColumnWidths = [:]
    }

    func resetListColumnsToDefault() {
        visibleListColumns = FontListColumn.defaultVisible
        listColumnOrder = FontListColumn.allCases
        listRowDensity = .compact
        groupedListSortPreset = .styleOrder
        flatListSortPreset = .byName
        resetListColumnWidths()
    }

    private static func loadListSortPreset(forKey key: String, default defaultValue: FontListSortPreset) -> FontListSortPreset {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let preset = FontListSortPreset(rawValue: raw) else {
            return defaultValue
        }
        return preset
    }

    func resetInspectorFieldsToDefault() {
        visibleInspectorFields = InspectorField.defaultVisible
    }

    func setListColumnVisible(_ column: FontListColumn, visible: Bool) {
        guard !column.isRequired else { return }
        if visible {
            if !visibleListColumns.contains(column) {
                visibleListColumns.append(column)
            }
        } else {
            visibleListColumns.removeAll { $0 == column }
        }
    }

    /// Adopts column order from the AppKit outline after header drag (`tableColumns` sequence).
    func adoptListColumnOrder(fromTableColumns tableColumns: [NSTableColumn]) {
        var order: [FontListColumn] = []
        var seen = Set<FontListColumn>()
        for tableColumn in tableColumns {
            guard let column = FontListColumn(rawValue: tableColumn.identifier.rawValue),
                  seen.insert(column).inserted else { continue }
            order.append(column)
        }
        for column in FontListColumn.allCases where !seen.contains(column) {
            order.append(column)
        }
        listColumnOrder = Self.dedupedColumnOrder(order)
    }

    /// Reorders columns in Font Table settings (Name row is locked first).
    func moveListColumn(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = listColumnOrder
        order.move(fromOffsets: source, toOffset: destination)
        if let nameIndex = order.firstIndex(of: .name), nameIndex != 0 {
            order.removeAll { $0 == .name }
            order.insert(.name, at: 0)
        }
        listColumnOrder = order
        syncVisibleColumnsToOrder()
    }

    func isListColumnVisible(_ column: FontListColumn) -> Bool {
        column == .name || visibleListColumns.contains(column)
    }

    /// Data columns for `Table`, in master order: visible first, then hidden (for header customization).
    var orderedFlatTableColumns: [FontListColumn] {
        let visibleSet = Set(visibleListColumns)
        let dataColumns = listColumnOrder.filter { $0 != .name }
        let visible = dataColumns.filter { visibleSet.contains($0) }
        let hidden = dataColumns.filter { !visibleSet.contains($0) }
        return visible + hidden
    }

    private func syncVisibleColumnsToOrder() {
        let visibleSet = Set(visibleListColumns)
        visibleListColumns = listColumnOrder.filter { visibleSet.contains($0) || $0 == .name }
    }

    private func persistListColumnOrder() {
        let raw = listColumnOrder.map(\.rawValue)
        UserDefaults.standard.set(raw, forKey: Keys.listColumnOrder)
        syncVisibleColumnsToOrder()
    }

    private static func loadListColumnOrder() -> [FontListColumn] {
        loadOrderedPreferences(
            key: Keys.listColumnOrder,
            defaultOrder: FontListColumn.allCases,
            allCases: FontListColumn.allCases
        )
    }

    func setInspectorFieldVisible(_ field: InspectorField, visible: Bool) {
        if visible {
            if !visibleInspectorFields.contains(field) {
                visibleInspectorFields.append(field)
            }
        } else {
            visibleInspectorFields.removeAll { $0 == field }
        }
    }

    private static func loadColumns() -> [FontListColumn] {
        loadOrderedPreferences(
            key: Keys.visibleListColumns,
            defaultOrder: FontListColumn.defaultVisible,
            allCases: FontListColumn.allCases
        )
    }

    private static func loadInspectorFields() -> [InspectorField] {
        loadOrderedPreferences(
            key: Keys.visibleInspectorFields,
            defaultOrder: InspectorField.defaultVisible,
            allCases: InspectorField.allCases
        )
    }

    private static func loadOrderedPreferences<Item: CaseIterable & RawRepresentable & Hashable>(
        key: String,
        defaultOrder: [Item],
        allCases: [Item]
    ) -> [Item] where Item.RawValue == String {
        guard let saved = UserDefaults.standard.array(forKey: key) as? [String], !saved.isEmpty else {
            return defaultOrder
        }
        var result: [Item] = []
        let lookup = Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0) })
        for raw in saved {
            if let item = lookup[raw], !result.contains(item) {
                result.append(item)
            }
        }
        for item in defaultOrder where !result.contains(item) {
            result.append(item)
        }
        return result
    }

    private func persistColumnPreferences() {
        let raw = visibleListColumns.map(\.rawValue)
        UserDefaults.standard.set(raw, forKey: Keys.visibleListColumns)
    }

    private func persistInspectorPreferences() {
        let raw = visibleInspectorFields.map(\.rawValue)
        UserDefaults.standard.set(raw, forKey: Keys.visibleInspectorFields)
    }

    private func persistListColumnWidths() {
        let encoded = listColumnWidths.mapValues { Double($0) }
        UserDefaults.standard.set(encoded, forKey: Keys.listColumnWidths)
    }

    private static func loadListColumnWidths() -> [String: CGFloat] {
        guard let dict = UserDefaults.standard.dictionary(forKey: Keys.listColumnWidths) as? [String: Double] else {
            return [:]
        }
        return dict.mapValues { CGFloat($0) }
    }

    private func persistImportFormats() {
        let d = UserDefaults.standard
        d.set(importFormats.openType, forKey: Keys.importOpenType)
        d.set(importFormats.trueType, forKey: Keys.importTrueType)
        d.set(importFormats.webFonts, forKey: Keys.importWebFonts)
    }

    /// Default location for brand-new installs.
    static var defaultVaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("FontVault", isDirectory: true)
    }

    func useDefaultVaultLocation() {
        vaultRootURL = Self.defaultVaultURL
    }

    func revealVaultInFinder() {
        guard let url = vaultRootURL else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    var lastCatalogOptimizationDate: Date? {
        let interval = UserDefaults.standard.double(forKey: Keys.lastCatalogOptimization)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func recordCatalogOptimization() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastCatalogOptimization)
    }

    var importMenuTitle: String {
        organizesVaultFiles ? "Import Fonts…" : "Add Fonts to Vault…"
    }

    var importToolbarTitle: String {
        organizesVaultFiles ? "Import Fonts" : "Add Fonts to Vault"
    }

    var catalogScanMenuTitle: String {
        organizesVaultFiles ? "Rebuild Catalog…" : "Scan Vault for Changes…"
    }

    var catalogScanToolbarTitle: String {
        organizesVaultFiles ? "Rebuild Catalog" : "Scan Vault"
    }

    var catalogScanProgressTitle: String {
        organizesVaultFiles ? "Rebuilding catalog…" : "Scanning vault for changes…"
    }

    var catalogScanCompleteTitle: String {
        organizesVaultFiles ? "Rebuild complete" : "Scan complete"
    }

    var addFontsStatusNudge: String {
        "You manage files in the vault folder — add or remove fonts in Finder, then use \(catalogScanMenuTitle.replacingOccurrences(of: "…", with: "")) to update the font table."
    }

    var vaultOrganizationExplanation: String {
        organizesVaultFiles
            ? VaultOrganizationHelp.managedExplanation
            : VaultOrganizationHelp.userManagedExplanation
    }
}
