# Font Vault

Native macOS font **file manager** — import, organize, and index fonts in a vault folder. Preview and activation stay in Typeface, FontBase, or Font Book.

## Open the project in Xcode

1. Open **Xcode** (from Applications or Spotlight).
2. **File → Open…** and choose:
   `Good Font Scripts/FontVault/FontVault.xcodeproj`
3. Wait for **Package Resolution** to finish (GRDB downloads once).
4. Select the **FontVault** scheme (toolbar, next to the stop button).
5. Press **⌘R** (Run). The app builds and launches.

### First-time Xcode setup

- **Signing:** Select the **FontVault** project in the left sidebar → **FontVault** target → **Signing & Capabilities**. Choose your **Team** (Apple ID). For personal use, “Sign to Run Locally” is enough.
- **Command Line Tools:** If build fails with “xcodebuild not found”, run Xcode once and install tools when prompted, or **Xcode → Settings → Locations → Command Line Tools** → select Xcode.

## First launch in the app

1. Pick a vault folder:
   - **Default:** `~/Documents/FontVault`
   - **Existing FEX library:** `~/Documents/FEX`
   - **Custom…** via folder picker
2. Choose layout: **FEX (A–Z buckets)** for your current tree.
3. Click **Continue**.
4. For an existing folder with many fonts: **Vault → Index Existing Vault** (menu) or toolbar **Index**. This builds `.fontvault/catalog.sqlite` without moving files.

## Project layout

| Path | Purpose |
|------|---------|
| `FontVault/` | App source (SwiftUI + services) |
| `FontVaultTests/` | Unit tests |
| `HANDOFF.md` | Agent onboarding (architecture, open work) |
| `NOTES.md` | Living backlog and persistence policy |
| `PHASE2_SPEC.md` | Phase 2a index exclusion / Smart Filters |
| `../_misc/_archive/FontVaultDevelopment/` | Archived design docs, FEX gap analysis, mockup, GUI spec |

## Architecture (hybrid — FEX-aligned list)

Font Vault is a **SwiftUI app** with an **AppKit font list** (same pattern as many Mac apps: SwiftUI chrome + `NSOutlineView` for heavy tables).

| Layer | Technology | Role |
|-------|------------|------|
| **App shell** | SwiftUI | Main window, sidebar, filters, inspector, settings, onboarding |
| **Font list** | AppKit `NSOutlineView` via `FontListOutlineHost` | Virtualized rows, FEX-style grouping (Phase 1) |
| **Catalog** | SQLite + GRDB | `{vault}/.fontvault/catalog.sqlite` — **not** FontExplorer `.fexdb` |
| **Files** | On-disk vault | FEX-compatible A–Z layout (style folders from name **ID 4**); Font Vault does not own preview/activation |

**What is changing:** only the **list UI + how it talks to the database** (windowed queries, selection coordinator).  
**What is not changing:** SwiftUI for everything else, vault layout, import/export, catalog schema.

Backlog and FEX comparison: **`NOTES.md`**. Deep parity matrix (snapshot): **`../_misc/_archive/FontVaultDevelopment/FEX_GAP_ANALYSIS.md`**.

## Decisions (v0.1)

- **macOS 14.4+**, universal Intel + Apple Silicon
- **Non-sandboxed** (development); App Store would add sandbox later
- **Catalog:** `{vault}/.fontvault/catalog.sqlite` (not FontExplorer’s `.fexdb`)
- **List view:** migrating from SwiftUI `Table` (1000-row cap) to **AppKit outline/table** for scale (~200k catalog)
- **Browse model at scale:** search/filter narrows SQL; status bar shows “first N of M” when capped

## Adding fonts to the vault

| Method | How |
|--------|-----|
| **File → Import Fonts…** | Opens the file picker with format options (like FEX). Choose files or folders; subfolders are scanned. |
| **Drag and drop** | Drop font files or folders onto the main window. Uses import defaults from Settings. |
| **Toolbar Import** | Same as File → Import Fonts… |
| **Index Existing Vault** | For fonts **already copied** into the vault folder — builds the catalog only (no file copy). |

In the import panel:

- **Formats** — OpenType, TrueType, and optional Web fonts (.woff / .woff2). The file picker filters to enabled types; folders still scan by the checkboxes.
- **Copy into vault** — originals stay where they are (default).
- **Move into vault** — like FEX “Move” in Advanced preferences; originals are removed after import.

Panel choices apply **only to that import**. Defaults live in **Font Vault → Settings** (⌘,) → Import defaults (drag-and-drop always uses Settings).

### Who manages font files? (Settings → General)

| Toggle | Who manages files | Import (⌘I) | Catalog sync (⇧⌘R) |
|--------|-------------------|-------------|-------------------|
| **On (default)** | Font Vault — A–Z layout | Import Fonts… | Rebuild Catalog… |
| **Off** | You — in Finder | Add Fonts to Vault… | Scan Vault for Changes… |

When the toggle is off, drag-and-drop import is disabled; add fonts in Finder, then scan. **Help → Font Vault Help…** summarizes both modes.

## Selection & remove

| Action | How |
|--------|-----|
| Select one | Click a row |
| Select range | ⇧-click (from last plain click) |
| Add / toggle | ⌘-click (selection persists when ⌘ is released) |
| Drag to Finder | Drag selected font row(s) out of the list (copies files) |
| Select all (visible list) | ⌘A |
| Deselect all | ⌘D |
| Move to Trash | **Font → Move to Trash…** or **Delete** key |
| Delete permanently | **Font → Delete Immediately…** or **⇧⌘Delete** |
| Context menu | Right-click list for same actions |

Removal matches FEX in spirit: confirm with font names, move files to **Trash**, remove catalog rows. Empty folders are pruned automatically.

## Export & clean vault

| Action | How |
|--------|-----|
| Export selected fonts | **File → Export Fonts…** (⌘E) or font table context menu |
| Export layout | **Group by family** (default, same as drag-out), **vault A–Z layout**, or **flat** file names — panel pre-fills from Settings; choice is one-shot per export |
| Clean vault | **Vault → Clean Vault…** — orphans → Trash; removes catalog rows for missing files; prunes empty folders |
| Reorganize layout | **Vault → Reorganize to A–Z Layout…** (organized mode only) — after copying fonts into the vault without importing |

**Rebuild catalog** / **Scan vault** only updates the database for files at their **current** paths; it does not move files. In organized mode, use **Reorganize** after dumping a folder of fonts into the vault.

Export **copies** fonts out of the vault (vault files stay put).

## Useful shortcuts

| Action | Shortcut |
|--------|----------|
| Settings | ⌘, |
| Import / add fonts | ⌘I (Import Fonts… or Add Fonts to Vault…) |
| Export fonts | ⌘E |
| Rebuild catalog / scan vault | ⇧⌘R (Vault menu) |
| Scan duplicates | ⇧⌘D (Duplicates view) |
| Select all families | ⌘A |
| Select all fonts | ⇧⌘A |
| Deselect all | ⌥⌘A |
| Group by family | ⇧⌘G |
| Find (focus search) | ⌘F |
| Show/hide Font Library | ⌃⌘S |
| Show/hide Information | ⌥⌘I |
| Show/hide library counters | View menu |
| Remove to Trash | ⌫ |
| Delete immediately | ⇧⌘⌫ |

## Troubleshooting

- **“Cannot find GRDB”** — File → Packages → Reset Package Caches, then Resolve Package Versions.
- **Signing errors** — Set Team under Signing & Capabilities.
- **Empty list after onboarding** — Run **Index Existing Vault** for folders that already contain fonts.
