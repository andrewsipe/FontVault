# Font Vault — notes & backlog

Living document for polish, features, and refinements discovered during development and testing.  
Not everything here is urgent — capture ideas so they are not lost when context shifts.

**Last updated:** 2026-05-30

**New chat?** Start with [`HANDOFF.md`](HANDOFF.md) (architecture, shipped work, open todos). Design/FEX/mockup docs: [`../_misc/_archive/FontVaultDevelopment/`](../_misc/_archive/FontVaultDevelopment/).

---

## Open todos (tight list)

Use full tables below for detail; this is the **action queue** for the next build.

| Priority | Item | Where |
|----------|------|--------|
| ~~P0~~ | ~~Fix test target: `FontTableBinaryReaderTests.swift` path~~ | Done 2026-05-30 — file ref in `FontVaultTests` group |
| ~~P0~~ | ~~Delete orphan `FontTableRow.swift`~~ | Done 2026-05-30 — legacy SwiftUI table row model |
| ~~P1~~ | ~~Column reorder / persistence~~ | Header drag (AppKit) + Settings; order/widths in UserDefaults (2026-05-30) |
| ~~P1~~ | ~~Import/export panels + settings persistence~~ | Done 2026-05-30 — § Persistence policy; UTType filter; ignored-format summary; compact export accessory |
| ~~P1~~ | ~~Import report sheet~~ | Done 2026-05-31 — View Details sheet: failed/skipped rows, Reveal, copy/save failure list (no quarantine) |
| P1 | Import duplicate policies | NOTES Settings |
| P1 | Missing/broken file row state | NOTES Technical |
| P1 | Open in Typeface / FontBase (menu handoff) | Not double-click — inspector window ships |
| P1 | PostScript duplicate conflicts | Duplicates |
| ~~P1~~ | ~~WOFF/WOFF2 sidebar format chips~~ | Done — `sidebarFormats` includes woff/woff2 when catalog has them |
| P2 | Smart filter catalog beyond Excluded Fonts (Phase 5b) | `SmartFilterID`, `FontTableBrowseScope`, SQL |
| ~~P2~~ | ~~Edit → Find prefilled from selection~~ | Done 2026-05-31 — ⌘F uses same rules as context menu Find |
| ~~P2~~ | ~~Expand context menu tests~~ | Done 2026-05-31 — builder titles + Filter gate tests |
| P2 | Index / duplicate scan at ~200k | Phase 6 in architecture table `[~]` |
| P2 | Inspector layout, app icon, list row polish | NOTES Polish |
| ~~P2~~ | ~~**Status bar refinement**~~ | Done 2026-05-30 — four zones, glance + tooltips, column-scoped warnings — see § Status bar refinement |
| P2 | **Help menu / in-app help** | Full expansion beyond vault-organization alert (import, export, persistence, shortcuts) |

**Done recently (do not re-implement):** P0 test target + `CatalogBrowseTests` on production migrations; AppKit list; context menu Phases 0–6; metadata **orange text underline**; URL blue links + ⌘-click; Filter ▸ Excluded gated on Show Ignored + sidebar row; View menu Show/Hide Ignored without checkmark; **double-click font row → inspector window**; **import/export + persistence** (Settings = defaults; panels one-shot; column order/widths persist; import UTTypes + ignored-file counts; compact export radios); **status bar four-zone refinement** (2026-05-30).

---

## Context menu test coverage (P2)

Shipped behavior is split across two types:

| Layer | File | Role |
|-------|------|------|
| **Logic** | `FontListContextMenuContext` | Eligibility: `urlIfValid`, `canFind` / `findText`, `formatFilterMenuOptions`, `showsClearFormatFilter`, `showsExcludedFontsSmartFilter` |
| **Presentation** | `FontListContextMenuBuilder` | Builds `NSMenu` titles via `AppMenuCopy` (e.g. `Find "…"`, `Show Only OTF`, `Show Only Excluded Fonts`) |

**`FontListContextMenuContextTests` today (logic only):**

- URL: one distinct http(s) value enables Open/Copy; multi-select with different URLs disables.
- Find: one non-empty cell value → `findText`; no clicked column → `canFind` false.
- Filter: format column on font row → one OTF option (`filterKey` + badge label).

**Still untested (why backlog says “expand”):**

