import AppKit

/// Data source + delegate for the virtualized font list (`NSOutlineView`).
@MainActor
final class FontListOutlineCoordinator: NSObject {
    weak var outlineView: NSOutlineView?
    weak var appState: AppState?

    private var groupByFamily = true
    private var rootNodes: [FontListOutlineNode] = []
    private var collapsedFamilies: Set<String> = []
    private var displayColumns: [FontListColumn] = []
    private var showFamilySubtitle = false
    private var rowDensity: FontListRowDensity = .compact
    private var lastRowDensity: FontListRowDensity = .compact
    private var sortColumn = "fullName"
    private var sortAscending = true

    private var listDataRevision: UInt = 0
    private var lastGroupByFamily = true
    private var lastCollapsedFamilies: Set<String> = []
    private var lastSyncedVaultPaths: Set<String> = []
    private var lastSyncedFamilyIDs: Set<String> = []
    private var familyIDToRow: [String: Int] = [:]
    private var isSyncingSelection = false
    private var isProgrammaticExpansionChange = false
    private var isBatchingColumnChanges = false
    private var activeExportDragFileCount = 0
    private var vaultPathToRow: [String: Int] = [:]
    /// Skips AppState→outline expansion sync while outline-driven expand/collapse updates `collapsedFamilies`.
    private var outlineDrivingExpansionChange = false
    private var lastContextMenuContext: FontListContextMenuContext?
    private var lastHoverRowColumn: (row: Int, column: Int)?
    /// Row/column for Edit → Find (hover, click, or context menu).
    private var lastFindAnchor: (row: Int, column: FontListColumn?)?
    private var columnMoveObservation: NSObjectProtocol?

    /// Exposed for context menu builder enablement rules.
    var appStateForMenu: AppState? { appState }

    /// Column for single-font selection status detail (last clicked/hovered cell).
    func statusDetailColumnForSelection() -> FontListColumn {
        lastFindAnchor?.column ?? .name
    }

    // MARK: - Public updates (from SwiftUI host)

    func update(
        appState: AppState,
        settings: VaultSettings,
        listDataRevision: UInt
    ) {
        self.appState = appState
        appState.fontListCoordinator = self
        groupByFamily = appState.groupByFamily
        collapsedFamilies = appState.collapsedFamilies
        sortColumn = appState.sortColumn
        sortAscending = appState.sortAscending
        rowDensity = settings.listRowDensity
        let newShowFamilySubtitle = !groupByFamily
            && !settings.visibleListColumns.contains(.family)
            && rowDensity == .comfortable
        let rowPresentationChanged =
            newShowFamilySubtitle != showFamilySubtitle || rowDensity != lastRowDensity
        showFamilySubtitle = newShowFamilySubtitle
        lastRowDensity = rowDensity

        let newColumns = Self.visibleColumns(from: settings)
        let columnsChanged = newColumns.map(\.rawValue) != displayColumns.map(\.rawValue)
        displayColumns = newColumns

        let listRevisionChanged = listDataRevision != self.listDataRevision
        let groupByFamilyChanged = groupByFamily != lastGroupByFamily
        let expansionChanged = collapsedFamilies != lastCollapsedFamilies
        let needsDataReload = listRevisionChanged || groupByFamilyChanged

        self.listDataRevision = listDataRevision
        lastGroupByFamily = groupByFamily
        lastCollapsedFamilies = collapsedFamilies

        guard let outlineView else { return }

        // One-time setup: create NSTableColumns for every FontListColumn.
        // After this, columns are never removed/added -- only shown/hidden via isHidden.
        if outlineView.tableColumns.isEmpty {
            installAllColumns(settings: settings, outlineView: outlineView)
        }

        if groupByFamilyChanged {
            rootNodes = []
        }

        if needsDataReload || rootNodes.isEmpty {
            if groupByFamily {
                rootNodes = appState.familySections.map { FontListOutlineNode(family: $0) }
            } else {
                rootNodes = appState.flatRowPaths.map { FontListOutlineNode(vaultPath: $0) }
            }
        } else if !groupByFamily, appState.flatRowPaths.count > rootNodes.count {
            let existing = Set(rootNodes.compactMap(\.vaultPath))
            let newPaths = appState.flatRowPaths.filter { !existing.contains($0) }
            rootNodes.append(contentsOf: newPaths.map { FontListOutlineNode(vaultPath: $0) })
            outlineView.noteNumberOfRowsChanged()
        }

        if columnsChanged {
            syncColumnVisibility(settings: settings, outlineView: outlineView)
        }
        ensureColumnMoveObservation(outlineView: outlineView)
        applyStoredColumnOrderIfNeeded(settings: settings, outlineView: outlineView)

        if needsDataReload || rowPresentationChanged {
            reloadOutline(keepingSelection: true)
        } else if expansionChanged, !outlineDrivingExpansionChange {
            if outlineExpansionDiffersFromAppState(outlineView) {
                syncExpansionFromAppState(outlineView)
            } else {
                rebuildRowIndex()
            }
        }

        if appState.selectedVaultPaths != lastSyncedVaultPaths
            || appState.selectedFamilyIDs != lastSyncedFamilyIDs {
            applySelection(
                familyIDs: appState.selectedFamilyIDs,
                vaultPaths: appState.selectedVaultPaths,
                to: outlineView
            )
        }

        if groupByFamilyChanged || columnsChanged || needsDataReload {
            updateSortIndicators()
        }
    }

    static func visibleColumns(from settings: VaultSettings) -> [FontListColumn] {
        var columns: [FontListColumn] = []
        var seen = Set<FontListColumn>()
        for column in settings.listColumnOrder {
            guard settings.isListColumnVisible(column), seen.insert(column).inserted else { continue }
            columns.append(column)
        }
        if !seen.contains(.name) {
            columns.insert(.name, at: 0)
        }
        return columns
    }

    // MARK: - Columns

