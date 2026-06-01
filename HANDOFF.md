# Font Vault — agent handoff

**Last updated:** 2026-05-30  
**Purpose:** Onboard a fresh chat without re-reading full transcript history.  
**Living backlog:** [`NOTES.md`](NOTES.md) · **Phase 2a exclusion:** [`PHASE2_SPEC.md`](PHASE2_SPEC.md)  
**Archived (reference):** [`../_misc/_archive/FontVaultDevelopment/`](../_misc/_archive/FontVaultDevelopment/) — FEX gap analysis, design spec, mockup, GUI docx, review brief

---

## Build & run

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme FontVault \
  -project FontVault/FontVault.xcodeproj \
  -destination 'platform=macOS' build
```

- **App target:** builds clean (macOS 14.4+, Swift, GRDB).
- **Test target:** `FontTableBinaryReaderTests.swift` in `FontVaultTests` group; `CatalogBrowseTests` uses `CatalogStore.makeInMemoryForTests()` (full migrations). **⌘U passes** as of 2026-05-30.

Default vault: `Documents/FontVault` · catalog: `.fontvault/catalog.sqlite`.

---

## Architecture (current)

| Layer | Tech |
|-------|------|
| Shell | SwiftUI — sidebar, search, inspector, settings, menus |
| Font list | AppKit `NSOutlineView` — `FontListOutlineHost`, `FontListOutlineCoordinator`, `FontListOutlineCells` |
| Data | `CatalogStore` + GRDB, windowed browse (`FontTableBrowseQuery`, `CatalogBrowseSQL`) |
| Selection bus | `ListSelectionDisplay` — narrow invalidation for inspector/status |

**Do not** reintroduce SwiftUI `Table` for the main list.

---

## Recently shipped (context menu + list polish)

### Phases 0–3 + family copy (baseline)

- [`NOTES.md`](NOTES.md) § Context menu and status bar — menu order, copy dedupe, family header copy, status bar priority.
- Key files: `FontListContextMenuContext.swift`, `FontListContextMenuBuilder.swift`, `ListStatusDetail.swift`, coordinator `contextMenu(for:)`.

### Phases 4–6 (2026-05-30)

| Feature | Implementation |
|---------|----------------|
| URL cells | Blue link underline via `FontListCellPresentation.applyingLinkStyleIfNeeded` + `FontListURLParsing` |
| Context menu URL | Open URL, Copy URL (deduped single URL) |
| Context menu Filter ▸ | Show Only {format}, Clear Format Filter; **Show Only Excluded Fonts** only when `showsExcludedFontsSmartFilter` (same as sidebar: Show Ignored on + `excludedFontCount > 0`) |
| Find | Find “{value}” → `searchText` + `focusSearchField()` |
| ⌘-click URL | `FontListOutlineHost` → `tryOpenLink` / `FontOutlineTextCellView.openLinkIfPresent()` |
| Metadata attention | **Orange underline on text** (not full-cell border); distinct from blue URLs |
| View menu | Show/Hide Ignored Fonts is a **Button** (no checkmark), ⇧⌘I |

### Incident note

`FontListOutlineCells.swift` was briefly corrupted during Phase 4; recovered from agent transcript. If cells look wrong, diff against git or transcript — do not rewrite the whole file casually.

### Cleanup

- `FontListTableView.swift` **deleted** (legacy SwiftUI table; was not in target).
- `FontTableRow.swift` **removed** (2026-05-30) — legacy SwiftUI `Table` row model; list uses AppKit outline only.

### Status bar refinement (2026-05-30)

| Area | Shipped |
|------|---------|
| **Four zones** | Visible (`tablecells` + cap `N / M` + optional `· OTF`), selection glance, cell `Column: value`, warning icon only |
| **Tooltips** | Full strings on `.help` / accessibility; selection/family breakdown unchanged in tooltip |
| **Column-scoped warnings** | `ListStatusDetail.metadataWarning` only when hovered/selected column maps to issue field |
| **Selection column** | Single-font selection uses coordinator `lastFindAnchor` column (not hardcoded PostScript) |

Key files: `StatusBarCopy.swift`, `ListStatusDetail.swift`, `StatusBarView` in `MainWindowView.swift`, `AppState.refreshSelectionCache`, `FontListOutlineCoordinator.updateHoverStatus`.

### Import/export + persistence (2026-05-30)

| Area | Shipped |
|------|---------|
| **Settings vs panels** | `VaultSettings` holds import formats, copy/move, export layout, column order/visibility/widths. **File → Import/Export** pre-fill from Settings; choices are **one-shot** (no write-back). Drag-and-drop import uses Settings only. |
| **Font table columns** | Header drag reorders (Name fixed at index 0); order + widths persist; Settings and header share the same prefs. |
| **Import panel** | Three format groups (Core Text extensions only); copy/move; `NSOpenPanel.allowedContentTypes` from checkboxes (updates when accessory toggles); folder scan still uses checkboxes. |
| **Import summary** | `ImportResult` counts files ignored (unsupported extension vs filtered format); status line, progress completion, and small-import alert. |
| **Export panel** | Family / vault / flat radios only (compact accessory); layout detail remains in Settings. |
| **Import report (v1)** | **View Details…** on completion when failed/skipped; `ImportReportSheet` — no quarantine, no per-success rows (2026-05-31). |
| **Also shipped (2026-05-31)** | Drag-out honors `exportLayoutMode`; ⌘F Find prefills from list cell; expanded context menu tests. |

Key files: `ImportFormatOptions.swift`, `FontImportPanel.swift`, `FontExportPanel.swift`, `VaultSettings.swift`, `VaultCoordinator.swift` (`collectFontFiles` / `ImportResult.summaryText`), `FontListOutlineCoordinator.swift`.

---

## Excluded / ignored fonts (product model)

Three concepts — **do not conflate in UI copy or SQL**:

| Concept | Control | Effect |
|---------|---------|--------|
| `excludedFromIndex` flag | Exclude/Include in Index (context menu) | Font skipped from index when enforce setting on |
| Show Ignored Fonts | View menu Button (⇧⌘I) | When off, All Fonts hides excluded rows; when on, dimmed + nosign |
| Excluded Fonts filter | Sidebar Smart Filters + context Filter ▸ (gated) | Only `excludedFromIndex = 1` |

Spec: [`PHASE2_SPEC.md`](PHASE2_SPEC.md).

---

## Open work (prioritized for next agent)

### P0 — CI / hygiene

- [x] Fix **FontVaultTests** pbxproj path for `FontTableBinaryReaderTests.swift` (2026-05-30).
- [x] Remove orphan **`FontTableRow.swift`** (2026-05-30).

### P1 — FEX daily parity (see also archived [`FEX_GAP_ANALYSIS.md`](../_misc/_archive/FontVaultDevelopment/FEX_GAP_ANALYSIS.md))

- [x] **Column reorder + persistence** — AppKit header drag; `listColumnOrder` / widths in UserDefaults; header drag syncs settings (2026-05-30).
- [x] **Import/export panels + settings persistence** — one-shot panels; UTType filter; ignored-format counts; compact export accessory (2026-05-30).
- [x] **Import report sheet (v1)** — failed/skipped detail sheet, Reveal, copy/save failure list (2026-05-31).
- [ ] **Import duplicate policies** (path / same font / keep both).
- [ ] **Missing/broken file** row state + integrity pass.
- [ ] **Open in Typeface / FontBase** — menu / URL handoff (not the same as double-click).
- [x] **Double-click font row** → font inspector window (`presentFontInspector`).
- [ ] **PostScript-name duplicate** conflicts (beyond SHA-256).
- [x] **WOFF/WOFF2** sidebar Format rows (when present in catalog; `sidebarFormats`).

### P2 — Polish

- [x] **Status bar refinement** — four zones, glance + tooltips, column-scoped warning icon (2026-05-30).
- [ ] **Phase 5b smart filters** — only `SmartFilterID.excludedFonts` today; catalog/SQL scopes needed for variable fonts, incomplete metadata, etc. **Do not** add Filter ▸ items without sidebar parity + product list.
- [ ] **Edit → Find** prefilled from selection (optional; Phase 5 closure did not require).
- [~] **Context menu tests** — `FontListContextMenuContextTests` covers context **logic** (URL/find/format options); expand for `AppMenuCopy` **menu titles** and Filter ▸ Excluded gate — see NOTES § Context menu test coverage.
- [ ] **Inspector** layout / empty state.
- [ ] **Index at ~200k** — batched index OK; duplicate scan still full catalog load.
- [ ] **Prettier list rows** — ongoing mockup alignment.

### P3 — Later

- Export zip/disk image, `.fexdb` read-only import, TTC face disclosure, Help menu expansion — see NOTES parking lot.

### Explicitly out of scope (unless user expands)

- Writing to FEX `.fexdb`
- User-defined smart filter editor (Phase 2b+)
- Non-macOS

---

## Key file map (context menu / list)

```
FontVault/Views/
  FontListOutlineHost.swift      # mouse, ⌘-click URL, tracking hover
  FontListOutlineCoordinator.swift # cells, context menu, selection, hover status
  FontListOutlineCells.swift     # name, format badge, text cell styling
  FontListContextMenuBuilder.swift