- **Menu titles** — strings users see (`AppMenuCopy.findValue`, `showOnlyFormat`, `showOnlySmartFilter`) are assembled in the builder, not asserted in tests.
- **Excluded Fonts filter item** — `showsExcludedFontsSmartFilter` true/false should control whether the Filter ▸ row appears (must match sidebar gate).
- **Clear Format Filter** — visible only when `activeFormatFilter != nil` and format column clicked.
- **Family header** — mixed-format Filter submenu (multiple chips), URL/copy on aggregated family cells.
- **Optional:** thin tests on `FontListContextMenuBuilder` menu item titles, or golden-title helpers extracted from the builder.

Context menu **behavior** is manual-QA’d per NOTES § Phases 4–6; unit tests guard the context struct only.

---

## Persistence policy (Settings vs one-shot UI)

| Feature | Persistent source | Ephemeral override |
|---------|-------------------|-------------------|
| **Font table columns** | `VaultSettings.listColumnOrder` (+ visibility, widths) | None — last change in **Settings** or **header** updates the same stored prefs |
| **Export layout** | `VaultSettings.exportLayoutMode` (Settings → Export defaults) | **File → Export Fonts…** — pre-filled; one-shot (does not write back) |
| **Import formats + copy/move** | `VaultSettings.importFormats`, `importOperation` (Settings → Import defaults) | **File → Import Fonts…** — pre-filled; one-shot (does not write back). **Drag-and-drop** uses Settings only. |
| **Drag-out export** | `VaultSettings.exportLayoutMode` | Same layout modes as File → Export (2026-05-31) |

**Font table:** one truth; last editor wins.

**Import / export panels:** settings = default habit; panel = deliberate choice for that run.

**Drag-and-drop import:** always uses Settings (no panel).

**Status (2026-05-30):** Implemented. File → Import/Export pre-fill from Settings and do **not** write back. Header column drag persists `listColumnOrder` / widths (Name stays first). Import open panel sets `allowedContentTypes` from format checkboxes (live update in accessory). Folder scan still honors checkboxes; status/alert report files ignored (unsupported extension or filtered format).

---

## Vault folder layout (FEX parity)

On-disk style folders use **OpenType name ID 4 (Full name)**, matching FontExplorer X — not Family + Style (IDs 1 + 2) and not typographic IDs 16 + 17.

### Catalog columns (literal vs preferred)

| Column | Meaning |
|--------|---------|
| **Name** | Preferred full name (ID 4 from name table, then Core Text / compose / PostScript fallbacks) |
| **Family** | Preferred family (ID 16 when present, else ID 1) — matches FEX “Family Name” |
| **Font Family (ID 1)** | Literal ID 1 only |
| **Full Name (ID 4)** | Literal ID 4 only (blank when missing) |
| **Typographic Family / Style** | Literal IDs 16 / 17 only (no fallback to 1 / 2) |
| **Vendor ID** | Literal OS/2 `achVendID` |
| **Vendor** | Microsoft registry name, or `Unknown` when the tag is set but not registered |

After upgrading metadata handling, run **Rebuild Catalog** so old rows lose derived typographic copies and vendor IDs re-parse correctly (`catalogMetadataVersion` 9).

If ID 4 is not viable (control characters, `.`, placeholders, leading `/ : . _ - &`, etc.), the vault folder falls back to the **filename stem**, then `Unknown`. Imports are never blocked for bad names.

After upgrading layout logic, run **Vault → Reorganize Vault** (or re-import) so existing libraries (e.g. ABC Honeymoon mis-labeled as `… Italic`) move to the correct folders.

---

## Launch sequence (FEX-style gate)

After onboarding, `RootView` shows `LaunchProgressView` until `AppState.launchPhase == .ready`, then `MainWindowView`.

| Step | Status message | Work |
|------|----------------|------|
| 1 | Opening catalog… | `VaultCoordinator.reloadCatalog()` |
| 2 | Preparing font list… | `refreshListForLaunch()` — SQL counts + family summaries or flat paths only (no 2000-row preload) |
| 3 | — | `launchPhase = .ready` |
| Deferred (~300ms) | — | SQL `duplicateExtraFileCount()` for sidebar; optional preload of first ~40 flat paths |