    /// Creates an NSTableColumn for every FontListColumn case (once at startup).
    /// Hidden columns remain in the table but are invisible and don't request cell views.
    private func installAllColumns(settings: VaultSettings, outlineView: NSOutlineView) {
        isBatchingColumnChanges = true
        defer { isBatchingColumnChanges = false }

        let visibleSet = Set(displayColumns)
        for column in settings.listColumnOrder {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.minWidth = column.minWidth
            tableColumn.maxWidth = column.maxWidth
            tableColumn.width = settings.columnWidth(for: column)
            tableColumn.isHidden = !visibleSet.contains(column)
            let headerCell = FontListOutlineHeaderCell(textCell: column.title)
            headerCell.alignment = .left
            tableColumn.headerCell = headerCell
            if let textCell = tableColumn.dataCell as? NSTextFieldCell {
                textCell.alignment = .left
            }
            outlineView.addTableColumn(tableColumn)
        }

        if let outlineColumn = outlineView.tableColumns.first(where: {
            $0.identifier.rawValue == FontListColumn.name.rawValue
        }) {
            outlineView.outlineTableColumn = outlineColumn
        } else {
            outlineView.outlineTableColumn = outlineView.tableColumns.first
        }

        attachCustomHeaderView(to: outlineView)
        ensureColumnMoveObservation(outlineView: outlineView)
        updateSortIndicators()
    }

