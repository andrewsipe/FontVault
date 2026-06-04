import AppKit
import Foundation
import UniformTypeIdentifiers

enum VaultBrowserMode: Hashable {
    case allFonts
    case duplicates
}

@MainActor
final class AppState: ObservableObject {
    let settings: VaultSettings
    let coordinator: VaultCoordinator

    let selectionDisplay = ListSelectionDisplay()

    /// FEX-style modal progress (large imports and catalog rebuilds).
    @Published var importProgressSession: ImportProgressSession?
    private var importProgressContinuation: CheckedContinuation<Void, Never>?

    init() {
        let settings = VaultSettings.shared
        self.settings = settings
        self.coordinator = VaultCoordinator(settings: settings)
        coordinator.onImportProgressState = { [weak self] state in
            self?.updateProgressSession(state, operation: .importFonts)
        }
        coordinator.onCatalogProgressState = { [weak self] state in
            self?.updateProgressSession(state, operation: .rebuildCatalog)
        }
        coordinator.onCleanProgressState = { [weak self] state in
            self?.updateProgressSession(state, operation: .cleanVault)
        }
        coordinator.onReorganizeProgressState = { [weak self] state in
            self?.updateProgressSession(state, operation: .reorganizeVault)
        }
        settings.onListSortPresetChanged = { [weak self] in
            self?.applyDefaultListSortIfUsingPreset()
            self?.scheduleRefreshList()
        }
    }

    private func updateProgressSession(_ state: ImportProgressState?, operation: ModalProgressOperation) {
        guard let state else {
            importProgressSession = nil
            return
        }
        if var session = importProgressSession, session.operation == operation {
            session.state = state
            importProgressSession = session
        } else {
            importProgressSession = ImportProgressSession(operation: operation, state: state)
        }
    }

    func cancelImportInProgress() {
        guard importProgressSession?.state.isComplete != true else {
            dismissImportProgress()
            return
        }
        coordinator.requestImportCancellation()
        importProgressSession = nil
    }

    func cancelCatalogRebuildInProgress() {
        guard importProgressSession?.state.isComplete != true else {
            dismissImportProgress()
            return
        }
        coordinator.requestCatalogCancellation()
        importProgressSession = nil
    }

    func cancelReorganizeInProgress() {
        guard importProgressSession?.state.isComplete != true else {
            dismissImportProgress()
            return
        }
        coordinator.requestReorganizeCancellation()
        importProgressSession = nil
    }

    func dismissImportProgress() {
        importProgressSession = nil
        importProgressContinuation?.resume()
        importProgressContinuation = nil
    }

    private func waitForProgressDismissalIfNeeded() async {
        guard coordinator.importUsedProgressPanel
            || coordinator.catalogUsedProgressPanel
            || coordinator.cleanUsedProgressPanel
            || coordinator.reorganizeUsedProgressPanel else { return }
        await withCheckedContinuation { continuation in
            if importProgressSession == nil {
                continuation.resume()
                return
            }
            importProgressContinuation = continuation
        }
    }

    /// Flat list window (paged SQL paths); grouped browse uses `familySummaries` instead.
    @Published private(set) var flatRowPaths: [String] = []
    /// Fonts matching the current sidebar filter, search, and format (font table scope).
    @Published var totalCount: Int = 0
    /// Active (non-excluded) fonts in the catalog (sidebar “All fonts”).
    @Published private(set) var catalogFontCount: Int = 0
    @Published private(set) var excludedFontCount: Int = 0

    static let flatPageSize = 2000
    /// Deep-select confirmation threshold (⇧⌘A).
    static let deepSelectConfirmThreshold = 10_000
    @Published var searchText: String = ""
    @Published var formatFilter: String? = nil
    /// Per-extension font counts in the vault (unfiltered; drives sidebar format list).
    @Published private(set) var vaultFormatCounts: [String: Int] = [:]
    @Published private(set) var variableFontCount: Int = 0
    @Published var sortColumn: String = "fullName"
    @Published var sortAscending: Bool = true
    @Published var groupByFamily: Bool = true {
        didSet {
            guard groupByFamily != oldValue else { return }
            applyDefaultListSort()
            scheduleRefreshList()
        }
    }
    /// Families collapsed in the grouped list (default: all expanded).
    @Published var collapsedFamilies: Set<String> = [] {
        didSet {
            guard collapsedFamilies != oldValue else { return }
            scheduleRebuildDisplayedFontPaths()
        }
    }
    /// Multi-selection of font rows (vault paths); ⌘/⇧ multi-select.
    @Published var selectedVaultPaths: Set<String> = [] {
        didSet {
            guard selectedVaultPaths != oldValue else { return }
            refreshSelectionCache()
        }
    }
    /// Multi-selection of family header rows (works when families are collapsed).
    @Published var selectedFamilyIDs: Set<String> = [] {
        didSet {
            guard selectedFamilyIDs != oldValue else { return }
            refreshSelectionCache()
        }
    }
    /// Anchor for ⇧-click range selection (family or font row).
    private var selectionAnchorRow: FontListSelectionRow?
    /// True while the user is dragging font files out of the list (suppresses import drop UI).
    @Published var isExportDragInProgress = false
    /// Temp drag staging directory (family folders); removed after export drag ends.
    private var exportDragStagingRoot: URL?
    @Published var showInspector: Bool = false
    /// Font metadata sheet presented by double-clicking a font row in the table.
    @Published var prefersSidebarVisible: Bool = true
    /// Incremented to focus the main window search field (Edit → Find, ⌘F).
    @Published private(set) var searchFocusRequest = 0
    /// AppKit font list coordinator (set when the outline view is active).
    weak var fontListCoordinator: FontListOutlineCoordinator?
    @Published var sidebarSelection: SidebarItem = .allFonts
    @Published var settingsTab: SettingsTab = .general
    /// Bumped when AppKit code needs the SwiftUI Settings window (column menu, inspector).
    @Published private(set) var settingsOpenRequest: SettingsOpenRequest?
    @Published var statusMessage: String = ""
    @Published var lastImportSummary: String?
    @Published private(set) var lastImportReport: ImportReport?
    @Published var importReportPresentation: ImportReport?
    @Published var browserMode: VaultBrowserMode = .allFonts
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var duplicateKeeperByHash: [String: String] = [:]
    @Published var isScanningDuplicates = false
    @Published var duplicateScanCompleted = false
    /// SQL estimate until a full duplicate scan completes.
    @Published private(set) var duplicateQuickCount: Int = 0

    @Published private(set) var launchPhase: LaunchPhase = .idle
    @Published private(set) var launchStatusMessage: String = ""

    private var launchTask: Task<Void, Never>?

    /// Extra catalog rows beyond one copy per SHA-256 group.
    var duplicateFileCount: Int {
        if duplicateScanCompleted {
            return duplicateGroups.reduce(0) { $0 + max(0, $1.copyCount - 1) }
        }
        return duplicateQuickCount
    }

    /// SQL family index for grouped browse (lightweight).
    @Published private(set) var familySummaries: [FontFamilySummary] = []
    /// Vault paths per family after lazy load (for ⇧-range and deep selection UI).
    private var loadedFamilyVaultPaths: [String: [String]] = [:]

    /// Family sections for outline (summaries + any loaded child fonts).
    var familySections: [FontFamilySection] {
        familySummaries.map { summary in
            let paths = loadedFamilyVaultPaths[summary.id] ?? []
            let fonts = catalogFonts(forVaultPaths: paths)
            return summary.asSection(with: fonts)
        }
    }

    /// Resolves catalog rows for vault paths (memory cache, then SQLite).
    func catalogFonts(forVaultPaths paths: [String]) -> [FontRecord] {
        paths.compactMap { catalogFont(forVaultPath: $0) }
    }
    /// Visible font row order for ⇧-click range selection (expanded families only).
    @Published private(set) var displayedFontPaths: [String] = []
    /// Family header order in the outline (always all families).
    @Published private(set) var displayedFamilyIDs: [String] = []
    /// Visible outline rows in display order (families + expanded children) for ⇧-click range.
    @Published private(set) var displayedSelectionRows: [FontListSelectionRow] = []
    /// Bumped when list data / sort / filters change (AppKit list reload trigger; not selection).
    @Published private(set) var listDataRevision: UInt = 0