**Not on boot:** `fetchAllFonts()`, full duplicate scan (runs when opening Duplicates or after import/rebuild).

**Grouped mode at launch:** all families start collapsed (`collapsedFamilies` = all family IDs) to avoid N+1 child SQL on first outline paint.

**Vault change:** Settings → pick vault folder resets launch phase and runs `startLaunch()` again.

### Launch manual test checklist

| Scenario | Expected |
|----------|----------|
| Empty vault | Brief sheet → main UI, 0 fonts |
| ~10k fonts, flat, all columns | Sheet ~1–3s → smooth main UI; CPU idle after open |
| Grouped, large vault | Families collapsed; expanding one loads only that family |
| Sidebar duplicate count | Appears within ~1s (SQL estimate), no hang |
| Open Duplicates | Full SHA-256 scan once |
| Import / Rebuild | `refreshDuplicateSummary()` still runs (may spike CPU on huge vaults) |
| Change vault folder | Launch gate runs again |
| Force-quit during launch | Retry on next open works |

---

## FEX vs Font Vault — list architecture (reference)

FontExplorer X (FEX) source is **not** in this repo. Comparison is from Font Vault behavior, project notes, and strings in the optional reference bundle `FontExplorer X Pro.app` (gitignored).

### What FEX does (font list)

| Area | FEX (FontExplorer X Pro) |
|------|---------------------------|
| **List UI** | AppKit **`NSOutlineView`** (`fontOutlineView` in binary) |
| **Row rendering** | **Virtualized** — only visible rows get views; data via `outlineView:objectValueForTableColumn:byItem:` / `viewForTableColumn:item:` |
| **Grouping** | Outline tree: `numberOfChildrenOfItem`, `isItemExpandable`, expand/collapse delegates |
| **Selection** | `outlineViewSelectionDidChange` — localized; does not rebuild the whole window |
| **Columns** | Per-column `NSTableColumn`; cells created for visible rows only |
| **Catalog** | Proprietary **`.fexdb`** (many tables, smart groups, activation, etc.) |
| **Files** | Organized Fonts Folder on disk (A–Z buckets, etc.) |

FEX does **not** materialize the full library as thousands of SwiftUI views. The outline asks the data layer for **one row at a time** when AppKit needs it.

### What Font Vault does today (v0.1)

| Area | Font Vault today |
|------|------------------|
| **Shell UI** | **SwiftUI** — window, sidebar, filter bar, inspector, settings, menus |
| **List UI** | **AppKit `NSOutlineView`** via `FontListOutlineHost` + coordinator (grouped + flat) |
| **Row rendering** | Virtualized AppKit cells; SQL windowing (family summaries + flat path paging) |
| **Selection** | Finder-style click in outline → `syncSelectionFromOutline`; `ListSelectionDisplay` for inspector/status |
| **Columns** | Header menu show/hide; AppKit format badge + styled name cells; resize/sort on headers |
| **Catalog** | **`{vault}/.fontvault/catalog.sqlite`** (GRDB) — intentionally **not** `.fexdb` |
| **Query cap** | **None** for browse — `filteredFontCount` + paged flat fetch |

### Target architecture (FEX-aligned, hybrid)

**Keep SwiftUI for the app shell. Replace only the font list surface with AppKit.**

```text
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI shell (unchanged)                                   │
│  Onboarding · NavigationSplitView · Sidebar · Inspector     │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  AppKit list host (NEW) — NSOutlineView (grouped) or         │
│  NSTableView (flat) via NSViewRepresentable                  │
│  · Virtualized rows                                          │
│  · Selection → narrow coordinator (not full AppState refresh)│
│  · Plain AppKit cells (text), not SwiftUI per cell           │
└───────────────────────────┬─────────────────────────────────┘
                            │ on-demand reads
┌───────────────────────────▼─────────────────────────────────┐
│  SQLite catalog (KEEP) — CatalogStore + GRDB                 │
│  · Windowed fetch (limit/offset or keyset) for visible rows  │
│  · Family headers via SQL/grouping or small in-memory index  │
│  · No change to vault files on disk                          │
└─────────────────────────────────────────────────────────────┘
```

