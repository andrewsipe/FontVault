# Phase 2 Alignment Spec — Index Exclusion & Visibility

Phase 1 (vault organization modes) is **done** in code. Phase 2a is **implemented** in code (`excludedFromIndex`, Smart Filters, visibility toggles). Validate in Xcode on your machine.

**Canonical spec for Phase 2a implementation.** Update this file when decisions change.

---

## Critical workflow model

There are **two independent actions** that must not be conflated:

1. **Exclude / Include** — sets or clears a catalog flag (`excludedFromIndex`). This is an indexing decision. It does **not** change what the user sees in the font table.
2. **Show / Hide Ignored Fonts** — a View menu toggle that controls whether flagged fonts are visible in the font table. This is a visibility decision. It does **not** change the flag.

A font can be excluded and still visible (if the toggle is On). A font can be unexcluded and still present in the table normally. These are orthogonal.

---

## Scope split

| Build | Includes | Excludes |
|-------|----------|----------|
| **Phase 2a** (build now) | Index exclusion flag, View toggles, counters, **Smart Filters** section with built-in **Excluded Fonts** filter, SQL/browse/indexer hooks | User-created Smart Filters, rule editor, FEX Smart Set import |
| **Phase 2b+** (later) | **New Smart Filter…**, persisted rules, AND/OR compiler, nested-set rules | Server smart sets, activation sets, `.fexdb` import |

---

## Problem being solved

FEX **Remove from FontExplorer X Pro** is often catalog-only; system/program fonts come back after restart/rescan. Font Vault today only has **Move to Trash** / **Delete Immediately** (disk + catalog).

Phase 2 adds a **non-destructive** path: flag a font to be excluded from indexing, and optionally hide it from the font table, **without** moving or deleting the file — with a way to find and restore it.

**Not using quarantine folders** — exclusion is a **catalog flag only**, not file relocation.

---

## Data model

| Item | Decision |
|------|----------|
| Column | `excludedFromIndex` `BOOLEAN NOT NULL DEFAULT 0` on `fonts` |
| Migration | `v5_excludedFromIndex` (GRDB migrator) |
| Code naming | `excludedFromIndex` in models/SQL |
| UI naming | *Exclude* / *Include* / *Excluded* / *Ignored* in menus (View toggle uses *Ignored*; smart filter uses *Excluded*) |
| File on disk | Unchanged at all times |
| Row in DB | **Kept** — not deleted until Trash/Delete or Clean Vault removes missing files |

---

## Menu structure

### Font menu — exclusion actions (flag only, no visibility change)

| Action | Enabled when | Effect |
|--------|-------------|--------|
| **Exclude from Index…** | Selection contains any non-excluded fonts | Sets `excludedFromIndex = 1`. Font remains visible in table at current position. |
| **Include in Index** | Selection contains any excluded fonts | Clears `excludedFromIndex = 0`. No other change. |

Confirmation for **Exclude from Index…** should state: the font file is not deleted or moved; it will be excluded from index scans while **Exclude Ignored Fonts from Index** is enabled; the font remains visible in the table until **Show Ignored Fonts** is turned off.

### Right-click context menu — exclusion actions only

Mirrors the Font menu for:

- **Exclude from Index…**
- **Include in Index**

The visibility toggle is **not** in the context menu — View menu only.

### View menu — visibility and indexer toggles

| Toggle | Default | Controls |
|--------|---------|----------|
| **Show Ignored Fonts** | **Off** | When Off: excluded fonts are hidden from the font table. When On: excluded fonts appear with distinct row styling. |
| **Exclude Ignored Fonts from Index** | **On** | When On: indexer/rebuild skips paths with `excludedFromIndex = 1`. When Off: re-index normally; **clear flag on successful re-index**. |

---

## Library sidebar layout

```text
Library
├── Vault → All Fonts
├── Conflicts → Duplicates
├── Format → OTF / TTF / …
└── Smart Filters
    └── Excluded Fonts   ← count > 0 AND Show Ignored Fonts is On
```

- **Smart Filters** section header always shown (Phase 2a has no other rows in this section).
- **Excluded Fonts** row when `excludedFontCount > 0` **and** **Show Ignored Fonts** is **On**.
- Phase 2b+: **Add Smart Filter…** and user-created entries in the same section.
- Selection: `SidebarItem.smartFilter(.excludedFonts)`.
- Query: `excludedFromIndex = 1`; search/format still apply.
- Last font **Included** while on **Excluded Fonts** → selection returns to **All Fonts**.
- Turning **Show Ignored Fonts** **Off** while on **Excluded Fonts** → selection returns to **All Fonts**.

---

## Browse & SQL behavior