FontVault/Models/
  FontListContextMenuContext.swift
  FontListContextMenuActionKind.swift
  FontListCellPresentation.swift
  FontListURLParsing.swift
  ListStatusDetail.swift
  AppMenuCopy.swift
FontVault/AppState.swift         # selectSidebarItem, tableBrowseQuery, showIgnoredFonts
```

---

## Plans (Cursor; do not edit unless user asks)

| Plan | Status |
|------|--------|
| `context_menu_and_status_bar` | Phases 0–3 done |
| `context_menu_phases_4-6` | **Done** (2026-05-30) |

---

## FEX reference bundle (optional, local)

`FontVault/FontExplorer X Pro.app/` may sit beside the Xcode project as a **read-only reference** to FontExplorer X Pro (strings, UI copy, behavior notes). It is **gitignored** and **not** part of the Font Vault target — do not edit files inside the bundle or treat it as app source.

When comparing to FEX, inspect **inside the `.app` package** (e.g. `Contents/Resources/*.lproj/Localizable.strings`, nibs, Info.plist), not the `FontVault/` Swift tree. If the bundle is absent, use an installed copy under `/Applications/` the same way.

---

## Conventions for agents

- **Minimize diff** — match existing patterns (`AppMenuCopy`, coordinator `@objc` handlers, `representedObject` raw strings).
- **Commits** — only when user asks.
- **Full Xcode path** — `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for `xcodebuild`.
- **User rules** — no plan file edits; code citations use `startLine:endLine:path`.

---

## Suggested first message in new chat

> Read `FontVault/HANDOFF.md` and `FontVault/NOTES.md` backlog. I want to work on [P1 item from open work].