| Layer | Change? | Notes |
|-------|---------|--------|
| **SwiftUI GUI (most of app)** | **No** | Same look & flows; list is one embedded AppKit view |
| **Font list only** | **Yes** | SwiftUI `Table` → `NSOutlineView` / `NSTableView` |
| **Database / catalog** | **Mostly no** | Same SQLite schema; add queries tuned for windowed list |
| **Vault files / layout** | **No** | FEX-compatible A–Z layout unchanged |
| **`.fexdb`** | **Out of scope** | Optional future read-only import for migration comparison |

### Observed performance

- **2026-05-25:** SwiftUI `Table` era — laggy with all columns at ~100 fonts (motivated AppKit migration).
- **2026-05-26 (P0 closed):** AppKit outline — **~9,939 fonts**, all columns, flat (grouping off): smooth scroll, no spinner, **~180 MB** RAM, nominal CPU. Column-perf hardening **deferred** until degradation is observed. Optional **200k** stress when vault grows.

### Implementation phases

| Phase | Work | Status |
|-------|------|--------|
| **1** | `NSOutlineView` + coordinator; flat + grouped; styled cells | `[x]` |
| **2** | Selection bus (narrow SwiftUI invalidation on select only) | `[x]` `ListSelectionDisplay` |
| **3** | SQL windowing + “Showing N of M” as normal browse model | `[x]` Phase 0 |
| **4** | Column visibility/order from `VaultSettings`; header context menu | `[x]` |
| **5** | Drag-out, sort headers, column resize (parity with today) | `[x]` |
| **6** | Index / duplicate scan at 200k (batch ops, no `fetchAllFonts` in UI) | `[~]` index batched; duplicate scan still full load |

### Default columns

Treat **Name, Format, Size, Import Date** as the default set for daily use. Extra metadata columns are inspector-first; many visible columns cost more layout work but list is AppKit-virtualized.

---

## Context menu and status bar (Phases 1–3)

Design for the font table row context menu and status bar detail. **Phases 4–6** shipped (see plan `context_menu_phases_4-6`).

### Status bar priority (highest wins)

**Left zones (always when not in progress):**

1. **Visible count** — `tablecells` icon, glance (`12 shown` or `2,000 / 9,412` when flat list is capped), optional inline `· OTF` when sidebar ≠ All Fonts; full filter context in tooltip (`StatusBarCopy`, `AppState.statusBarVisibleCount`).
2. **Selection** — `checkmark.circle`, compact `N sel · size`; full family/loose breakdown in tooltip (`selectionDisplay.summary`).
3. **Cell detail** — `Column: value` glance (`ListStatusDetail.glanceLine`); full value + optional link hint in tooltip (`tooltipLine`). Hover wins over selection when both set.
4. **Warning** — orange `exclamationmark.octagon.fill` when the row has issues: **icon only** on non-problem columns; **icon + issue label** on the problem column. Row-wide reasons in icon tooltip when not on the problem field. **View → Show/Hide Metadata Warnings** silences list, status bar, inspector, and Metadata menu (default on).

**Right rail (highest wins):**

1. Import / index / export / clean **progress** (coordinator flags) — also hides zones 3–4.
2. Duplicate files link (All Fonts mode).
3. `statusMessage` when no cell detail is showing.

Truncate cell values at ~500 characters. Progress hides cell detail and warning zones.

### Row context menu — top-level order (font row)

1. Open in Inspector Window
2. Show in Information / Hide in Information — toggles `showInspector`
3. Reveal in Finder, Export Fonts…
4. **Copy ▸** submenu
5. **Metadata ▸** submenu — only when font has any `activeMetadataIssues`
6. Family expand/collapse block — only when `groupByFamily`
7. Edit block (Select All Families / Fonts, Deselect)
8. Exclude / Include from Index — only `browserMode == .allFonts`
9. Move to Trash / Delete Immediately (bottom)

Header right-click stays **column customize** only (unchanged).

### Copy ▸ (v1)

| Item | Rule |
|------|------|
| Copy “{Column}” | First item; deduped values across selection (e.g. one family when all match) |
| Copy Font Name | Deduped full names |
| Copy Font Family | Deduped family names; family row uses section display name |
| Copy Full Path | Absolute path (`vaultRoot` + `vaultPath`); deduped |
| Copy Family Row | Family header only: TSV header + one row of **grouped** column values (family row right-click) |
| Copy Row / Copy N Rows | TSV header + one row per font in scope (`Copy 7 Rows` on a family with 7 styles) |
| Menu labels | Singular when one distinct value; else `Copy N …` where N is **unique** count, not selection size |