    private var fontsByVaultPath: [String: FontRecord] = [:]
    private var cachedSelectedFonts: [FontRecord] = []
    private var cachedPrimarySelectedFont: FontRecord?
    private var cachedSelectionSummary: String = ""
    private var cachedSelectionGlance: String?
    private var refreshScheduled = false
    private var displayedPathsRefreshScheduled = false
    private var flatPageAppendScheduled = false

    /// Fonts in the current list that are selected.
    var selectedFonts: [FontRecord] { cachedSelectedFonts }

    /// Inspector detail when exactly one row is selected.
    var primarySelectedFont: FontRecord? { cachedPrimarySelectedFont }

    var selectionSummary: String { cachedSelectionSummary }

    /// Status bar zone 1 — visible fonts in the current browse scope.
    var statusBarVisibleCount: StatusBarVisibleCount {
        StatusBarCopy.visibleCount(
            browserMode: browserMode,
            totalCount: totalCount,
            flatLoadedCount: flatRowPaths.count,
            groupByFamily: groupByFamily,
            catalogFontCount: catalogFontCount,
            familySummaryCount: familySummaries.count,
            sidebarSelection: sidebarSelection,
            sidebarFormats: sidebarFormats,
            searchText: searchText,
            formatFilter: formatFilter,
            showLibraryCounters: settings.showLibraryCounters,
            excludedFontCount: excludedFontCount,
            showIgnoredFonts: settings.showIgnoredFonts
        )
    }

    /// Status bar zone 2 — compact selection summary (`nil` when nothing selected).
    var statusBarSelectionGlance: String? { cachedSelectionGlance }

    var showsExcludedFontsSmartFilterRow: Bool {
        excludedFontCount > 0 && settings.showIgnoredFonts
    }

    func tableBrowseQuery() -> FontTableBrowseQuery {
        FontTableBrowseQuery(
            search: searchText,
            format: formatFilter,
            tableScope: tableBrowseScope,
            showIgnoredFonts: settings.showIgnoredFonts
        )
    }

    private var tableBrowseScope: FontTableBrowseScope {
        switch sidebarSelection {
        case .smartFilter(.excludedFonts):
            return .excludedFontsOnly
        default:
            return .allFonts
        }
    }

    var canExcludeSelectionFromIndex: Bool {
        browserMode == .allFonts && selectedFonts.contains { !$0.excludedFromIndex }
    }

    var canIncludeSelectionInIndex: Bool {
        browserMode == .allFonts && selectedFonts.contains { $0.excludedFromIndex }
    }

    /// Sidebar format rows (badge + count), only formats present in the catalog.
    var sidebarFormats: [(format: FontFormat, filterKey: String, count: Int)] {
        var aggregated: [FontFormat: Int] = [:]
        for (ext, count) in vaultFormatCounts {
            let format = FontFormat.from(pathExtension: ext)
            guard format != .mixed, format != .unknown else { continue }
            aggregated[format, default: 0] += count
        }
        return Self.sidebarFormatDisplayOrder.compactMap { format in
            guard let count = aggregated[format], count > 0 else { return nil }
            return (format, format.rawValue, count)
        }
    }

    private static let sidebarFormatDisplayOrder: [FontFormat] = [.otf, .ttf, .ttc, .woff, .woff2]

    /// Starts the FEX-style launch gate (idempotent while in progress or ready).
    func startLaunch() {
        guard settings.hasCompletedOnboarding, settings.vaultRootURL != nil else { return }
        guard !launchPhase.isInProgress else { return }
        if launchPhase.isReady { return }

        launchTask?.cancel()
        launchTask = Task { @MainActor in
            await runLaunchSequence()
        }
    }

    func retryLaunch() {
        launchTask?.cancel()
        launchPhase = .idle
        startLaunch()
    }

    private func runLaunchSequence() async {
        launchPhase = .openingCatalog
        launchStatusMessage = "Opening catalog…"
        await Task.yield()

        do {
            try coordinator.reloadCatalog()

            launchPhase = .preparingList
            launchStatusMessage = "Preparing font list…"
            await Task.yield()

            try refreshListForLaunch()

            if needsCatalogMetadataRefresh {
                let scan = settings.catalogScanMenuTitle.replacingOccurrences(of: "…", with: "")
                statusMessage =
                    "Font metadata may be outdated — use \(scan) (Vault menu or toolbar, ⇧⌘R) to refresh OpenType fields."
            }

            launchPhase = .ready
            launchStatusMessage = ""
            schedulePostLaunchTasks()
        } catch {
            let message = error.localizedDescription
            launchPhase = .failed(message)
            launchStatusMessage = message
            statusMessage = message
        }
    }

