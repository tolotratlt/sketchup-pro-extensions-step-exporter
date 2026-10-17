# Developer install: copies src\ into the SketchUp Plugins folder, then restart SketchUp.
# End users can install dist\meubles-<version>.rbz from the Extension Manager instead.
param([string]$Version = '2026')
$ErrorActionPreference = 'Stop'

$src     = Join-Path $PSScriptRoot 'src'
$plugins = Join-Path $env:APPDATA "SketchUp\SketchUp $Version\SketchUp\Plugins"
if (-not (Test-Path $plugins)) { throw "Plugins folder not found: $plugins (is SketchUp $Version installed and launched once?)" }

Copy-Item (Join-Path $src 'meubles.rb') $plugins -Force
$dest = Join-Path $plugins 'meubles'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $src 'meubles\*.rb'), (Join-Path $src 'meubles\*.py') $dest -Force
Write-Host "Meubles installed in $plugins - restart SketchUp."