    private func ensureColumnMoveObservation(outlineView: NSOutlineView) {
        guard columnMoveObservation == nil else { return }
        columnMoveObservation = NotificationCenter.default.addObserver(
            forName: NSTableView.columnDidMoveNotification,
            object: outlineView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistOutlineColumnOrderFromHeaderDrag()
            }
        }
    }

    private func persistOutlineColumnOrderFromHeaderDrag() {
        guard !isBatchingColumnChanges,
              let outlineView,
              let appState else { return }
        appState.settings.adoptListColumnOrder(fromTableColumns: outlineView.tableColumns)
    }

    /// Applies Settings / persisted order to the outline (e.g. after reorder in Font Table settings).
    private func applyStoredColumnOrderIfNeeded(settings: VaultSettings, outlineView: NSOutlineView) {
        let stored = settings.listColumnOrder.map(\.rawValue)
        let current = outlineView.tableColumns.map(\.identifier.rawValue)
        guard stored != current else { return }
        isBatchingColumnChanges = true
        defer { isBatchingColumnChanges = false }
        for (targetIndex, raw) in stored.enumerated() {
            guard let fromIndex = outlineView.tableColumns.firstIndex(where: { $0.identifier.rawValue == raw }),
                  fromIndex != targetIndex else { continue }
            outlineView.moveColumn(fromIndex, toColumn: targetIndex)
        }
    }

    /// Toggles isHidden on existing NSTableColumns to match current visibility settings.
    /// No columns are removed or added — avoids triggering cascading SwiftUI observation updates.
    private func syncColumnVisibility(settings: VaultSettings, outlineView: NSOutlineView) {
        isBatchingColumnChanges = true
        defer { isBatchingColumnChanges = false }

        let visibleSet = Set(displayColumns)
        for tableColumn in outlineView.tableColumns {
            guard let column = columnForIdentifier(tableColumn.identifier) else { continue }
            let shouldBeVisible = visibleSet.contains(column)
            if tableColumn.isHidden == shouldBeVisible {
                tableColumn.isHidden = !shouldBeVisible
                if shouldBeVisible {
                    tableColumn.width = settings.columnWidth(for: column)
                }
            }
        }
        updateSortIndicators()
    }

    private func attachCustomHeaderView(to outlineView: NSOutlineView) {
        if let header = outlineView.headerView as? FontListOutlineHeaderView {
            header.interaction = self
            return
        }
        let frame = outlineView.headerView?.frame ?? NSRect(x: 0, y: 0, width: outlineView.bounds.width, height: 30)
        let header = FontListOutlineHeaderView(frame: frame)
        header.interaction = self
        outlineView.headerView = header
    }

    private func isEventInTableHeader(_ event: NSEvent, outlineView: NSOutlineView) -> Bool {
        guard let header = outlineView.headerView, header.window != nil else { return false }
        let headerFrame = header.convert(header.bounds, to: nil)
        return headerFrame.contains(event.locationInWindow)
    }

    private func updateSortIndicators() {
        guard let outlineView else { return }
        let nameHeaderInset = FontListOutlineChrome.nameColumnHeaderLeadingInset(
            indentationPerLevel: outlineView.indentationPerLevel,
            groupByFamily: groupByFamily
        )
        for tableColumn in outlineView.tableColumns {
            guard let column = columnForIdentifier(tableColumn.identifier) else { continue }
            let headerCell: FontListOutlineHeaderCell
            if let existing = tableColumn.headerCell as? FontListOutlineHeaderCell {
                headerCell = existing
            } else {
                headerCell = FontListOutlineHeaderCell(textCell: column.title)
                headerCell.alignment = .left
                tableColumn.headerCell = headerCell
            }
            headerCell.stringValue = column.title
            headerCell.titleLeadingInset = column == .name ? nameHeaderInset : 6
            if column.databaseSortColumn == sortColumn {
                headerCell.sortIndicator = sortAscending ? .ascending : .descending
            } else {
                headerCell.sortIndicator = .none
            }
        }
        outlineView.headerView?.needsDisplay = true
    }

    /// True when the click is on a column divider (resize grab), not the sortable header body.
    private func isEventInColumnResizeZone(_ event: NSEvent, outlineView: NSOutlineView) -> Bool {
        guard let header = outlineView.headerView else { return false }
        let location = header.convert(event.locationInWindow, from: nil)
        let grabHalfWidth: CGFloat = 7

        for columnIndex in 0 ..< outlineView.numberOfColumns {
            let tableColumn = outlineView.tableColumns[columnIndex]
            guard !tableColumn.isHidden else { continue }
            let rect = header.headerRect(ofColumn: columnIndex)
            guard rect.width > 0 else { continue }
            if abs(location.x - rect.maxX) <= grabHalfWidth {
                return true
            }
        }
        return false
    }

    private func columnForIdentifier(_ id: NSUserInterfaceItemIdentifier) -> FontListColumn? {
        FontListColumn(rawValue: id.rawValue)
    }

    // MARK: - Reload

    private func reloadOutline(keepingSelection: Bool) {
        guard let outlineView else { return }
        let priorFamilies = keepingSelection ? lastSyncedFamilyIDs : []
        let priorPaths = keepingSelection ? lastSyncedVaultPaths : []
        outlineView.reloadData()
        syncExpansionFromAppState(outlineView)
        rebuildRowIndex()
        if keepingSelection {
            applySelection(familyIDs: priorFamilies, vaultPaths: priorPaths, to: outlineView)
        }
    }

    /// Aligns outline expand/collapse with `collapsedFamilies` without eager child SQL loads.
    private func syncExpansionFromAppState(_ outlineView: NSOutlineView) {
        guard groupByFamily else { return }
        isProgrammaticExpansionChange = true
        defer { isProgrammaticExpansionChange = false }
        for node in rootNodes where node.isFamily {
            guard let familyID = node.familyID else { continue }
            let shouldExpand = !collapsedFamilies.contains(familyID)
            if shouldExpand {
                if !outlineView.isItemExpanded(node) {
                    outlineView.expandItem(node, expandChildren: false)
                }
            } else if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node, collapseChildren: true)
            }
        }
    }

    private func outlineExpansionDiffersFromAppState(_ outlineView: NSOutlineView) -> Bool {
        guard groupByFamily else { return false }
        for node in rootNodes where node.isFamily {
            guard let familyID = node.familyID else { continue }
            let shouldExpand = !collapsedFamilies.contains(familyID)
            if outlineView.isItemExpanded(node) != shouldExpand {
                return true
            }
        }
        return false
    }

    private func rebuildRowIndex() {
        guard let outlineView else { return }
        vaultPathToRow.removeAll(keepingCapacity: true)
        familyIDToRow.removeAll(keepingCapacity: true)
        for row in 0 ..< outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? FontListOutlineNode else { continue }
            if let path = node.vaultPath {
                vaultPathToRow[path] = row
            }
            if let familyID = node.familyID {
                familyIDToRow[familyID] = row
            }
        }
    }

    // MARK: - Selection

    private func applySelection(
        familyIDs: Set<String>,
        vaultPaths: Set<String>,
        to outlineView: NSOutlineView
    ) {
        isSyncingSelection = true
        defer {
            isSyncingSelection = false
            lastSyncedFamilyIDs = familyIDs
            lastSyncedVaultPaths = vaultPaths
        }

        var indexes = IndexSet()
        for familyID in familyIDs {
            if let row = familyIDToRow[familyID] {
                indexes.insert(row)
            }
        }
        for path in vaultPaths {
            if let row = vaultPathToRow[path] {
                indexes.insert(row)
            }
        }
        outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    // MARK: - Select all key commands (override AppKit default select-all-rows)

    func handleSelectAllFamiliesKeyCommand() {
        guard let appState, let outlineView else { return }
        appState.selectAllFamiliesInFilter()
        applySelection(
            familyIDs: appState.selectedFamilyIDs,
            vaultPaths: appState.selectedVaultPaths,
            to: outlineView
        )
    }

    func handleSelectAllFontsDeepKeyCommand() {
        guard let appState else { return }
        appState.selectAllFontsDeepInFilter()
    }

    func handleDeselectAllKeyCommand() {
        guard let appState, let outlineView else { return }
        appState.deselectAll()
        applySelection(familyIDs: [], vaultPaths: [], to: outlineView)
    }

    private func publishSelection(from outlineView: NSOutlineView) {
        guard !isSyncingSelection, let appState else { return }
        var familyIDs = Set<String>()
        var paths = Set<String>()
        for row in outlineView.selectedRowIndexes {
            guard let node = outlineView.item(atRow: row) as? FontListOutlineNode else { continue }
            if let path = node.vaultPath {
                paths.insert(path)
            }
            if let familyID = node.familyID {
                familyIDs.insert(familyID)
            }
        }
        guard familyIDs != lastSyncedFamilyIDs || paths != lastSyncedVaultPaths else { return }
        lastSyncedFamilyIDs = familyIDs
        lastSyncedVaultPaths = paths
        appState.syncSelectionFromOutline(familyIDs: familyIDs, vaultPaths: paths)
    }

    private func deferToNextRunLoop(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in action() }
    }

    // MARK: - Mouse, context menu, export drag (restored from pre-outline interaction layer)

    /// Plain or chord click committed on mouse up (FEX-style: drag before click replaces selection).
    func commitFontClick(vaultPath: String, event: NSEvent, outlineView: NSOutlineView) {
        recordFindAnchor(for: event, outlineView: outlineView)
        appState?.handleFontListMouseDown(vaultPath: vaultPath, event: event)
        guard let appState else { return }
        applySelection(
            familyIDs: appState.selectedFamilyIDs,
            vaultPaths: appState.selectedVaultPaths,
            to: outlineView
        )
    }

    func commitFamilyClick(section: FontFamilySection, event: NSEvent, outlineView: NSOutlineView) {
        recordFindAnchor(for: event, outlineView: outlineView)
        appState?.handleFamilyListMouseDown(familyID: section.id, event: event)
        guard let appState else { return }
        applySelection(
            familyIDs: appState.selectedFamilyIDs,
            vaultPaths: appState.selectedVaultPaths,
            to: outlineView
        )
    }

    /// Edit → Find: same rules as context menu Find when one distinct cell value is available.
    @discardableResult
    func applyFindFromListSelection() -> Bool {
        guard let appState, let outlineView else { return false }

        let row: Int
        let column: FontListColumn?
        if let anchor = lastFindAnchor, anchor.row >= 0 {
            row = anchor.row
            column = anchor.column ?? .name
        } else if outlineView.selectedRow >= 0 {
            row = outlineView.selectedRow
            let colIndex = outlineView.clickedColumn
            column = colIndex >= 0 ? columnAtIndex(colIndex, in: outlineView) : .name
        } else {
            return false
        }

        guard let context = makeListContext(row: row, clickedColumn: column, outlineView: outlineView),
              let text = context.findText else {
            appState.focusSearchField()
            return true
        }
        appState.searchText = text
        appState.focusSearchField()
        return true
    }

    func handleFontRowDoubleClick(vaultPath: String, outlineView: NSOutlineView) {
        guard let appState else { return }
        let navigationPaths = appState.inspectorNavigationVaultPathsForClick(anchoredAt: vaultPath)
        if navigationPaths.count <= 1 {
            appState.selectedFamilyIDs.removeAll()
            appState.syncSelectionFromOutline(familyIDs: [], vaultPaths: [vaultPath])
            applySelection(familyIDs: [], vaultPaths: [vaultPath], to: outlineView)
        }
        appState.presentFontInspector(anchoredAtVaultPath: vaultPath)
    }

    func handleFamilyRowDoubleClick(section: FontFamilySection, outlineView: NSOutlineView) {
        guard let appState else { return }
        if let node = rootNodes.first(where: { $0.familyID == section.id }) {
            loadFamilyChildrenIfNeeded(node: node, outlineView: outlineView)
        }
        if appState.collapsedFamilies.contains(section.id) {
            appState.collapsedFamilies.remove(section.id)
            collapsedFamilies = appState.collapsedFamilies
            syncFamilyExpansion(section.id, outlineView: outlineView)
        }
        let paths: Set<String>
        if let node = rootNodes.first(where: { $0.familyID == section.id }),
           let children = node.children {
            paths = Set(children.compactMap(\.vaultPath))
        } else {
            paths = Set(
                (try? appState.coordinator.catalog?.fetchFontsForFamily(
                    familyKey: section.id,
                    query: appState.tableBrowseQuery(),
                    sortColumn: appState.sortColumn,
                    ascending: appState.sortAscending
                ).map(\.vaultPath)) ?? []
            )
        }
        appState.selectedFamilyIDs.removeAll()
        appState.syncSelectionFromOutline(familyIDs: [], vaultPaths: paths)
        applySelection(familyIDs: [], vaultPaths: paths, to: outlineView)
    }

    private func loadFamilyChildrenIfNeeded(node: FontListOutlineNode, outlineView: NSOutlineView) {
        guard node.isFamily,
              !node.isChildrenLoaded,
              let familyID = node.familyID,
              let appState,
              let catalog = appState.coordinator.catalog else { return }

        do {
            let fonts = try catalog.fetchFontsForFamily(
                familyKey: familyID,
                query: appState.tableBrowseQuery(),
                sortColumn: appState.sortColumn,
                ascending: appState.sortAscending
            )
            let children = fonts.map { FontListOutlineNode(font: $0) }
            node.setChildNodes(children)
            appState.registerLoadedFamilyFonts(familyID: familyID, fonts: fonts)
            // Defer reload so AppKit does not re-enter `child(_:ofItem:)` mid-load and bind rows to the family node.
            DispatchQueue.main.async { [weak outlineView] in
                outlineView?.reloadItem(node, reloadChildren: true)
            }
        } catch {
            node.setChildNodes([])
            appState.statusMessage = error.localizedDescription
        }
    }

    private func resolvedPayload(for node: FontListOutlineNode) -> FontListOutlineItem {
        switch node.payload {
        case .fontPath(let path):
            if let font = appState?.catalogFont(forVaultPath: path) {
                return .font(font)
            }
            return node.payload
        default:
            return node.payload
        }
    }

    private func syncFamilyExpansion(_ familyID: String, outlineView: NSOutlineView) {
        guard groupByFamily,
              let node = rootNodes.first(where: { $0.familyID == familyID }) else { return }
        isProgrammaticExpansionChange = true
        defer { isProgrammaticExpansionChange = false }
        let shouldExpand = !collapsedFamilies.contains(familyID)
        if shouldExpand {
            outlineView.expandItem(node, expandChildren: false)
        } else {
            outlineView.collapseItem(node, collapseChildren: true)
        }
        rebuildRowIndex()
    }

    func shouldBeginExportDrag(from start: NSPoint, to current: NSPoint) -> Bool {
        let dx = current.x - start.x
        let dy = current.y - start.y
        return (dx * dx + dy * dy) >= FontListOutlineView.exportDragThreshold * FontListOutlineView.exportDragThreshold
    }

    func beginExportDrag(vaultPath: String?, family: FontFamilySection?, event: NSEvent, outlineView: NSOutlineView) -> Bool {
        guard let appState else { return false }
        let plan: DragExportStaging.Plan?
        if let family {
            plan = appState.prepareExportDrag(forFamily: family)
        } else if let vaultPath {
            plan = appState.prepareExportDrag(for: vaultPath)
        } else {
            plan = nil
        }
        guard let plan, !plan.dragURLs.isEmpty else { return false }

        appState.beginExportDragSession()
        activeExportDragFileCount = plan.fileCount

        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        FontVaultDragTypes.markExportDrag(on: pasteboard)
        pasteboard.writeObjects(plan.dragURLs.map { $0 as NSURL })

        let badge = FontExportDragBadge.image(count: plan.fileCount)
        let frame = NSRect(origin: .zero, size: FontExportDragBadge.dragImageSize)
        let items = plan.dragURLs.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(frame, contents: badge)
            return item
        }

        let session = outlineView.beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = plan.fileCount > 1 ? .pile : .default
        return true
    }

    func contextMenu(for event: NSEvent, outlineView: NSOutlineView) -> NSMenu? {
        if isEventInTableHeader(event, outlineView: outlineView) {
            return columnHeaderMenu()
        }

        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row = outlineView.row(at: point)
        guard row >= 0 else {
            return columnHeaderMenu()
        }

        if let node = outlineView.item(atRow: row) as? FontListOutlineNode,
           let appState {
            let rowSelection: FontListSelectionRow?
            if let path = node.vaultPath {
                rowSelection = .font(path)
            } else if let section = node.familySection {
                rowSelection = .family(section.id)
            } else {
                rowSelection = nil
            }
            if let rowSelection, !appState.isListRowSelected(rowSelection) {
                appState.handleListRowMouseDown(rowSelection, event: event)
                applySelection(
                    familyIDs: appState.selectedFamilyIDs,
                    vaultPaths: appState.selectedVaultPaths,
                    to: outlineView
                )
            }
        }

        guard let context = buildContextMenuContext(for: event, outlineView: outlineView, row: row) else {
            return nil
        }
        lastContextMenuContext = context
        return FontListContextMenuBuilder.menu(for: context, target: self)
    }

    func updateHoverStatus(at point: NSPoint, in outlineView: NSOutlineView) {
        guard let appState else { return }
        let row = outlineView.row(at: point)
        let columnIndex = outlineView.column(at: point)
        if row < 0 {
            clearHoverStatusDetail()
            return
        }
        if isPointInDisclosureZone(point: point, row: row, outlineView: outlineView) {
            clearHoverStatusDetail()
            return
        }
        if lastHoverRowColumn?.row == row, lastHoverRowColumn?.column == columnIndex { return }
        lastHoverRowColumn = (row: row, column: columnIndex)
        let hoverColumn = columnAtIndex(columnIndex, in: outlineView)
        lastFindAnchor = (row, hoverColumn)

        guard let node = outlineView.item(atRow: row) as? FontListOutlineNode else {
            clearHoverStatusDetail()
            return
        }
        let payload = resolvedPayload(for: node)
        let column = columnAtIndex(columnIndex, in: outlineView)

        switch payload {
        case .font(let font):
            if let detail = ListStatusDetail.forFont(font, column: column, source: .hover) {
                appState.selectionDisplay.updateHoverStatusDetail(detail)
            } else {
                clearHoverStatusDetail()
            }
        case .family(let section):
            guard let column else {
                clearHoverStatusDetail()
                return
            }
            let loaded = appState.fontsForExportSelection().filter {
                FontListGrouping.familyKey(for: $0) == section.id
            }
            if let detail = ListStatusDetail.forFamilyHeader(
                column: column,
                section: section,
                loadedFonts: loaded,
                source: .hover
            ) {
                appState.selectionDisplay.updateHoverStatusDetail(detail)
            } else {
                clearHoverStatusDetail()
            }
        default:
            clearHoverStatusDetail()
        }
    }

    func clearHoverStatusDetail() {
        lastHoverRowColumn = nil
        appState?.selectionDisplay.updateHoverStatusDetail(nil)
    }

    private func buildContextMenuContext(
        for event: NSEvent,
        outlineView: NSOutlineView,
        row: Int
    ) -> FontListContextMenuContext? {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let columnIndex = outlineView.column(at: point)
        let clickedColumn: FontListColumn?
        if isPointInDisclosureZone(point: point, row: row, outlineView: outlineView) {
            clickedColumn = nil
        } else {
            clickedColumn = columnAtIndex(columnIndex, in: outlineView)
        }
        lastFindAnchor = (row, clickedColumn)
        return makeListContext(row: row, clickedColumn: clickedColumn, outlineView: outlineView)
    }

    private func makeListContext(
        row: Int,
        clickedColumn: FontListColumn?,
        outlineView: NSOutlineView
    ) -> FontListContextMenuContext? {
        guard let appState else { return nil }
        guard let node = outlineView.item(atRow: row) as? FontListOutlineNode else { return nil }
        let payload = resolvedPayload(for: node)
        let rowKind: FontListContextMenuRowKind
        switch payload {
        case .family(let section):
            rowKind = .family(section)
        case .font(let font):
            rowKind = .font(font)
        case .fontPath:
            rowKind = .none
        }

        let clickedDisplayText: String
        if let column = clickedColumn {
            switch payload {
            case .family(let section):
                clickedDisplayText = column.familyCellText(for: section)
            case .font(let font):
                clickedDisplayText = column.rawDisplayValue(for: font)
            case .fontPath:
                clickedDisplayText = ""
            }
        } else {
            clickedDisplayText = ""
        }

        let selectedFonts = appState.fontsForExportSelection()
        let selectionCount = selectedFonts.count
        let singleFontSelected = appState.selectedFamilyIDs.isEmpty
            && appState.selectedVaultPaths.count == 1

        return FontListContextMenuContext(
            rowKind: rowKind,
            clickedColumn: clickedColumn,
            clickedDisplayText: clickedDisplayText,
            selectionCount: selectionCount,
            singleFontSelected: singleFontSelected,
            browserMode: appState.browserMode,
            groupByFamily: groupByFamily,
            showInspector: appState.showInspector,
            selectedFonts: selectedFonts,
            visibleColumns: Self.visibleColumns(from: appState.settings),
            vaultRootURL: appState.settings.vaultRootURL,
            activeFormatFilter: appState.formatFilter,
            showsExcludedFontsSmartFilter: appState.browserMode == .allFonts
                && appState.showsExcludedFontsSmartFilterRow
        )
    }

    private func recordFindAnchor(for event: NSEvent, outlineView: NSOutlineView) {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row = outlineView.row(at: point)
        guard row >= 0 else { return }
        if isPointInDisclosureZone(point: point, row: row, outlineView: outlineView) {
            lastFindAnchor = (row, nil)
            return
        }
        let columnIndex = outlineView.column(at: point)
        lastFindAnchor = (row, columnAtIndex(columnIndex, in: outlineView))
    }

    /// Cmd-click on a URL cell opens the link without changing selection.
    func tryOpenLink(at point: NSPoint, in outlineView: NSOutlineView) -> Bool {
        let row = outlineView.row(at: point)
        guard row >= 0 else { return false }
        if isPointInDisclosureZone(point: point, row: row, outlineView: outlineView) { return false }
        let columnIndex = outlineView.column(at: point)
        guard let column = columnAtIndex(columnIndex, in: outlineView), column.isWebURLColumn else { return false }
        guard let cell = outlineView.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? FontOutlineTextCellView else {
            return false
        }
        return cell.openLinkIfPresent()
    }

    private func columnAtIndex(_ index: Int, in outlineView: NSOutlineView) -> FontListColumn? {
        guard index >= 0, index < outlineView.tableColumns.count else { return nil }
        return columnForIdentifier(outlineView.tableColumns[index].identifier)
    }

    private func isPointInDisclosureZone(point: NSPoint, row: Int, outlineView: NSOutlineView) -> Bool {
        guard groupByFamily,
              let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) else { return false }
        let local = outlineView.convert(point, to: rowView)
        let level = outlineView.level(forRow: row)
        let chevronMaxX = FontListOutlineChrome.disclosureHitMaxX(
            indentationPerLevel: outlineView.indentationPerLevel,
            level: level
        )
        return local.x <= chevronMaxX + 4
    }
}