| Context | Rows shown |
|---------|------------|
| **All Fonts**, Show Ignored **Off** | `excludedFromIndex = 0` only |
| **All Fonts**, Show Ignored **On** | All rows; excluded styled distinctly |
| **Smart Filters → Excluded Fonts** | `excludedFromIndex = 1` only (row visible only when Show Ignored On) |
| **Format** + **All Fonts** | Format on visible set per Show Ignored state |
| **Format** + **Excluded Fonts** | Excluded only, matching format |
| **Duplicates** | Excluded omitted from scan/list |

Extend `CatalogBrowseSQL` with visibility/smart-filter parameters for counts, family summaries, and flat paths.

---

## Indexer behavior

**Exclude Ignored Fonts from Index On (default):**

- Do not insert new rows for paths already `excludedFromIndex = 1`.
- Do not clear the flag on existing excluded rows during scan.

**Exclude Ignored Fonts from Index Off:**

- Re-index excluded paths normally.
- **Clear `excludedFromIndex` on successful re-index.**

New imports (managed mode) always non-excluded.

---

## Counters (Show Counters on)

| Surface | Count |
|---------|-------|
| **All Fonts** sidebar | Active only (`excludedFromIndex = 0`) |
| **Excluded Fonts** smart filter | `excludedFontCount` |
| Status bar — All Fonts | `N fonts` + `· E excluded` if E > 0 |
| Status bar — Excluded Fonts filter | e.g. `12 excluded fonts` |
| Format chips | Active (non-excluded) only |

---

## Row styling

When **Show Ignored Fonts** is On, excluded rows in **All Fonts**: secondary opacity + `eye.slash` badge (`FontListOutlineCells`). Visual pass TBD.

---

## Integration

| Feature | Behavior |
|---------|----------|
| **Export** | Visible selection only; excluded exportable when visible |
| **Clean Vault** | Excluded + file on disk → not orphan. Excluded + missing file → stale row (removable) |
| **Information** | Works when row visible |
| **Exclude** | Flag only; row stays until Show Ignored Off |
| **Duplicates** | Excluded omitted from scan; **Exclude from Index** / **Include in Index** **disabled** in Duplicates browser mode (revisit if Duplicates gains more than SHA-256 exact matching) |

---

## Exclude from Index confirmation

Shown unless suppressed in Settings.

- Plain-language summary: which fonts (names and/or count).
- One line: no files are deleted or moved.
- Checkbox: **Don’t show again** → `VaultSettings.suppressExcludeFromIndexConfirmation`.
- **Settings → General:** control to reset “show Exclude confirmation” (re-enables the sheet).

---

## Out of scope (Phase 2a)

- Quarantine folder
- **Add Smart Filter** affordance and user-created filters (2b+; same **Smart Filters** section)
- FEX Smart Set / `.fexdb` import
- Finder-close auto-scan
- Vault organization changes (Phase 1)
- Help menu expansion

---

## Build decisions (locked for 2a)

| # | Topic | Decision |
|---|--------|----------|
| 1 | Re-scan with **Exclude Ignored Fonts from Index** Off | **Clear `excludedFromIndex` on successful re-index** |
| 2 | Exclude / Include in **Duplicates** view | **Disabled** for Phase 2a. *Future:* revisit if Duplicates expands beyond SHA-256 exact matching |
| 3 | **Smart Filters** section | Header **always visible**. Phase 2a: only **Excluded Fonts** row (when count > 0 and Show Ignored On). **Add Smart Filter** + user filters → Phase 2b+ |
| 4 | Keyboard shortcuts | **Exclude / Include:** none. **Show Ignored Fonts:** **⇧⌘I** placeholder — no in-app conflict today (⌘I = Import, ⌥⌘I = Information); confirm before ship |
| 5 | Exclude confirmation | Sheet **always shown** unless user checked Don’t show again. File list + count + “not deleted or moved.” Don’t show again + **reset in Settings → General** |

---

## Implementation order (Phase 2a)

1. Migration + `FontRecord` + count helpers (`activeFontCount`, `excludedFontCount`)
2. `CatalogBrowseSQL` visibility + smart filter
3. **Exclude from Index** confirmation sheet + `suppressExcludeFromIndexConfirmation` + Settings reset
4. **Exclude from Index** / **Include in Index** + `AppState` (disabled in Duplicates mode)
5. View toggles (persisted in `VaultSettings`); **Show Ignored Fonts** ⇧⌘I when confirmed
6. Indexer + enforce toggle
7. `SidebarItem.smartFilter(.excludedFonts)` + Smart Filters section (header only until row qualifies)
8. Counters + status bar
9. Context menu + outline enablement
10. Clean Vault / duplicates scan rules
11. Excluded row styling
