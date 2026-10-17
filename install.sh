#!/usr/bin/env bash
# Developer install on macOS: copies src/ into the SketchUp Plugins folder, then restart SketchUp.
# End users can install dist/meubles-<version>.rbz from the Extension Manager instead.
#
#   ./install.sh          # SketchUp 2026
#   ./install.sh 2025     # other version
set -euo pipefail

version="${1:-2026}"
here="$(cd "$(dirname "$0")" && pwd)"
plugins="$HOME/Library/Application Support/SketchUp $version/SketchUp/Plugins"

[ -d "$plugins" ] || { echo "Plugins folder not found: $plugins (is SketchUp $version installed and launched once?)" >&2; exit 1; }

cp "$here/src/meubles.rb" "$plugins/"
mkdir -p "$plugins/meubles"
cp "$here"/src/meubles/*.rb "$here"/src/meubles/*.py "$plugins/meubles/"
echo "Meubles installed in $plugins - restart SketchUp."