Copy uses pasteboard only; no `statusMessage` spam.

### Metadata ▸ (v1)

Shown when `font.hasAnyActiveMetadataIssue` (or any active issue on font row).

| Item | Behavior |
|------|----------|
| Show Issue in Information | `showInspector = true` (selection already synced on right-click) |
| Copy Issue Summary | Issues for **clicked column** if `metadataFieldKey` maps; else all active issues, joined for tooltip text |

### Family row vs font row

| Item | Family row | Font row |
|------|------------|----------|
| Copy “{Column}” | Uses **header cell** text when one family in scope; else deduped per-font values across selection |
| Copy Font Name / Family / Full Path | Same dedupe rules; family from **export selection**, not only the clicked header |
| Copy Row | Yes when selection resolves to fonts (e.g. family selected) |
| Metadata ▸ | Yes if any font in selection has issues |
| Hover status | Header cell text + issue hint when applicable |
| Expand / Collapse all | When grouped | When grouped |
| Open in Inspector | If selection allows | If selection allows |

### Column hit-test (context menu + hover)

- `point = outlineView.convert(event.locationInWindow, from: nil)`
- `row = outlineView.row(at: point)`; `columnIndex = outlineView.column(at: point)`
- Map column identifier → `FontListColumn` via coordinator `columnForIdentifier`
- Skip disclosure triangle zone: `point.x <= FontListOutlineChrome.disclosureHitMaxX(indentationPerLevel:level:) + 4` (same as `FontListOutlineView` mouse handling)
- Resolve font via `resolvedPayload(for:)` on `FontListOutlineNode`

### Phases 4–6 (URL, filter, find, in-cell)

| Item | Behavior |
|------|----------|
| URL cells | Blue underline + link color when `FontListURLParsing` accepts http(s); distinct from orange metadata underline |
| Open URL / Copy URL | After **Copy ▸** when one deduped URL in clicked URL column |
| **Filter ▸** | **Show Only {OTF/…}** on format column; **Clear Format Filter** when active; **Show Only Excluded Fonts** only when sidebar Smart Filters shows Excluded Fonts (Show Ignored Fonts on + count > 0) |
| Find “…” | One distinct non-empty cell value → `searchText` + `focusSearchField()`; disabled when ambiguous or `—` |
| Cmd-click URL | Opens in browser without changing row selection |
| Status bar hover | `License URL: …` glance; tooltip includes full URL + `⌘-click to open` when valid http(s) (not orange metadata styling) |

---

## Status bar refinement (shipped 2026-05-30)

Four left zones + right priority rail in `StatusBarView` (`MainWindowView.swift`). Copy helpers: `StatusBarCopy.swift`, `ListStatusDetail` column-scoped `metadataWarning`. Tests: `ListStatusDetailTests`, `StatusBarCopyTests`.

**Out of scope (still backlog):** full Help menu; extra bar fields (vault path, license, export mode); grouped “N families visible” as a separate glance number (family count may appear in zone 1 tooltip).

---

## How to use this file

- Add items as you notice them while testing (one line is enough).
- Mark status when you pick something up: `[ ]` todo · `[~]` in progress · `[x]` done · `[-]` won't do
- **Core** = needed before trusting Font Vault for real migration off FEX  
- **Polish** = improves daily use but not blocking  
- **Later** = nice to have / post–v1

---

## Core functionality (in progress)