// MARK: - NSOutlineViewDataSource

extension FontListOutlineCoordinator: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNodes.count }
        if let node = item as? FontListOutlineNode {
            if node.isFamily { return node.childCount }
            return 0
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? FontListOutlineNode {
            if node.isFamily {
                if !node.isChildrenLoaded {
                    loadFamilyChildrenIfNeeded(node: node, outlineView: outlineView)
                }
                if let children = node.children, index < children.count {
                    return children[index]
                }
            }
            return node
        }
        return rootNodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FontListOutlineNode)?.isFamily ?? false
    }
}

// MARK: - NSOutlineViewDelegate

extension FontListOutlineCoordinator: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let tableColumn,
              let column = columnForIdentifier(tableColumn.identifier),
              let node = item as? FontListOutlineNode else { return nil }

        if !groupByFamily {
            let row = outlineView.row(forItem: item)
            if row >= 0 {
                appState?.appendFlatPageIfNeeded(currentRow: row)
            }
        }

        let payload = resolvedPayload(for: node)
        let dimExcluded = dimmedExcludedAppearance(for: node)

        if column == .name {
            if let presentation = column.nameCellPresentation(for: payload, showFamilySubtitle: showFamilySubtitle) {
                return nameCell(
                    outlineView: outlineView,
                    primary: presentation.primary,
                    secondary: presentation.secondary,
                    familyHeader: presentation.isFamilyHeader,
                    dimmedExcluded: dimExcluded,
                    showVariableDot: showVariableDot(for: payload)
                )
            }
            if case .font(let font) = payload {
                return nameCell(
                    outlineView: outlineView,
                    primary: font.fullName,
                    secondary: showFamilySubtitle && !font.preferredFamily.isEmpty ? font.preferredFamily : nil,
                    familyHeader: false,
                    dimmedExcluded: dimExcluded,
                    showVariableDot: font.isVariable
                )
            }
        }

        if column == .format {
            let format: FontFormat
            let isVariable: Bool
            let mixExtensions: [String]
            switch payload {
            case .font(let font):
                format = FontFormat.from(pathExtension: font.format)
                isVariable = font.isVariable
                mixExtensions = []
            case .family(let section):
                format = FontFormat.aggregate(forFormatStrings: section.distinctFormats)
                isVariable = false
                mixExtensions = section.distinctFormats
            case .fontPath:
                format = .unknown
                isVariable = false
                mixExtensions = []
            }
            return formatBadgeCell(
                outlineView: outlineView,
                format: format,
                isVariable: isVariable,
                mixFormatExtensions: mixExtensions,
                dimmedExcluded: dimExcluded
            )
        }

        let presentation = cellPresentation(
            for: column,
            payload: payload,
            node: node,
            showFamilySubtitle: showFamilySubtitle
        )
        let emphasized = node.isFamily && column == .name
        return textCell(
            outlineView: outlineView,
            column: column,
            presentation: presentation,
            trailing: column.isTrailing,
            emphasized: emphasized,
            showsTooltip: column == .name || presentation.showsMetadataAttention || presentation.showsLink,
            dimmedExcluded: dimExcluded
        )
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? FontListOutlineNode else {
            return FontListRowMetrics.rowHeight(density: rowDensity, isFamily: false)
        }
        return FontListRowMetrics.rowHeight(density: rowDensity, isFamily: node.isFamily)
    }

    private func nameCell(
        outlineView: NSOutlineView,
        primary: String,
        secondary: String?,
        familyHeader: Bool,
        dimmedExcluded: Bool = false,
        showVariableDot: Bool = false
    ) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("FontVaultOutlineCell.name")
        let cell: FontOutlineNameCellView
        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? FontOutlineNameCellView {
            cell = reused
        } else {
            cell = FontOutlineNameCellView(frame: .zero)
            cell.identifier = cellID
        }
        cell.configure(
            primary: primary,
            secondary: secondary,
            familyHeader: familyHeader,
            dimmedExcluded: dimmedExcluded,
            showVariableDot: showVariableDot
        )
        return cell
    }

    private func showVariableDot(for payload: FontListOutlineItem) -> Bool {
        switch payload {
        case .font(let font):
            return font.isVariable
        default:
            return false
        }
    }

    private func formatBadgeCell(
        outlineView: NSOutlineView,
        format: FontFormat,
        isVariable: Bool = false,
        mixFormatExtensions: [String] = [],
        dimmedExcluded: Bool = false
    ) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("FontVaultOutlineCell.formatBadge")
        let cell: FontOutlineFormatBadgeCellView
        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? FontOutlineFormatBadgeCellView {
            cell = reused
        } else {
            cell = FontOutlineFormatBadgeCellView(frame: .zero)
            cell.identifier = cellID
        }
        cell.configure(
            format: format,
            isVariable: isVariable,
            mixFormatExtensions: mixFormatExtensions,
            dimmedExcluded: dimmedExcluded
        )
        return cell
    }

    private func cellPresentation(
        for column: FontListColumn,
        payload: FontListOutlineItem,
        node: FontListOutlineNode,
        showFamilySubtitle: Bool
    ) -> FontListCellPresentation {
        switch payload {
        case .font(let font):
            return column.fontCellPresentation(for: font)
        case .family(let section):
            let loadedFonts = loadedFonts(forFamilyNode: node)
            return node.familyFieldState(
                column: column,
                section: section,
                loadedFonts: loadedFonts
            )
            .cellPresentation(columnTitle: column.title)
            .applyingLinkStyleIfNeeded(column: column)
        case .fontPath(let path):
            if let font = appState?.catalogFont(forVaultPath: path) {
                return column.fontCellPresentation(for: font)
            }
            if column == .path {
                return FontListCellPresentation(text: path)
            }
            return FontListCellPresentation(text: "")
        }
    }

    /// Child rows under an expanded family (for aggregating Style, Designer, etc.).
    private func loadedFonts(forFamilyNode node: FontListOutlineNode) -> [FontRecord] {
        if case .family(let section) = node.payload, !section.fonts.isEmpty {
            return section.fonts
        }
        guard let children = node.children else { return [] }
        return children.compactMap { child in
            switch child.payload {
            case .font(let font):
                return font
            case .fontPath(let path):
                return appState?.catalogFont(forVaultPath: path)
            case .family:
                return nil
            }
        }
    }

    private func textCell(
        outlineView: NSOutlineView,
        column: FontListColumn,
        presentation: FontListCellPresentation,
        trailing: Bool,
        emphasized: Bool,
        showsTooltip: Bool,
        dimmedExcluded: Bool = false
    ) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("FontVaultOutlineCell.\(column.rawValue)")
        let cell: FontOutlineTextCellView
        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? FontOutlineTextCellView {
            cell = reused
        } else {
            cell = FontOutlineTextCellView(frame: .zero)
            cell.identifier = cellID
        }
        cell.configure(
            presentation: presentation,
            trailing: trailing,
            emphasized: emphasized,
            showsTooltip: showsTooltip,
            dimmedExcluded: dimmedExcluded
        )
        return cell
    }

    private func dimmedExcludedAppearance(for node: FontListOutlineNode) -> Bool {
        guard appState?.settings.showIgnoredFonts == true else { return false }
        return FontListExcludedAppearance.shouldDim(
            item: resolvedPayload(for: node),
            showIgnoredFonts: true
        )
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView else { return }
        refreshVisibleRowBackgrounds(in: outlineView)
        publishSelection(from: outlineView)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is FontListOutlineNode
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = FontListOutlineRowView()
        rowView.hostingOutlineView = tableView as? NSOutlineView
        return rowView
    }

    func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        applyAlternatingRowBackground(rowView, row: row, outlineView: outlineView)
        applyDisclosureTint(rowView, row: row, outlineView: outlineView)
    }

    func outlineView(_ outlineView: NSOutlineView, didRemove rowView: NSTableRowView, forRow row: Int) {}

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        true
    }

    private func refreshVisibleRowBackgrounds(in outlineView: NSOutlineView) {
        let visible = outlineView.rows(in: outlineView.visibleRect)
        guard visible.length > 0 else { return }
        for row in visible.location ..< NSMaxRange(visible) {
            guard let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) else { continue }
            applyAlternatingRowBackground(rowView, row: row, outlineView: outlineView)
            applyDisclosureTint(rowView, row: row, outlineView: outlineView)
        }
    }

    private func applyDisclosureTint(
        _ rowView: NSTableRowView,
        row: Int,
        outlineView: NSOutlineView
    ) {
        FontListOutlineChrome.applyDisclosureTint(
            to: rowView,
            level: outlineView.level(forRow: row),
            indentationPerLevel: outlineView.indentationPerLevel,
            appearance: outlineView.effectiveAppearance
        )
    }

    func retintVisibleDisclosureControls() {
        guard let outlineView else { return }
        let visible = outlineView.rows(in: outlineView.visibleRect)
        guard visible.length > 0 else { return }
        for row in visible.location ..< NSMaxRange(visible) {
            guard let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) else { continue }
            applyDisclosureTint(rowView, row: row, outlineView: outlineView)
        }
    }

    private func applyAlternatingRowBackground(
        _ rowView: NSTableRowView,
        row: Int,
        outlineView: NSOutlineView
    ) {
        let colors = NSColor.alternatingContentBackgroundColors
        guard colors.count >= 2 else { return }
        let selected = outlineView.selectedRowIndexes.contains(row)
        if selected {
            rowView.backgroundColor = .unemphasizedSelectedContentBackgroundColor
        } else {
            rowView.backgroundColor = colors[row % colors.count]
        }
        rowView.alphaValue = 1
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FontListOutlineNode,
              let familyID = node.familyID,
              let appState,
              let outlineView else { return }
        if isProgrammaticExpansionChange {
            rebuildRowIndex()
            return
        }
        loadFamilyChildrenIfNeeded(node: node, outlineView: outlineView)
        outlineDrivingExpansionChange = true
        appState.collapsedFamilies.remove(familyID)
        outlineDrivingExpansionChange = false
        rebuildRowIndex()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FontListOutlineNode,
              let familyID = node.familyID,
              let appState else { return }
        if isProgrammaticExpansionChange { return }
        outlineDrivingExpansionChange = true
        appState.collapsedFamilies.insert(familyID)
        outlineDrivingExpansionChange = false
        rebuildRowIndex()
    }

    func outlineViewColumnDidResize(_ notification: Notification) {
        guard !isBatchingColumnChanges,
              let appState,
              let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              let column = columnForIdentifier(tableColumn.identifier) else { return }
        appState.settings.setColumnWidth(column, width: tableColumn.width)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
        guard columnIndex >= 0, columnIndex < outlineView.tableColumns.count else { return true }
        guard let column = columnForIdentifier(outlineView.tableColumns[columnIndex].identifier) else {
            return true
        }
        if column == .name { return false }
        if newColumnIndex == 0 { return false }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, mouseDownInHeaderOf tableColumn: NSTableColumn) {
        guard let column = columnForIdentifier(tableColumn.identifier),
              let appState,
              let event = NSApp.currentEvent,
              event.type != .rightMouseDown,
              event.type != .otherMouseDown,
              !isEventInColumnResizeZone(event, outlineView: outlineView) else { return }
        deferToNextRunLoop { [weak self, weak appState] in
            guard let self, let appState else { return }
            if appState.sortColumn == column.databaseSortColumn {
                appState.sortAscending.toggle()
            } else {
                appState.sortColumn = column.databaseSortColumn
                appState.sortAscending = true
            }
            self.sortColumn = appState.sortColumn
            self.sortAscending = appState.sortAscending
            self.updateSortIndicators()
            appState.scheduleRefreshList()
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard importDropAllowed(info.draggingPasteboard) else { return [] }
        return .copy
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard importDropAllowed(info.draggingPasteboard) else { return false }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL], !urls.isEmpty else { return false }

        Task { @MainActor [weak appState] in
            await appState?.importDroppedURLs(urls)
        }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, menuFor event: NSEvent) -> NSMenu? {
        contextMenu(for: event, outlineView: outlineView)
    }

    private func importDropAllowed(_ pasteboard: NSPasteboard) -> Bool {
        if VaultSettings.shared.organizesVaultFiles == false { return false }
        if appState?.isExportDragInProgress == true { return false }
        if FontVaultDragTypes.isExportDrag(pasteboard) { return false }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return false }
        guard let appState else { return false }
        return urls.contains { !appState.isURLInsideVault($0) }
    }
}

