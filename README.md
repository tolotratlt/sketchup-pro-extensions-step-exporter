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

### To use the extension (required)

Supported platforms: **Windows** and **macOS**.

| Software | Version | Provides | Notes |
|---|---|---|---|
| **SketchUp Pro** | 2024 or later — tested 2026 (26.2) on Windows | **Ruby runtime** (bundled, Ruby 3.2 in SketchUp 2026) | Runs the extension (`.rb` files). Only Ruby standard library is used (`json`, `csv`, `open3`). |
| **FreeCAD** | 1.0 or later — tested 1.1.3 on Windows | **Python runtime** (bundled, Python 3.11 in FreeCAD 1.1) and the OpenCASCADE STEP writer | Only `freecadcmd` (headless FreeCAD) is used: it runs `import_sketchup.py` with FreeCAD's own Python. |

That's all. **No separate Ruby, Python or conda install, no gems, no pip packages and no FreeCAD add-on are needed** — both runtimes ship inside SketchUp and FreeCAD.

Where the extension looks for `freecadcmd` (the most recent version found wins):

| OS | Searched locations |
|---|---|
| Windows | `Program Files\FreeCAD*\bin\freecadcmd.exe`, `%LOCALAPPDATA%\Programs\FreeCAD*\bin\freecadcmd.exe` |
| macOS | `/Applications/FreeCAD*.app/Contents/Resources/bin/freecadcmd` (or `Contents/MacOS/`), same under `~/Applications` |

If FreeCAD is elsewhere, set the path with *Chemin de FreeCADCmd...* (on macOS you type/paste the path, because the file picker can't enter `.app` bundles). On macOS, **launch FreeCAD once** from the Finder before the first export so Gatekeeper approves it.

The CSV cut list and the buffet generator work without FreeCAD.

### Optional — checking the STEP with build123d

`tools/check_step_build123d.py` is a standalone helper, not part of the extension. It needs a regular Python with build123d:

| Package | Version tested |
|---|---|
| Python | 3.12 |
| build123d | 0.13.0 (pulls OCP / OpenCASCADE `cadquery-ocp-novtk` 8.0.1) |

With conda (Windows or macOS):
```bash
conda env create -f environment.yml     # creates the "sketchup-step" env
conda activate sketchup-step
```
or with pip in any Python 3.10+ environment:
```bash
pip install -r tools/requirements.txt
```

## Installation

### Option A — `.rbz` package (recommended, same file for Windows and macOS)

1. Build it (or download it from the GitHub Releases page):
   ```powershell
   # Windows (PowerShell)
   .\build_rbz.ps1          # creates dist\meubles-<version>.rbz
   ```
   ```bash
   # macOS (Terminal)
   ./build_rbz.sh           # creates dist/meubles-<version>.rbz
   ```
2. In SketchUp: **Extensions > Extension Manager > Install Extension**, pick the `.rbz`.

### Option B — developer install (copies `src/` into the Plugins folder)

| OS | Command | Plugins folder |
|---|---|---|
| Windows | `.\install.ps1` (or `.\install.ps1 -Version 2025`) | `%APPDATA%\SketchUp\SketchUp 2026\SketchUp\Plugins` |
| macOS | `./install.sh` (or `./install.sh 2025`) | `~/Library/Application Support/SketchUp 2026/SketchUp/Plugins` |

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

1. **Preferences > General > Document**: *Allow duplicate object labels in one document*.
2. **Preferences > Import-Export > STEP**: *Use LinkGroup*.

(Preferences are under **Edit > Preferences** on Windows, **FreeCAD > Settings / Preferences** on macOS.)

### build123d

```python
from build123d import import_step
model = import_step("model.step")
```
The hierarchy and names are preserved, but note that build123d's `import_step` itself replaces spaces, dots and parentheses in labels with `_` (`Côté gauche` → `Côté_gauche`).

To print the tree as build123d sees it:
```bash
python tools/check_step_build123d.py model.step     # see "Optional — checking the STEP with build123d"
```

## Limitations

- In the STEP, identical parts don't share geometry: each part is its own product so that readers display the **instance** name. Definition names (e.g. `Côté 850x450x18`) are kept in the CSV cut list.
- Scaled instances are exported without their scale (STEP placements are rigid).
- macOS support is implemented (FreeCAD detection, path dialog, `install.sh` / `build_rbz.sh`) but has only been tested on Windows so far.

## Project layout

```
src/meubles.rb              extension loader (registers "Meubles")
src/meubles/main.rb         menu and dialogs
src/meubles/export_freecad.rb  SketchUp → JSON (hierarchy + faces), runs freecadcmd
src/meubles/import_sketchup.py JSON → STEP, executed by FreeCAD's Python
src/meubles/nomenclature.rb CSV cut list
src/meubles/buffet.rb       parametric buffet generator
build_rbz.ps1 / build_rbz.sh   build dist/meubles-<version>.rbz (Windows / macOS)
install.ps1 / install.sh       developer install into the Plugins folder (Windows / macOS)
tools/check_step_build123d.py  print a STEP tree with build123d (optional)
tools/requirements.txt      pip requirements of the optional tool
environment.yml             conda env of the optional tool
```

## License

[MIT](LICENSE)