    private func schedulePostLaunchTasks() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard launchPhase.isReady else { return }
            await refreshDuplicateQuickCount()
            preloadFirstVisibleFlatRowsIfNeeded()
        }
    }

    private func refreshDuplicateQuickCount() async {
        guard let catalog = coordinator.catalog else {
            duplicateQuickCount = 0
            return
        }
        duplicateQuickCount = (try? catalog.duplicateExtraFileCount()) ?? 0
    }

    /// After launch: cache records for the first screen of flat rows (launch loads paths only).
    private func preloadFirstVisibleFlatRowsIfNeeded() {
        guard !groupByFamily, !flatRowPaths.isEmpty else { return }
        let paths = Array(flatRowPaths.prefix(40))
        preloadCatalogFonts(vaultPaths: paths)
        listDataRevision &+= 1
    }

    private func invalidateDuplicateScanState() {
        duplicateScanCompleted = false
        duplicateGroups = []
        duplicateKeeperByHash = [:]
    }

    /// True when the catalog was built before the latest metadata schema / reader.
    private var needsCatalogMetadataRefresh: Bool {
        let stored = UserDefaults.standard.integer(forKey: VaultSettings.Keys.catalogMetadataVersion)
        return stored < VaultSettings.currentCatalogMetadataVersion
    }

    func completeOnboarding(vaultURL: URL) {
        settings.vaultRootURL = vaultURL
        settings.hasCompletedOnboarding = true
        try? FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        statusMessage = "Vault ready at \(vaultURL.path)"
        launchPhase = .idle
        startLaunch()
    }

    func refreshList(preloadFirstPage: Bool = false) {
        do {
            try refreshListCore(preloadFirstPage: preloadFirstPage, collapseAllFamiliesOnLaunch: false)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Launch browse load: paths only for flat mode; collapse all families to avoid N+1 child fetches.
    private func refreshListForLaunch() throws {
        applyDefaultListSort()
        try refreshListCore(preloadFirstPage: false, collapseAllFamiliesOnLaunch: groupByFamily)
    }

    /// Applies the grouped or flat default sort preset from Settings.
    func applyDefaultListSort() {
        let preset = groupByFamily ? settings.groupedListSortPreset : settings.flatListSortPreset
        sortColumn = preset.sortColumn
        sortAscending = true
    }

    /// Re-applies layout defaults when the user is still on a preset sort (not a column-header override).
    func applyDefaultListSortIfUsingPreset() {
        guard FontListSortPreset.isPresetSortColumn(sortColumn) else { return }
        applyDefaultListSort()
    }

    func resetListSortToDefault() {
        applyDefaultListSort()
        scheduleRefreshList()
    }

    private func refreshListCore(preloadFirstPage: Bool, collapseAllFamiliesOnLaunch: Bool) throws {
        guard let catalog = coordinator.catalog else {
            flatRowPaths = []
            familySummaries = []
            totalCount = 0
            catalogFontCount = 0
            excludedFontCount = 0
            vaultFormatCounts = [:]
            variableFontCount = 0
            loadedFamilyVaultPaths = [:]
            fontsByVaultPath = [:]
            rebuildListCaches()
            return
        }

        vaultFormatCounts = (try? catalog.formatCounts(activeOnly: true)) ?? [:]
        variableFontCount = (try? catalog.variableFontCount(activeOnly: true)) ?? 0
        catalogFontCount = try catalog.activeFontCount()
        excludedFontCount = try catalog.excludedFontCount()
        normalizeSidebarSelectionForExclusionState()
        let browseQuery = tableBrowseQuery()
        totalCount = try catalog.filteredFontCount(query: browseQuery)
        loadedFamilyVaultPaths = [:]
        fontsByVaultPath = [:]

        if groupByFamily {
            flatRowPaths = []
            familySummaries = try catalog.fetchFamilySummaries(
                query: browseQuery,
                sortColumn: sortColumn,
                ascending: sortAscending
            )
            if collapseAllFamiliesOnLaunch {
                collapsedFamilies = Set(familySummaries.map(\.id))
            }
        } else {
            familySummaries = []
            flatRowPaths = try catalog.fetchOrderedVaultPaths(
                query: browseQuery,
                sortColumn: sortColumn,
                ascending: sortAscending,
                limit: Self.flatPageSize,
                offset: 0
            )
            if preloadFirstPage {
                preloadCatalogFonts(vaultPaths: flatRowPaths)
            }
        }

        rebuildListCaches()

        let visiblePaths: Set<String>
        if groupByFamily {
            if selectedVaultPaths.isEmpty {
                visiblePaths = []
            } else {
                visiblePaths = Set(
                    try catalog.fetchAllFilteredVaultPaths(
                        query: tableBrowseQuery(),
                        sortColumn: sortColumn,
                        ascending: sortAscending
                    )
                )
            }
        } else {
            visiblePaths = Set(flatRowPaths)
        }
        let prunedPaths = selectedVaultPaths.intersection(visiblePaths)
        if prunedPaths != selectedVaultPaths {
            selectedVaultPaths = prunedPaths
        }
        let visibleFamilies = Set(familySummaries.map(\.id))
        let prunedFamilies = selectedFamilyIDs.intersection(visibleFamilies)
        if prunedFamilies != selectedFamilyIDs {
            selectedFamilyIDs = prunedFamilies
        }
    }

    /// Appends the next flat-list page when the user scrolls near the end.
    func appendFlatPageIfNeeded(currentRow: Int) {
        guard !groupByFamily,
              coordinator.catalog != nil,
              flatRowPaths.count < totalCount,
              currentRow >= flatRowPaths.count - 40,
              !flatPageAppendScheduled else { return }

        flatPageAppendScheduled = true
        Task { @MainActor in
            defer { self.flatPageAppendScheduled = false }
            guard !self.groupByFamily,
                  let catalog = self.coordinator.catalog,
                  self.flatRowPaths.count < self.totalCount else { return }
            do {
                let more = try catalog.fetchOrderedVaultPaths(
                    query: self.tableBrowseQuery(),
                    sortColumn: self.sortColumn,
                    ascending: self.sortAscending,
                    limit: Self.flatPageSize,
                    offset: self.flatRowPaths.count
                )
                guard !more.isEmpty else { return }
                self.preloadCatalogFonts(vaultPaths: more)
                self.flatRowPaths.append(contentsOf: more)
                self.rebuildDisplayedFontPaths()
            } catch {
                self.statusMessage = error.localizedDescription
            }
        }
    }

    /// Called by the outline when a family's styles are loaded from SQL.
    func registerLoadedFamilyFonts(familyID: String, fonts: [FontRecord]) {
        loadedFamilyVaultPaths[familyID] = fonts.map(\.vaultPath)
        for font in fonts {
            fontsByVaultPath[font.vaultPath] = font
        }
        scheduleRebuildDisplayedFontPaths()
    }

    /// Defers display-path cache updates (called from AppKit `viewFor` / expansion callbacks).
    func scheduleRebuildDisplayedFontPaths() {
        guard !displayedPathsRefreshScheduled else { return }
        displayedPathsRefreshScheduled = true
        Task { @MainActor in
            self.displayedPathsRefreshScheduled = false
            self.rebuildDisplayedFontPaths()
        }
    }

    func catalogFont(forVaultPath path: String) -> FontRecord? {
        if let cached = fontsByVaultPath[path] { return cached }
        guard let catalog = coordinator.catalog,
              let record = try? catalog.fetchRecord(vaultPath: path) else { return nil }
        fontsByVaultPath[path] = record
        return record
    }

    /// Preload catalog rows for flat-list paths (one query per page, not per cell).
    func preloadCatalogFonts(vaultPaths: [String]) {
        guard !vaultPaths.isEmpty, let catalog = coordinator.catalog else { return }
        let missing = vaultPaths.filter { fontsByVaultPath[$0] == nil }
        guard !missing.isEmpty else { return }
        guard let records = try? catalog.fetchRecords(vaultPaths: missing) else { return }
        for record in records {
            fontsByVaultPath[record.vaultPath] = record
        }
        listDataRevision &+= 1
    }

    private func rebuildListCaches() {
        listDataRevision &+= 1
        rebuildDisplayedFontPaths()
        refreshSelectionCache()
    }

    private func rebuildDisplayedFontPaths() {
        if groupByFamily {
            displayedFamilyIDs = familySummaries.map(\.id)
            var paths: [String] = []
            var rows: [FontListSelectionRow] = []
            for summary in familySummaries {
                rows.append(.family(summary.id))
                guard !collapsedFamilies.contains(summary.id) else { continue }
                let childPaths = loadedFamilyVaultPaths[summary.id] ?? []
                paths.append(contentsOf: childPaths)
                rows.append(contentsOf: childPaths.map { .font($0) })
            }
            displayedFontPaths = paths
            displayedSelectionRows = rows
        } else {
            displayedFamilyIDs = []
            displayedFontPaths = flatRowPaths
            displayedSelectionRows = flatRowPaths.map { .font($0) }
        }
    }

    func fonts(inFamilies familyIDs: Set<String>) -> [FontRecord] {
        guard !familyIDs.isEmpty, let catalog = coordinator.catalog else { return [] }
        return (try? catalog.fetchFontsForFamilies(
            familyKeys: familyIDs,
            query: tableBrowseQuery(),
            sortColumn: sortColumn,
            ascending: sortAscending
        )) ?? []
    }

    private func refreshSelectionCache() {
        let selected = fontsForExportSelection()

        cachedSelectedFonts = selected

        if selected.isEmpty {
            cachedSelectionSummary = ""
            cachedSelectionGlance = nil
            cachedPrimarySelectedFont = nil
            selectionDisplay.update(summary: "", primaryFont: nil, selectedFonts: [])
            selectionDisplay.updateSelectionStatusDetail(nil)
            return
        }

        let totalSize = selected.reduce(Int64(0)) { $0 + $1.fileSize }
        cachedSelectionGlance = StatusBarCopy.selectionGlance(
            fontCount: selected.count,
            totalByteCount: totalSize
        )

        let familyCount = selectedFamilyIDs.count
        let looseFontCount = selectedVaultPaths.filter { path in
            guard let font = fontsByVaultPath[path] else { return false }
            return !selectedFamilyIDs.contains(FontListGrouping.familyKey(for: font))
        }.count

        if familyCount > 0 && looseFontCount == 0 && selected.count > familyCount {
            cachedPrimarySelectedFont = nil
            let sizeText = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            let familyWord = familyCount == 1 ? "family" : "families"
            cachedSelectionSummary =
                "\(familyCount) \(familyWord) selected (\(selected.count) fonts, \(sizeText))"
            selectionDisplay.update(
                summary: cachedSelectionSummary,
                primaryFont: nil,
                selectedFonts: cachedSelectedFonts
            )
            selectionDisplay.updateSelectionStatusDetail(nil)
            return
        }

        if familyCount == 0, selectedVaultPaths.count == 1, let font = selected.first {
            cachedPrimarySelectedFont = font
            cachedSelectionSummary = "Selected: \(font.fullName)"
            let detailColumn = fontListCoordinator?.statusDetailColumnForSelection() ?? .name
            selectionDisplay.update(
                summary: cachedSelectionSummary,
                primaryFont: font,
                selectedFonts: cachedSelectedFonts
            )
            selectionDisplay.updateSelectionStatusDetail(
                ListStatusDetail.forFont(font, column: detailColumn, source: .selection)
            )
            return
        }

        cachedPrimarySelectedFont = nil
        let sizeText = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        if familyCount > 0 && looseFontCount > 0 {
            cachedSelectionSummary =
                "\(familyCount) families + \(looseFontCount) fonts (\(selected.count) total, \(sizeText))"
        } else {
            cachedSelectionSummary = "\(selected.count) fonts selected (\(sizeText))"
        }

        selectionDisplay.update(
            summary: cachedSelectionSummary,
            primaryFont: cachedPrimarySelectedFont,
            selectedFonts: cachedSelectedFonts
        )
        selectionDisplay.updateSelectionStatusDetail(nil)
    }

    /// Fonts to export/drag given current row selection (FEX rules).
    func fontsForExportSelection() -> [FontRecord] {
        guard let catalog = coordinator.catalog else { return [] }
        var byPath: [String: FontRecord] = [:]

        if !selectedFamilyIDs.isEmpty {
            let familyFonts = (try? catalog.fetchFontsForFamilies(
                familyKeys: selectedFamilyIDs,
                query: tableBrowseQuery(),
                sortColumn: sortColumn,
                ascending: sortAscending
            )) ?? []
            for font in familyFonts {
                byPath[font.vaultPath] = font
            }
        }

        for path in selectedVaultPaths {
            if let cached = fontsByVaultPath[path] {
                let familyID = FontListGrouping.familyKey(for: cached)
                if selectedFamilyIDs.contains(familyID) { continue }
                byPath[path] = cached
            } else if let fetched = try? catalog.fetchRecord(vaultPath: path) {
                let familyID = FontListGrouping.familyKey(for: fetched)
                if selectedFamilyIDs.contains(familyID) { continue }
                byPath[path] = fetched
                fontsByVaultPath[path] = fetched
            }
        }

        return Array(byPath.values)
    }

    func toggleFamilyExpanded(_ familyKey: String) {
        if collapsedFamilies.contains(familyKey) {
            collapsedFamilies.remove(familyKey)
        } else {
            collapsedFamilies.insert(familyKey)
        }
    }

    func expandAllFamilies() {
        collapsedFamilies.removeAll()
    }

    func collapseAllFamilies() {
        collapsedFamilies = Set(familySummaries.map(\.id))
    }

    /// Refreshes the font list on the next run loop (avoids SwiftUI “Publishing changes from within view updates”).
    func scheduleRefreshList() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor in
            self.refreshScheduled = false
            self.refreshList()
        }
    }

    func pickVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose your font vault folder"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.vaultRootURL = url
            launchPhase = .idle
            startLaunch()
        }
    }

    // MARK: - Import (File → Import, toolbar, drag-and-drop)

    func presentImportPanel() {
        guard ensureVaultConfigured() else { return }
        guard settings.organizesVaultFiles else {
            presentAddFontsToVault()
            return
        }

        guard let pick = FontImportPanel.pickFiles(
            initialFormats: settings.importFormats,
            initialOperation: settings.importOperation
        ) else { return }

        // One-shot formats and copy/move for this import only; Settings defaults are unchanged.
        Task {
            await runImport(
                urls: pick.urls,
                formats: pick.formats,
                move: pick.operation == .move
            )
        }
    }

    func importDroppedURLs(_ urls: [URL]) async {
        guard ensureVaultConfigured() else { return }
        if isExportDragInProgress { return }

        guard settings.organizesVaultFiles else {
            presentAddFontsToVault()
            return
        }

        let external = urls.filter { !isURLInsideVault($0) }
        guard !external.isEmpty else { return }

        await runImport(
            urls: external,
            formats: settings.importFormats,
            move: settings.importOperation == .move
        )
    }

    /// Opens the vault folder in Finder; used when the user manages files on disk (organization off).
    func presentAddFontsToVault() {
        guard ensureVaultConfigured() else { return }
        settings.revealVaultInFinder()
        statusMessage = settings.addFontsStatusNudge
    }

    /// Reject drops of vault files onto the app (export drags, internal paths).
    func isURLInsideVault(_ url: URL) -> Bool {
        guard let root = settings.vaultRootURL?.standardizedFileURL else { return false }
        let path = url.standardizedFileURL.path
        return path == root.path || path.hasPrefix(root.path + "/")
    }

    private func runImport(urls: [URL], formats: ImportFormatOptions, move: Bool) async {
        guard !urls.isEmpty else { return }

        do {
            let result = try await coordinator.importURLs(urls, move: move, formats: formats)
            let report = result.makeReport(move: move)
            lastImportReport = report
            lastImportSummary = report.summaryLine

            // Refresh before the completion sheet so the table is populated behind it.
            refreshList()
            refreshDuplicateSummary()

            if coordinator.importWasCancelled {
                importProgressSession = nil
                lastImportReport = nil
                statusMessage = "Import cancelled — no fonts were added."
            } else if coordinator.importUsedProgressPanel {
                if var session = importProgressSession {
                    session.state = coordinator.importCompletionProgressState(
                        result: result,
                        move: move,
                        total: result.scanned
                    )
                    session.importReport = report
                    importProgressSession = session
                }
                statusMessage = lastImportSummary ?? ""
                await waitForProgressDismissalIfNeeded()
            } else {
                statusMessage = lastImportSummary ?? ""
                showImportSummaryAlert(report: report)
            }
        } catch {
            importProgressSession = nil
            statusMessage = error.localizedDescription
            showErrorAlert("Import failed", error.localizedDescription)
        }
    }

    private func summaryText(for result: ImportResult, move: Bool) -> String {
        ImportResult.summaryText(for: result, move: move)
    }

    private func showImportSummaryAlert(report: ImportReport) {
        let alert = NSAlert()
        alert.messageText = report.imported > 0 ? "Import complete" : "Nothing imported"
        alert.informativeText = importSummaryInformativeText(report: report)
        alert.addButton(withTitle: "OK")
        if report.hasInspectableRows {
            alert.addButton(withTitle: AppMenuCopy.viewImportDetails)
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                presentImportReport(report)
            }
        } else {
            alert.runModal()
        }
    }

    private func importSummaryInformativeText(report: ImportReport) -> String {
        var info = report.completionAlertBody
        if report.scanned == 0 {
            info += "\n\nNo files matched the selected format filters. Enable “Web fonts” for .woff/.woff2, or OpenType/TrueType for .otf/.ttf."
        } else if report.imported == 0 && report.failedCount == 0 && !report.hasInspectableRows {
            info += "\n\nAll matching files were already in the vault (skipped)."
        }
        return info
    }

    func presentImportReport(_ report: ImportReport? = nil) {
        guard let report = report ?? lastImportReport else { return }
        importReportPresentation = report
    }

    func dismissImportReport() {
        importReportPresentation = nil
    }

    func revealImportEntryInFinder(_ entry: ImportReportEntry) {
        guard FileManager.default.fileExists(atPath: entry.sourceURL.path) else {
            showErrorAlert("File not found", "The file is no longer at:\n\(entry.sourceURL.path)")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([entry.sourceURL])
    }

    func copyImportIssueListToPasteboard(_ report: ImportReport) {
        let plain = ImportReport.issueListText(from: report)
        guard !plain.isEmpty else { return }
        let html = ImportReport.issueListHTML(from: report)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plain, forType: .string)
        if let htmlData = html.data(using: .utf8) {
            pasteboard.setData(htmlData, forType: .html)
        }
        let n = report.failed.count + report.namingFallbackEntries.count
        statusMessage = "Copied \(n) issue\(n == 1 ? "" : "s") to clipboard."
    }

    func saveImportIssueList(_ report: ImportReport) {
        let html = ImportReport.issueListHTML(from: report)
        guard !html.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = ImportReport.defaultIssueListFilename()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Saved issue report to \(url.lastPathComponent)."
        } catch {
            showErrorAlert("Could not save file", error.localizedDescription)
        }
    }

    func copyImportFailureListToPasteboard(_ report: ImportReport) {
        copyImportIssueListToPasteboard(report)
    }

    func saveImportFailureList(_ report: ImportReport) {
        saveImportIssueList(report)
    }

    private func showErrorAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func ensureVaultConfigured() -> Bool {
        guard settings.vaultRootURL != nil else {
            showErrorAlert("Vault not configured", "Choose a vault folder in onboarding or Settings (⌘,) first.")
            return false
        }
        if coordinator.catalog == nil {
            try? coordinator.reloadCatalog()
        }
        return true
    }

    func indexVault() {
        Task {
            do {
                let result = try await coordinator.indexExistingVault()
                if coordinator.catalogWasCancelled {
                    importProgressSession = nil
                    statusMessage = coordinator.indexProgress
                    return
                }

                UserDefaults.standard.set(
                    VaultSettings.currentCatalogMetadataVersion,
                    forKey: VaultSettings.Keys.catalogMetadataVersion
                )
                refreshList()
                refreshDuplicateSummary()

                if var session = importProgressSession {
                    session.state = coordinator.catalogCompletionProgressState(result: result)
                    importProgressSession = session
                }
                statusMessage = coordinator.indexProgress
                await waitForProgressDismissalIfNeeded()
            } catch {
                importProgressSession = nil
                statusMessage = error.localizedDescription
                showErrorAlert("Rebuild catalog failed", error.localizedDescription)
            }
        }
    }

    func absoluteURL(for record: FontRecord) -> URL? {
        guard let root = settings.vaultRootURL else { return nil }
        return root.appendingPathComponent(record.vaultPath)
    }

    // MARK: - Selection (FEX-style: each row independent; ⌘ toggle; ⇧ range)

    func handleListRowMouseDown(_ row: FontListSelectionRow, event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.shift) {
            applyRangeSelection(to: row, adding: flags.contains(.command))
            return
        }

        if flags.contains(.command) {
            toggleRowSelection(row)
            selectionAnchorRow = row
            return
        }

        // FEX-style: plain click on an already-selected row in a multi-selection keeps the set
        // (so you can double-click to open the inspector for all selected fonts).
        if hasMultipleSelectedRows, isRowSelected(row) {
            selectionAnchorRow = row
            return
        }

        selectOnly(row)
        selectionAnchorRow = row
    }

    private var hasMultipleSelectedRows: Bool {
        selectedFamilyIDs.count + selectedVaultPaths.count > 1
    }

    func handleFontListMouseDown(vaultPath: String, event: NSEvent) {
        handleListRowMouseDown(.font(vaultPath), event: event)
    }

    func handleFamilyListMouseDown(familyID: String, event: NSEvent) {
        handleListRowMouseDown(.family(familyID), event: event)
    }

    func isListRowSelected(_ row: FontListSelectionRow) -> Bool {
        isRowSelected(row)
    }

    private func isRowSelected(_ row: FontListSelectionRow) -> Bool {
        switch row {
        case .family(let id):
            return selectedFamilyIDs.contains(id)
        case .font(let path):
            return selectedVaultPaths.contains(path)
        }
    }

    private func selectOnly(_ row: FontListSelectionRow) {
        switch row {
        case .family(let id):
            selectedFamilyIDs = [id]
            selectedVaultPaths.removeAll()
        case .font(let path):
            selectedVaultPaths = [path]
            selectedFamilyIDs.removeAll()
        }
        selectionAnchorRow = row
    }

    private func toggleRowSelection(_ row: FontListSelectionRow) {
        switch row {
        case .family(let id):
            if selectedFamilyIDs.contains(id) {
                selectedFamilyIDs.remove(id)
            } else {
                selectedFamilyIDs.insert(id)
            }
        case .font(let path):
            if selectedVaultPaths.contains(path) {
                selectedVaultPaths.remove(path)
            } else {
                selectedVaultPaths.insert(path)
            }
        }
    }

    private func applyRangeSelection(to row: FontListSelectionRow, adding: Bool) {
        let anchor = selectionAnchorRow
            ?? displayedSelectionRows.first(where: isRowSelected)
            ?? row

        let ordered = displayedSelectionRows
        guard let anchorIndex = ordered.firstIndex(of: anchor),
              let targetIndex = ordered.firstIndex(of: row) else {
            if !adding { selectOnly(row) }
            selectionAnchorRow = row
            return
        }

        let range = ordered[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)]
        var families = adding ? selectedFamilyIDs : Set<String>()
        var paths = adding ? selectedVaultPaths : Set<String>()

        for item in range {
            switch item {
            case .family(let id):
                families.insert(id)
            case .font(let path):
                paths.insert(path)
            }
        }

        selectedFamilyIDs = families
        selectedVaultPaths = paths
        selectionAnchorRow = row
    }

    /// ⌘A — all family headers in the current filter; export resolves all styles via SQL.
    func selectAllFamiliesInFilter() {
        guard groupByFamily else {
            selectAllFontsDeepInFilter()
            return
        }
        selectedFamilyIDs = Set(familySummaries.map(\.id))
        selectedVaultPaths.removeAll()
        selectionAnchorRow = displayedSelectionRows.first { row in
            if case .family = row { return true }
            return false
        }
        refreshSelectionCache()
    }

    /// ⇧⌘A — deep select every font in the current filter (highlights families + styles).
    func selectAllFontsDeepInFilter() {
        guard let catalog = coordinator.catalog else { return }

        if totalCount > Self.deepSelectConfirmThreshold {
            let alert = NSAlert()
            alert.messageText = "Select \(totalCount) fonts?"
            alert.informativeText = "This will select every font matching the current search and filters."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Select All")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        statusMessage = "Selecting \(totalCount) fonts…"
        Task { @MainActor in
            do {
                if groupByFamily {
                    selectedFamilyIDs = Set(familySummaries.map(\.id))
                    let allFonts = try catalog.fetchFontsForFamilies(
                        familyKeys: selectedFamilyIDs,
                        query: tableBrowseQuery(),
                        sortColumn: sortColumn,
                        ascending: sortAscending
                    )
                    for font in allFonts {
                        fontsByVaultPath[font.vaultPath] = font
                    }
                    var byFamily: [String: [String]] = [:]
                    for font in allFonts {
                        let key = FontListGrouping.familyKey(for: font)
                        byFamily[key, default: []].append(font.vaultPath)
                    }
                    loadedFamilyVaultPaths = byFamily
                    collapsedFamilies.removeAll()
                    selectedVaultPaths = Set(allFonts.map(\.vaultPath))
                } else {
                    let paths = try catalog.fetchAllFilteredVaultPaths(
                        query: tableBrowseQuery(),
                        sortColumn: sortColumn,
                        ascending: sortAscending
                    )
                    selectedFamilyIDs.removeAll()
                    selectedVaultPaths = Set(paths)
                    let records = try catalog.fetchRecords(vaultPaths: paths)
                    for font in records {
                        fontsByVaultPath[font.vaultPath] = font
                    }
                }
                rebuildDisplayedFontPaths()
                listDataRevision &+= 1
                selectionAnchorRow = displayedSelectionRows.first
                refreshSelectionCache()
                statusMessage = "\(totalCount) fonts selected."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func selectAllVisible() {
        selectAllFamiliesInFilter()
    }

    func deselectAll() {
        selectedVaultPaths.removeAll()
        selectedFamilyIDs.removeAll()
        selectionAnchorRow = nil
        refreshSelectionCache()
    }

    /// Called by the AppKit list when selection changes (immediate sync for outline + inspector).
    func syncSelectionFromOutline(familyIDs: Set<String>, vaultPaths: Set<String>) {
        let familiesChanged = selectedFamilyIDs != familyIDs
        let pathsChanged = selectedVaultPaths != vaultPaths
        guard familiesChanged || pathsChanged else { return }
        if familiesChanged { selectedFamilyIDs = familyIDs }
        if pathsChanged { selectedVaultPaths = vaultPaths }
    }

    /// Builds drag pasteboard URLs (family folders or flat file) for export to Finder.
    func prepareExportDrag(for vaultPath: String) -> DragExportStaging.Plan? {
        prepareExportDrag(fonts: resolvedExportDragFonts(fallbackVaultPath: vaultPath))
    }

    /// Drag from a family header row (respects full current selection).
    func prepareExportDrag(forFamily section: FontFamilySection) -> DragExportStaging.Plan? {
        prepareExportDrag(fonts: resolvedExportDragFonts(fallbackFamilyID: section.id))
    }

    private func resolvedExportDragFonts(
        fallbackVaultPath: String? = nil,
        fallbackFamilyID: String? = nil
    ) -> [FontRecord] {
        let selected = fontsForExportSelection()
        if !selected.isEmpty { return selected }

        if let fallbackFamilyID {
            return fonts(inFamilies: [fallbackFamilyID])
        }
        if let fallbackVaultPath, let font = fontsByVaultPath[fallbackVaultPath] {
            return [font]
        }
        return []
    }

    private func prepareExportDrag(fonts: [FontRecord]) -> DragExportStaging.Plan? {
        if !isExportDragInProgress {
            clearExportDragStaging()
        }
        guard !fonts.isEmpty else { return nil }

        do {
            let plan = try DragExportStaging.prepare(
                fonts: fonts,
                mode: settings.exportLayoutMode
            ) { [weak self] font in
                self?.absoluteURL(for: font)
            } fileName: { [weak self] font in
                self?.absoluteURL(for: font)?.lastPathComponent ?? font.vaultPath
            }
            exportDragStagingRoot = plan?.stagingRoot
            return plan
        } catch {
            statusMessage = "Could not prepare export: \(error.localizedDescription)"
            return nil
        }
    }

    func clearExportDragStaging() {
        if let root = exportDragStagingRoot {
            try? FileManager.default.removeItem(at: root)
            exportDragStagingRoot = nil
        }
    }

    /// Call when an AppKit outline drag begins.
    func beginExportDragSession() {
        isExportDragInProgress = true
    }

    /// Call when the drag session ends (Finder may still be copying from staged paths).
    func endExportDragSession(operation: NSDragOperation) {
        isExportDragInProgress = false
        // Staged drag uses real file copies; allow extra time for Finder to finish reading them.
        let delay: TimeInterval = operation.contains(.copy) ? 3.0 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.clearExportDragStaging()
        }
    }

    func makeExportDragItemProvider(for vaultPath: String) -> NSItemProvider {
        guard let plan = prepareExportDrag(for: vaultPath) else {
            return NSItemProvider()
        }
        beginExportDragSession()

        let provider = NSItemProvider()
        for url in plan.dragURLs {
            provider.registerObject(url as NSURL, visibility: .all)
        }
        return provider
    }

    func openSettings(tab: SettingsTab = .general) {
        settingsTab = tab
        settingsOpenRequest = SettingsOpenRequest(tab: tab)
        NSApp.activate(ignoringOtherApps: true)
    }

    func clearSettingsOpenRequest() {
        settingsOpenRequest = nil
    }

    // MARK: - Index exclusion (Phase 2)

    func presentExcludeSelectedFromIndex() {
        guard ensureVaultConfigured(), browserMode == .allFonts else { return }
        let targets = selectedFonts.filter { !$0.excludedFromIndex }
        guard !targets.isEmpty else {
            showErrorAlert("Nothing to exclude", "Select one or more fonts that are not already excluded from the index.")
            return
        }

        let suppression = settings.suppressExcludeFromIndexConfirmation
        let confirmation = ExcludeFromIndexAlert.confirm(
            fonts: targets,
            suppressionAlreadyEnabled: suppression
        )
        guard confirmation.proceed else { return }
        if confirmation.suppressFuture {
            settings.suppressExcludeFromIndexConfirmation = true
        }

        applyIndexExclusion(vaultPaths: targets.map(\.vaultPath), excluded: true)
    }

    func includeSelectedInIndex() {
        guard ensureVaultConfigured(), browserMode == .allFonts else { return }
        let targets = selectedFonts.filter(\.excludedFromIndex)
        guard !targets.isEmpty else {
            showErrorAlert("Nothing to include", "Select one or more excluded fonts to include in the index again.")
            return
        }
        applyIndexExclusion(vaultPaths: targets.map(\.vaultPath), excluded: false)
    }

    func setShowIgnoredFonts(_ enabled: Bool) {
        guard settings.showIgnoredFonts != enabled else { return }
        settings.showIgnoredFonts = enabled
        normalizeSidebarSelectionForExclusionState()
        refreshList()
    }

    func toggleShowIgnoredFonts() {
        setShowIgnoredFonts(!settings.showIgnoredFonts)
    }

    func toggleShowMetadataWarnings() {
        settings.showMetadataWarnings.toggle()
        listDataRevision &+= 1
        refreshSelectionCache()
    }

    private func applyIndexExclusion(vaultPaths: [String], excluded: Bool) {
        guard let catalog = coordinator.catalog else { return }
        do {
            _ = try catalog.setExcludedFromIndex(vaultPaths: vaultPaths, excluded: excluded)
            for path in vaultPaths {
                if var record = fontsByVaultPath[path] {
                    record.excludedFromIndex = excluded
                    fontsByVaultPath[path] = record
                } else if let record = try catalog.fetchRecord(vaultPath: path) {
                    fontsByVaultPath[path] = record
                }
            }
            let verb = excluded ? "Excluded from index" : "Included in index"
            statusMessage = "\(verb): \(vaultPaths.count) font\(vaultPaths.count == 1 ? "" : "s")."
            refreshList()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func normalizeSidebarSelectionForExclusionState() {
        if !settings.showIgnoredFonts, case .smartFilter = sidebarSelection {
            sidebarSelection = .allFonts
            formatFilter = nil
        }
        if case .smartFilter(.excludedFonts) = sidebarSelection {
            if excludedFontCount == 0 || !settings.showIgnoredFonts {
                sidebarSelection = .allFonts
                formatFilter = nil
            }
        }
    }

    // MARK: - Remove (FEX-style: Trash or delete permanently; always drops catalog rows)

    func presentRemoveSelected(moveToTrash: Bool) {
        guard ensureVaultConfigured() else { return }

        let selected = selectedFonts
        guard !selected.isEmpty else {
            showErrorAlert("Nothing selected", "Select one or more fonts to move or delete.")
            return
        }

        let alert = NSAlert()
        let names = selected.prefix(12).map(\.fullName).joined(separator: "\n")
        let more = selected.count > 12 ? "\n…and \(selected.count - 12) more" : ""

        if moveToTrash {
            alert.messageText = selected.count == 1
                ? "Move font to Trash?"
                : "Move \(selected.count) fonts to Trash?"
            alert.informativeText = """
            The selected font file(s) will be moved to the Trash and removed from the catalog. You can restore them from the Trash in Finder.

            \(names)\(more)
            """
            alert.addButton(withTitle: "Move to Trash")
        } else {
            alert.messageText = "Delete immediately?"
            alert.informativeText = """
            The selected font file(s) will be removed from the catalog and deleted permanently. This cannot be undone.

            \(names)\(more)
            """
            alert.addButton(withTitle: "Delete Immediately")
            alert.alertStyle = .critical
        }
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                let result = try await coordinator.removeFonts(selected, moveToTrash: moveToTrash)
                selectedVaultPaths.removeAll()
                selectedFamilyIDs.removeAll()
                let verb = moveToTrash ? "Moved to Trash" : "Deleted"
                statusMessage = "\(verb): \(result.removed) font\(result.removed == 1 ? "" : "s")"
                if !result.failed.isEmpty {
                    statusMessage += " (\(result.failed.count) failed)"
                }
                refreshList()
                refreshDuplicateSummary()
            } catch {
                statusMessage = error.localizedDescription
                showErrorAlert(moveToTrash ? "Move to Trash failed" : "Delete failed", error.localizedDescription)
            }
        }
    }

    // MARK: - Export (FEX-style copy out of vault)

    func presentExportSelected() {
        guard ensureVaultConfigured() else { return }

        let selected = selectedFonts
        guard !selected.isEmpty else {
            showErrorAlert("Nothing selected", "Select one or more fonts to export.")
            return
        }

        guard let pick = FontExportPanel.pickDestination(
            initialLayoutMode: settings.exportLayoutMode
        ) else { return }

        // One-shot layout choice for this export only; Settings default is unchanged.
        Task {
            do {
                let result = try await coordinator.exportFonts(
                    selected,
                    to: pick.destination,
                    layoutMode: pick.layoutMode
                )
                statusMessage = "Exported \(result.exported) font\(result.exported == 1 ? "" : "s") to \(pick.destination.path)"
                if !result.failed.isEmpty {
                    statusMessage += " (\(result.failed.count) failed)"
                }
                showExportSummaryAlert(result: result, destination: pick.destination)
            } catch {
                statusMessage = error.localizedDescription
                showErrorAlert("Export failed", error.localizedDescription)
            }
        }
    }

    private func showExportSummaryAlert(result: ExportResult, destination: URL) {
        let alert = NSAlert()
        alert.messageText = result.exported > 0 ? "Export complete" : "Nothing exported"
        var info = "Copied \(result.exported) font\(result.exported == 1 ? "" : "s") to:\n\(destination.path)"
        if !result.failed.isEmpty {
            let detail = result.failed.prefix(8).joined(separator: "\n")
            let more = result.failed.count > 8 ? "\n…and \(result.failed.count - 8) more" : ""
            info += "\n\nFailures:\n\(detail)\(more)"
        }
        alert.informativeText = info
        alert.runModal()
    }

    // MARK: - Clean vault (FEX “Clean Organized Fonts Folder”)

    func presentCleanVault() {
        guard ensureVaultConfigured() else { return }

        Task {
            do {
                coordinator.reportCleanScanProgress()
                let scan = try coordinator.scanVaultIntegrity()
                await presentCleanVaultConfirmation(scan: scan)
            } catch {
                importProgressSession = nil
                statusMessage = error.localizedDescription
                showErrorAlert("Clean Vault failed", error.localizedDescription)
            }
        }
    }

    private func presentCleanVaultConfirmation(scan: OrphanScanResult) async {
        let hasOrphans = !scan.orphanFiles.isEmpty
        let hasMissing = !scan.missingCatalogPaths.isEmpty

        if !hasOrphans && !hasMissing {
            coordinator.reportCleanScanProgress()
            do {
                let optimizeResult = try await coordinator.optimizeCatalogIfNeeded(afterClean: CleanVaultResult())
                importProgressSession = ImportProgressSession(
                    operation: .cleanVault,
                    state: coordinator.cleanVaultAlreadyCleanWithOptimizationProgressState(result: optimizeResult)
                )
                statusMessage = optimizeResult.catalogWasOptimized
                    ? cleanVaultStatusSummary(optimizeResult)
                    : "Vault is clean."
            } catch {
                importProgressSession = nil
                statusMessage = error.localizedDescription
                showErrorAlert("Clean Vault failed", error.localizedDescription)
            }
            await waitForProgressDismissalIfNeeded()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Clean Vault?"
        var info = """
        Clean Vault fixes mismatches between files on disk and the catalog. It does not rescan metadata (use Rebuild Catalog for that).

        Font Vault will:

        """

        if hasOrphans {
            let sample = scan.orphanFiles.prefix(6).map(\.lastPathComponent).joined(separator: "\n")
            let more = scan.orphanFiles.count > 6 ? "\n…and \(scan.orphanFiles.count - 6) more" : ""
            let scanAction = settings.catalogScanMenuTitle.replacingOccurrences(of: "…", with: "")
            let orphanLead = settings.organizesVaultFiles
                ? "Move \(scan.orphanFiles.count) orphan file\(scan.orphanFiles.count == 1 ? "" : "s") on disk (not in the catalog) to the Trash:"
                : "Move \(scan.orphanFiles.count) file\(scan.orphanFiles.count == 1 ? "" : "s") on disk that are not in the catalog to the Trash (or add them, then run \(scanAction)):"
            info += "• \(orphanLead)\n\(sample)\(more)\n"
        }

        if hasMissing {
            let sample = scan.missingCatalogPaths.prefix(6).map { ($0 as NSString).lastPathComponent }.joined(separator: "\n")
            let more = scan.missingCatalogPaths.count > 6 ? "\n…and \(scan.missingCatalogPaths.count - 6) more" : ""
            info += "\n• Remove \(scan.missingCatalogPaths.count) catalog entr\(scan.missingCatalogPaths.count == 1 ? "y" : "ies") whose files are missing (e.g. deleted in Finder):\n\(sample)\(more)\n"
        }

        info += "\n• Remove empty folders left in the vault."
        alert.informativeText = info
        alert.addButton(withTitle: "Clean")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            importProgressSession = nil
            return
        }

        do {
            let result = try await coordinator.performVaultClean(scan: scan)
            refreshList()
            refreshDuplicateSummary()

            if var session = importProgressSession {
                session.state = coordinator.cleanCompletionProgressState(result: result)
                importProgressSession = session
            }
            statusMessage = cleanVaultStatusSummary(result)
            await waitForProgressDismissalIfNeeded()
            if !result.failed.isEmpty {
                showCleanVaultFailuresAlert(result)
            }
        } catch {
            importProgressSession = nil
            statusMessage = error.localizedDescription
            showErrorAlert("Clean Vault failed", error.localizedDescription)
        }
    }

    private func cleanVaultStatusSummary(_ result: CleanVaultResult) -> String {
        var parts: [String] = []
        if result.trashed > 0 {
            parts.append("\(result.trashed) orphan\(result.trashed == 1 ? "" : "s") trashed")
        }
        if result.removedFromCatalog > 0 {
            parts.append("\(result.removedFromCatalog) stale catalog entr\(result.removedFromCatalog == 1 ? "y" : "ies") removed")
        }
        if result.prunedEmptyFolders > 0 {
            parts.append("\(result.prunedEmptyFolders) empty folder\(result.prunedEmptyFolders == 1 ? "" : "s") removed")
        }
        if result.catalogWasOptimized {
            if result.catalogBytesReclaimed > 0 {
                let saved = ByteCountFormatter.string(fromByteCount: result.catalogBytesReclaimed, countStyle: .file)
                parts.append("catalog compacted (about \(saved) reclaimed)")
            } else {
                parts.append("catalog compacted")
            }
        }
        if parts.isEmpty { return "Vault cleaned." }
        var message = "Cleaned vault: " + parts.joined(separator: "; ")
        if !result.failed.isEmpty {
            message += " (\(result.failed.count) failed)"
        }
        return message
    }

    private func showCleanVaultFailuresAlert(_ result: CleanVaultResult) {
        let alert = NSAlert()
        alert.messageText = "Some items could not be cleaned"
        let detail = result.failed.prefix(8).joined(separator: "\n")
        let more = result.failed.count > 8 ? "\n…and \(result.failed.count - 8) more" : ""
        alert.informativeText = detail + more
        alert.runModal()
    }

    func reorganizeVault() {
        guard ensureVaultConfigured() else { return }
        guard settings.organizesVaultFiles else { return }

        let alert = NSAlert()
        alert.messageText = "Reorganize to A–Z Layout?"
        alert.informativeText = """
        Reorganize moves font files into letter buckets and style folders (FEX-style) and updates catalog paths to match.

        Use this after copying fonts directly into the vault folder.

        Rebuild Catalog only scans files where they already are and refreshes metadata — it does not move files or fix folder structure.
        """
        alert.addButton(withTitle: "Reorganize")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        importProgressSession = ImportProgressSession(
            operation: .reorganizeVault,
            state: .active(
                title: "Reorganizing vault…",
                fileName: "Preparing…",
                completed: 0,
                total: 1
            )
        )

        Task {
            await Task.yield()
            do {
                let result = try await coordinator.reorganizeVaultLayout()
                refreshList()
                refreshDuplicateSummary()

                if var session = importProgressSession {
                    let fileCount = result.moved + result.unchanged + result.catalogAdded
                    session.state = coordinator.reorganizeCompletionProgressState(
                        result: result,
                        fileCount: fileCount
                    )
                    importProgressSession = session
                }

                if coordinator.reorganizeWasCancelled {
                    statusMessage = coordinator.indexProgress
                    await waitForProgressDismissalIfNeeded()
                    return
                }

                var parts: [String] = []
                if result.moved > 0 { parts.append("\(result.moved) moved") }
                if result.catalogAdded > 0 { parts.append("\(result.catalogAdded) added to catalog") }
                if result.unchanged > 0 { parts.append("\(result.unchanged) already in place") }
                statusMessage = parts.isEmpty ? "Nothing to reorganize." : "Reorganize: " + parts.joined(separator: "; ")
                if !result.failed.isEmpty {
                    statusMessage += " (\(result.failed.count) failed)"
                }
                await waitForProgressDismissalIfNeeded()
                if !result.failed.isEmpty {
                    showReorganizeFailuresAlert(result)
                }
            } catch {
                importProgressSession = nil
                statusMessage = error.localizedDescription
                showErrorAlert("Reorganize failed", error.localizedDescription)
            }
        }
    }

    private func showReorganizeFailuresAlert(_ result: ReorganizeResult) {
        let alert = NSAlert()
        alert.messageText = "Some fonts could not be reorganized"
        let detail = result.failed.prefix(10).joined(separator: "\n")
        let more = result.failed.count > 10 ? "\n…and \(result.failed.count - 10) more" : ""
        alert.informativeText = detail + more
        alert.runModal()
    }

    func revealSelectedInFinder() {
        let urls = selectedFonts.compactMap { absoluteURL(for: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: - Duplicates (SHA-256, FEX Conflicts → Duplicates → File)

    func showAllFonts() {
        browserMode = .allFonts
        sidebarSelection = .allFonts
    }

    func showDuplicates() {
        browserMode = .duplicates
        sidebarSelection = .duplicates
        if !duplicateScanCompleted {
            scanForDuplicates()
        }
    }

    func selectSidebarItem(_ item: SidebarItem) {
        switch item {
        case .allFonts:
            browserMode = .allFonts
            formatFilter = nil
            sidebarSelection = .allFonts
        case .duplicates:
            showDuplicates()
        case .format(let filterKey):
            browserMode = .allFonts
            formatFilter = filterKey
            sidebarSelection = .format(filterKey: filterKey)
        case .smartFilter:
            browserMode = .allFonts
            sidebarSelection = item
        }
        scheduleRefreshList()
    }

    func toggleSidebarVisibility() {
        prefersSidebarVisible.toggle()
    }

    func toggleInspectorVisibility() {
        showInspector.toggle()
    }

    /// Opens a new inspector window (FEX-style). Navigation uses the current table selection.
    func presentFontInspector(anchoredAtVaultPath vaultPath: String) {
        let navigation = inspectorNavigationFonts(anchoredAt: vaultPath)
        guard !navigation.fonts.isEmpty else { return }
        FontInspectorWindowController.shared.present(
            fonts: navigation.fonts,
            selectedIndex: navigation.selectedIndex
        )
    }

    /// Whether the font table context menu can open an inspector for the current selection.
    var canPresentFontInspectorForSelection: Bool {
        !fontsForExportSelection().isEmpty
    }

    /// Opens an inspector window for the current row selection (fonts and/or families).
    func presentFontInspectorForSelection() {
        let paths = fontsForExportSelection().map(\.vaultPath)
        guard let anchor = sortVaultPathsByDisplayOrder(paths).first else { return }
        presentFontInspector(anchoredAtVaultPath: anchor)
    }

    func dismissFontInspector() {
        FontInspectorWindowController.shared.closeAll()
    }

    /// Ordered font list for inspector prev/next and the picker (table display order).
    func inspectorNavigationFonts(anchoredAt vaultPath: String) -> (fonts: [FontRecord], selectedIndex: Int) {
        let paths = inspectorNavigationVaultPaths(anchoredAt: vaultPath)
        let fonts = paths.compactMap { catalogFont(forVaultPath: $0) }
        let index = paths.firstIndex(of: vaultPath) ?? 0
        return (fonts, min(index, max(0, fonts.count - 1)))
    }

    /// Paths used for inspector navigation (exposed for double-click before selection is narrowed).
    func inspectorNavigationVaultPathsForClick(anchoredAt vaultPath: String) -> [String] {
        inspectorNavigationVaultPaths(anchoredAt: vaultPath)
    }

    private func inspectorNavigationVaultPaths(anchoredAt vaultPath: String) -> [String] {
        let looseSelection = selectedVaultPaths
        if looseSelection.contains(vaultPath), looseSelection.count > 1 {
            let ordered = displayedFontPaths.filter { looseSelection.contains($0) }
            if ordered.contains(vaultPath) { return ordered }
        }

        if !selectedFamilyIDs.isEmpty {
            let exportPaths = fontsForExportSelection().map(\.vaultPath)
            let ordered = sortVaultPathsByDisplayOrder(exportPaths)
            if ordered.contains(vaultPath) { return ordered }
            if !looseSelection.isEmpty {
                let mixed = sortVaultPathsByDisplayOrder(Array(looseSelection))
                if mixed.contains(vaultPath) { return mixed }
            }
            if !ordered.isEmpty, looseSelection.isEmpty { return ordered }
        }

        return [vaultPath]
    }

    private func sortVaultPathsByDisplayOrder(_ paths: [String]) -> [String] {
        let order = displayedFontPaths
        return paths.sorted { lhs, rhs in
            let li = order.firstIndex(of: lhs) ?? Int.max
            let ri = order.firstIndex(of: rhs) ?? Int.max
            if li != ri { return li < ri }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    func focusSearchField() {
        searchFocusRequest += 1
    }

    /// Edit → Find (⌘F): prefill search when the list has a single findable cell value; always focus search.
    func performFindFromList() {
        if let coordinator = fontListCoordinator,
           coordinator.applyFindFromListSelection() {
            return
        }
        focusSearchField()
    }

    func scanForDuplicates() {
        guard ensureVaultConfigured() else { return }
        invalidateDuplicateScanState()
        Task {
            await performDuplicateScan(updateStatus: true)
        }
    }

    /// Full duplicate scan when opening Duplicates or after catalog changes.
    func ensureDuplicateScanForBrowse() {
        guard settings.vaultRootURL != nil, coordinator.catalog != nil else { return }
        guard !duplicateScanCompleted, !isScanningDuplicates else { return }
        Task {
            await performDuplicateScan(updateStatus: false)
        }
    }

    /// Background summary for status bar (after import/rebuild/remove).
    func refreshDuplicateSummary() {
        guard settings.vaultRootURL != nil, coordinator.catalog != nil else { return }
        invalidateDuplicateScanState()
        Task {
            await performDuplicateScan(updateStatus: false)
            await refreshDuplicateQuickCount()
        }
    }

    private func performDuplicateScan(updateStatus: Bool) async {
        isScanningDuplicates = true
        defer { isScanningDuplicates = false }

        do {
            guard let catalog = coordinator.catalog else { return }
            let all = try catalog.fetchFontsForDuplicateScan()
            let groups = DuplicateScanner.findGroups(in: all)
            duplicateGroups = groups
            duplicateKeeperByHash = Dictionary(
                uniqueKeysWithValues: groups.map { group in
                    (group.sha256, DuplicateScanner.defaultKeeperPath(in: group.fonts))
                }
            )
            duplicateScanCompleted = true

            if updateStatus {
                if groups.isEmpty {
                    statusMessage = "No duplicate file content in catalog."
                } else {
                    statusMessage = "Found \(duplicateFileCount) duplicate files in \(groups.count) cases."
                }
            }
        } catch {
            if updateStatus {
                statusMessage = error.localizedDescription
            }
        }
    }

    func keeperPath(for group: DuplicateGroup) -> String {
        duplicateKeeperByHash[group.sha256] ?? DuplicateScanner.defaultKeeperPath(in: group.fonts)
    }

    func setKeeper(_ vaultPath: String, for sha256: String) {
        duplicateKeeperByHash[sha256] = vaultPath
    }

    func presentResolveDuplicates(moveToTrash: Bool) {
        guard ensureVaultConfigured() else { return }

        var toRemove: [FontRecord] = []
        for group in duplicateGroups {
            let keeper = keeperPath(for: group)
            toRemove.append(contentsOf: DuplicateScanner.fontsToRemove(from: group, keeperPath: keeper))
        }
        guard !toRemove.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Resolve duplicate fonts?"
        alert.informativeText = """
        \(toRemove.count) duplicate file(s) will be removed from the catalog\(moveToTrash ? " and moved to the Trash" : " and deleted permanently"). One copy per group will be kept.

        Review the “Keep” selection in each case before continuing.
        """
        alert.addButton(withTitle: moveToTrash ? "Move Duplicates to Trash" : "Delete Duplicates")
        if !moveToTrash { alert.alertStyle = .critical }
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                let result = try await coordinator.removeFonts(toRemove, moveToTrash: moveToTrash)
                refreshList()
                await performDuplicateScan(updateStatus: true)
                statusMessage = "Removed \(result.removed) duplicate file(s)."
            } catch {
                statusMessage = error.localizedDescription
                showErrorAlert("Resolve duplicates failed", error.localizedDescription)
            }
        }
    }
}