| Status | Item | Notes |
|--------|------|--------|
| [x] | Import via File → Import Fonts… | Format filters, copy/move, folder scan, UTType picker filter, ignored-format counts in summary (2026-05-30) |
| [x] | Drag-and-drop import | Uses Settings → Import defaults (panel choices do not write back) |
| [x] | SQLite catalog (`.fontvault/catalog.sqlite`) | Fixed `id` / `databaseID` column mapping |
| [x] | FEX-style vault layout (A–Z buckets) | `Documents/FontVault` |
| [~] | Index existing vault | Works; needs testing at large scale (~200k) |
| [x] | Export to Finder | File → Export Fonts… (⌘E); family / vault A–Z / flat; compact panel; Settings default, one-shot override (2026-05-30) |
| [x] | Drag-out export | Family folders when grouped; `FontVault Export/` root when multiple families |
| [x] | Finder-style list selection | Click / ⌘ / ⇧; no shift-drag range |
| [x] | Multi-select in list (⌘/⇧-click, ⌘A) | |
| [x] | Move to Trash + remove DB row | FEX-style confirmation; Delete Immediately via ⌘⇧⌫ |
| [x] | Clean vault | Orphans → Trash; stale catalog rows removed; empty folders pruned |
| [x] | Reorganize to A–Z layout | Vault menu; moves files + updates catalog (after Finder copy into vault) |
| [x] | Prune empty folders after remove | On remove; walks up from style folder |
| [x] | Prune empty source folders after move import | Stops at parent of import selection (FEX-style) |
| [x] | Performance at scale — AppKit list | P0 closed: SQL windowing + ~10k validation (all columns, flat) |

---

## Polish / UX

| Status | Item | Notes |
|--------|------|--------|
| [x] | **Family grouping in list** | Filter bar “Grouped” toggle; chevron headers, style count, expand/collapse all in context menu |
| [x] | **Import Date column** | FEX-style `M/d/yy`; family header shows `-` when styles have different import days |
| [x] | **SHA-256 duplicates** | Sidebar Conflicts → Duplicates; scan catalog, pick keeper, resolve to Trash |
| [x] | WOFF / WOFF2 in sidebar Format section | `AppState.sidebarFormats`; rows appear when catalog has woff/woff2 (count-gated) |
| [x] | Import progress sheet (large imports) | FEX `importSheet`: title, file name, bar, **Cancel Import**; completion in-sheet (OK) — threshold 5+ files |
| [x] | Import rollback on cancel | Single pass source→vault; cancel removes vault files + catalog rows (sources kept until move succeeds) |
| [x] | Import report sheet | Summary unchanged; **View Details…** when failed/skipped rows exist; `ImportReportSheet` with Reveal, copy/save `.txt` (2026-05-31) |
| [~] | Duplicate detection UI | Basic SHA-256 scan + resolve; no PostScript-name conflicts yet |
| [x] | OpenType name metadata in catalog | IDs 0,3,7–10 + OS/2 VendID + format detailed; inspector + DB v2 migration |
| [~] | Prettier list rows | AppKit name subtitle + format badge; mockup polish ongoing |
| [ ] | Inspector default / layout | Toggle exists; refine sections and empty state |
| [~] | App icon | Asset catalog has PNGs; polish if needed |
| [x] | Double-click font row → inspector window | `presentFontInspector` / tabbed window |
| [ ] | “Open in Typeface” / “Open in FontBase” | Menu / external handoff (not double-click) |
| [x] | Import format options | Three categories matching Core Text import (.otf/.ttc/.ttf/.dfont/.woff/.woff2); no PostScript/EOT/SVG; panel UTTypes (2026-05-30) |
| [x] | Import/export Settings vs panels | Defaults persist; File → Import/Export one-shot pre-fill only (2026-05-30) |
| [x] | Column order / width persistence | Header drag + Settings share `listColumnOrder` (2026-05-30) |
| [x] | Compact export panel accessory | Layout radios only; full copy in Settings → Export defaults (2026-05-30) |
| [x] | Onboarding copy & flow | FEX folder option + catalog note (2026-05-31) |

---

## Settings & behavior (from FEX — evaluate later)

| Status | Item | FEX reference | Font Vault today |
|--------|------|---------------|------------------|
| [x] | Default copy vs move | Settings → Import defaults | Default **copy**; Import panel pre-fills, one-shot override (2026-05-30) |
| [x] | Import/export persistence policy | § Persistence policy | Panels do not write Settings; drag import uses Settings only (2026-05-30) |
| [ ] | Import into sets / set structure | Import dialog | **Out of scope** — sets live in viewer apps |
| [ ] | Duplicate path / duplicate font policies | Import preferences | Not implemented |
| [ ] | Auto-classify after import | Import preferences | Not implemented |
| [x] | Export: family / vault / flat layout | Settings = default; File → Export pre-fills, one-shot override (2026-05-30) |
| [ ] | Export: zip / disk image | Export preferences | Not implemented |