// MARK: - Export drag source (Finder copy)

extension FontListOutlineCoordinator: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return .copy
        case .withinApplication:
            return []
        @unknown default:
            return []
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint
    ) {
        guard activeExportDragFileCount > 1,
              let outlineView else { return }
        let badge = FontExportDragBadge.image(count: activeExportDragFileCount)
        let frame = NSRect(origin: .zero, size: FontExportDragBadge.dragImageSize)
        session.draggingFormation = .pile
        session.enumerateDraggingItems(
            for: outlineView,
            classes: [NSObject.self],
            searchOptions: [:]
        ) { item, index, _ in
            if index == 0 {
                item.setDraggingFrame(frame, contents: badge)
            } else {
                item.setDraggingFrame(.zero, contents: nil)
            }
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        activeExportDragFileCount = 0
        appState?.endExportDragSession(operation: operation)
    }
}

// MARK: - Menus

extension FontListOutlineCoordinator {
    /// Column customize menu (header right-click).
    func columnHeaderContextMenu() -> NSMenu {
        columnHeaderMenu()
    }

    private func columnHeaderMenu() -> NSMenu {
        let menu = NSMenu()
        guard let appState else { return menu }
        let settings = appState.settings

        for column in FontListColumn.allCases {
            let item = NSMenuItem(
                title: column.title,
                action: #selector(toggleColumnVisibility(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = column
            item.state = settings.isListColumnVisible(column) ? .on : .off
            item.isEnabled = !column.isRequired
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let fontTableItem = NSMenuItem(
            title: AppMenuCopy.fontTable,
            action: #selector(openFontTableSettings(_:)),
            keyEquivalent: ""
        )
        fontTableItem.target = self
        menu.addItem(fontTableItem)
        let resetWidthsItem = NSMenuItem(
            title: AppMenuCopy.resetColumnWidths,
            action: #selector(resetColumnWidths),
            keyEquivalent: ""
        )
        resetWidthsItem.target = self
        menu.addItem(resetWidthsItem)
        for item in menu.items where item.action != nil && item.target == nil {
            item.target = self
        }
        return menu
    }

    @objc func showInInformation() {
        appState?.showInspector = true
    }

    @objc func hideInInformation() {
        appState?.showInspector = false
    }

    @objc func showMetadataIssueInInformation() {
        appState?.showInspector = true
    }

    @objc func copyMetadataIssueSummary() {
        guard let text = lastContextMenuContext?.metadataIssueSummary() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func performContextMenuCopy(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = FontListContextMenuCopyKind(rawValue: raw),
              let text = lastContextMenuContext?.copyText(for: kind) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func performContextMenuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let context = lastContextMenuContext,
              let appState else { return }

        if let filterKey = FontListContextMenuActionKind.parseShowOnlyFormatKey(raw) {
            appState.selectSidebarItem(.format(filterKey: filterKey))
            return
        }

        guard let action = FontListContextMenuActionKind(rawValue: raw) else { return }
        switch action {
        case .openURL:
            if let url = context.urlIfValid {
                NSWorkspace.shared.open(url)
            }
        case .copyURL:
            if let url = context.urlIfValid {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        case .find:
            if let text = context.findText {
                appState.searchText = text
                appState.focusSearchField()
            }
        case .showOnlyFormat:
            break
        case .clearFormatFilter:
            appState.selectSidebarItem(.allFonts)
        case .smartFilterExcludedFonts:
            appState.selectSidebarItem(.smartFilter(.excludedFonts))
        }
    }

    @objc private func toggleColumnVisibility(_ sender: NSMenuItem) {
        guard let column = sender.representedObject as? FontListColumn,
              let appState,
              let outlineView else { return }
        let settings = appState.settings
        let visible = settings.isListColumnVisible(column)
        settings.setListColumnVisible(column, visible: !visible)
        displayColumns = Self.visibleColumns(from: settings)
        syncColumnVisibility(settings: settings, outlineView: outlineView)
        updateSortIndicators()
    }

    @objc private func openFontTableSettings(_ sender: Any?) {
        guard let appState else { return }
        // Defer until after the context menu closes so Settings can take focus.
        DispatchQueue.main.async {
            appState.openSettings(tab: .fontTable)
        }
    }
    @objc private func resetColumnWidths() {
        guard let appState, let outlineView else { return }
        isBatchingColumnChanges = true
        defer { isBatchingColumnChanges = false }
        appState.settings.resetListColumnWidths()
        for tableColumn in outlineView.tableColumns {
            if let column = columnForIdentifier(tableColumn.identifier) {
                tableColumn.width = appState.settings.columnWidth(for: column)
            }
        }
    }

    @objc func expandAllFamilies() { appState?.expandAllFamilies() }
    @objc func collapseAllFamilies() { appState?.collapseAllFamilies() }
    @objc func selectAllFamilies() { appState?.selectAllFamiliesInFilter() }
    @objc func selectAllFontsDeep() { appState?.selectAllFontsDeepInFilter() }
    @objc func deselectAll() { appState?.deselectAll() }
    @objc func revealInFinder() { appState?.revealSelectedInFinder() }
    @objc func openInInspectorWindow() { appState?.presentFontInspectorForSelection() }
    @objc func exportSelected() { appState?.presentExportSelected() }
    @objc func excludeFromIndex() { appState?.presentExcludeSelectedFromIndex() }
    @objc func includeInIndex() { appState?.includeSelectedInIndex() }
    @objc func removeToTrash() { appState?.presentRemoveSelected(moveToTrash: true) }
    @objc func deleteImmediately() { appState?.presentRemoveSelected(moveToTrash: false) }
}
