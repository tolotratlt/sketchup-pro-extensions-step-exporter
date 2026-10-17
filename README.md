# Meubles — SketchUp Pro extension

**STEP export for SketchUp Pro that preserves the model hierarchy and object names.**

SketchUp has no STEP exporter, and its other formats (OBJ, STL, DAE, FBX, IFC…) either flatten the model, turn it into meshes, or rename objects. This extension exports exact solids to STEP with the **hierarchy and names exactly as in the Outliner** — nothing is renamed, flattened or exploded.

Built for a SketchUp → STEP → [build123d](https://github.com/gumyr/build123d) workflow, with FreeCAD used as the converter and viewer.

### Scope

- ✅ **In scope:** geometry (exact B-rep solids), hierarchy (groups / components / nesting), object names, placements.
- ❌ **Out of scope, by design:** materials, textures, colours, tags/layers. They are not exported.

## Features

All commands are in **Extensions > Meubles** (menu labels are in French).

**Main feature**

| Menu item | What it does |
|---|---|
| *Exporter en STEP (via FreeCAD)...* | Exports the selection (or the whole model if nothing is selected) to a `.step` file, keeping hierarchy and names. |
| *Chemin de FreeCADCmd...* | Sets the path to `freecadcmd.exe` if it isn't found automatically. |

**Secondary tools**

| Menu item | What it does |
|---|---|
| *Exporter la nomenclature (CSV)...* | Cut list: one row per identical part (same definition and material), with L × W × thickness in mm, quantity, area, parent assemblies and instance names. `;`-separated, UTF-8 with BOM (opens directly in Excel). |
| *Nouveau buffet...* / *Modifier le buffet sélectionné...* | Parametric sideboard: width, depth, height, number of compartments (= doors), shelves per compartment, panel thicknesses. Parts are components named `Type LxWxT` and are regenerated when parameters change. |

### How the STEP export maps the model

```
SketchUp model                      STEP
──────────────                      ────
model title                    →    root assembly
group / component with children →   assembly, same name, same placement
part (no nested group/component) →  solid (exact B-rep, not a mesh), named after the instance
```

- Names come from the **instance name** (the name shown in the Outliner); if an instance has no name, its definition name is used.
- Duplicate names are kept (e.g. two `Panneau` in two different doors).
- Non-ASCII characters are written using the ISO 10303-21 `\X2\...\X0\` encoding, so accents survive in every reader.
- Units: millimetres.

## Requirements

- **SketchUp Pro 2024 or later on Windows** (tested with SketchUp 2026). SketchUp ships its own Ruby; nothing else to install.
- **FreeCAD 1.0 or later** (tested with 1.1.3). Only `freecadcmd.exe` (the headless FreeCAD) is used: it runs the bundled `import_sketchup.py` with FreeCAD's own Python. **No separate Python install and no FreeCAD add-on are needed.**
  The extension looks for `FreeCAD*\bin\freecadcmd.exe` in `Program Files` and `%LOCALAPPDATA%\Programs`; otherwise set it with *Chemin de FreeCADCmd...*.

The CSV cut list and the buffet generator work without FreeCAD.

## Installation

### Option A — `.rbz` package (recommended)

1. Build it (or download it from the GitHub Releases page):
   ```powershell
   .\build_rbz.ps1          # creates dist\meubles-<version>.rbz
   ```
2. In SketchUp: **Extensions > Extension Manager > Install Extension**, pick the `.rbz`.

### Option B — developer install

```powershell
.\install.ps1                # copies src\ into %APPDATA%\SketchUp\SketchUp 2026\SketchUp\Plugins
.\install.ps1 -Version 2025  # other SketchUp version
```
Restart SketchUp afterwards.

### "Unsigned" warning

The Extension Manager shows the extension as **Unsigned**: this is expected for any extension not signed through the Extension Warehouse. It loads fine as long as **Extension Manager > Settings > Loading Policy** is *Approve Unidentified Extensions* or *Unrestricted* (not *Identified Extensions Only*).

## Usage

1. Select the objects to export (or nothing to export the whole model).
2. **Extensions > Meubles > Exporter en STEP (via FreeCAD)...** and choose the output file.
3. A few seconds later a message confirms the export. A temporary `.json` next to the `.step` is deleted automatically.

## Viewing / reading the STEP

### FreeCAD

FreeCAD's STEP importer adds things that are **not in the file**: with default settings it renames duplicate labels (`Panneau001`) and adds an `Origin` object to every assembly. To see the exact structure, enable once:

1. **Edit > Preferences > General > Document**: *Allow duplicate object labels in one document*.
2. **Edit > Preferences > Import-Export > STEP**: *Use LinkGroup*.

### build123d

```python
from build123d import import_step
model = import_step("model.step")
```
The hierarchy and names are preserved, but note that build123d's `import_step` itself replaces spaces, dots and parentheses in labels with `_` (`Côté gauche` → `Côté_gauche`).

To print the tree as build123d sees it:
```powershell
python tools\check_step_build123d.py model.step     # needs: pip install build123d
```

## Limitations

- In the STEP, identical parts don't share geometry: each part is its own product so that readers display the **instance** name. Definition names (e.g. `Côté 850x450x18`) are kept in the CSV cut list.
- Scaled instances are exported without their scale (STEP placements are rigid).
- Windows only (path detection and `freecadcmd.exe`).

## Project layout

```
src/meubles.rb              extension loader (registers "Meubles")
src/meubles/main.rb         menu and dialogs
src/meubles/export_freecad.rb  SketchUp → JSON (hierarchy + faces), runs freecadcmd
src/meubles/import_sketchup.py JSON → STEP, executed by FreeCAD's Python
src/meubles/nomenclature.rb CSV cut list
src/meubles/buffet.rb       parametric buffet generator
tools/check_step_build123d.py  print a STEP tree with build123d
```

## License

[MIT](LICENSE)