---

## Technical / debt

| Status | Item | Notes |
|--------|------|--------|
| [x] | SwiftUI “Publishing changes from within view updates” | Mitigated via `scheduleRefreshList()` |
| [ ] | Failed import left files on disk without catalog rows | Fixed DB bug; use **Index** to reconcile orphans |
| [ ] | Import should rollback file copy if DB insert fails | Today: copy then insert — orphan file possible on failure |
| [ ] | Manual Finder delete → stale catalog rows | Needs integrity “missing files” pass (FEX marks broken) |
| [ ] | Sandboxing for Mac App Store | Dev build is non-sandboxed by design |
| [ ] | Universal binary testing on Apple Silicon | Target is arm64 + x86_64 |
| [ ] | Do not write to FEX `.fexdb` | Font Vault uses its own catalog only |

---

## Testing log (informal)

| Date | What | Result |
|------|------|--------|
| 2026-05-23 | First launch, empty `Documents/FontVault` | Onboarding OK |
| 2026-05-23 | Import OTF / TTF / WOFF2 | OK after `CodingKeys` fix |
| 2026-05-23 | Bulk copy of previously added test files | 60 in catalog; many duplicate rows; **no family grouping** |
| 2026-05-23 | Multi-select + remove to Trash | ⌘A, ⇧/⌘-click, Font menu / context menu |
| 2026-05-25 | List perf: all columns vs few | Release build still laggy with many columns; fewer columns much better |
| 2026-05-25 | Architecture review vs FEX | FEX uses `fontOutlineView` / `NSOutlineView`; Font Vault migrating hybrid shell |
| | Index large existing FEX library | Not yet tested |
| | Move (not copy) import | Not yet tested |
| | Drag-drop with Web fonts off | Should skip .woff — verify message |

---

## Backlog — Help menu

| Status | Item |
|--------|------|
| [x] | **Font Vault Help…** — file-management modes alert (`VaultOrganizationHelp`) |
| [ ] | Expand Help entries beyond organization (import, scan/rebuild, vault maintenance, duplicates, export, keyboard shortcuts) |
| [ ] | Consistent naming: Help menu titles vs Settings section titles vs `AppMenuCopy` |
| [ ] | Decide long-term format: more alert sheets vs Help Book / dedicated Help window |

---

## Backlog — Phase 2a (index exclusion & visibility)

**Canonical spec:** [`PHASE2_SPEC.md`](PHASE2_SPEC.md)

**Critical:** **Exclude/Include** (flag) and **Show Ignored Fonts** (visibility) are orthogonal.

| Status | Item |
|--------|------|
| [x] | DB: `excludedFromIndex` + migration `v5_excludedFromIndex` |
| [x] | Font / context: **Exclude from Index…**, **Include in Index** |
| [x] | View: **Show / Hide Ignored Fonts** (⇧⌘I, Button not Toggle), **Exclude Ignored Fonts from Index** |
| [x] | Smart Filters → **Excluded Fonts** (count > 0 and Show Ignored On) |
| [x] | Indexer, SQL browse, counters, row styling; duplicates omit excluded |

Locked: re-scan clears flag when enforce off; Exclude/Include **disabled in Duplicates** (2a); Smart Filters header always, Excluded Fonts row conditional; ⇧⌘I placeholder for Show Ignored; Exclude confirm with list + Don’t show again + Settings reset.

---

## Ideas parking lot

_Add anything here without overthinking priority._

- Batch rename / rebucket tools in vault  
- CSV export of catalog (paths, family, hash)  
- Menu bar helper for quick drop-import  
- Read-only import from existing FEX `.fexdb` for comparison (one-time migration aid)  
- Variable font badge / filter (partially detectable via `isVariable`)  
- TTC: single row with disclosure to faces (no TTC test files yet)  

---

## Reference files

| File | Purpose |
|------|---------|
| `README.md` | Build & run (users) |
| `HANDOFF.md` | Agent onboarding |
| `PHASE2_SPEC.md` | Phase 2a exclusion / Smart Filters spec |
| [`../_misc/_archive/FontVaultDevelopment/`](../_misc/_archive/FontVaultDevelopment/) | Archived: FEX gap analysis, `DESIGN.md`, HTML mockup, GUI docx, review brief |
