#!/usr/bin/env bash
# Builds the installable SketchUp package: dist/meubles-<version>.rbz (macOS / Linux).
# (an .rbz is a zip with the loader meubles.rb and the meubles/ folder at its root).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
src="$here/src"
dist="$here/dist"

version="$(sed -n "s/.*ext\.version *= *'\([^']*\)'.*/\1/p" "$src/meubles.rb" | head -n 1)"
[ -n "$version" ] || { echo "ext.version not found in $src/meubles.rb" >&2; exit 1; }

mkdir -p "$dist"
rbz="$dist/meubles-$version.rbz"
rm -f "$rbz"
(cd "$src" && zip -q -r -X "$rbz" meubles.rb meubles -x '*__pycache__*' '*.pyc' '*.DS_Store')
echo "Built $rbz"
