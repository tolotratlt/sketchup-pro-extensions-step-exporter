# Builds the installable SketchUp package: dist\meubles-<version>.rbz
# (an .rbz is a zip with the loader meubles.rb and the meubles\ folder at its root).
$ErrorActionPreference = 'Stop'

$src  = Join-Path $PSScriptRoot 'src'
$dist = Join-Path $PSScriptRoot 'dist'
$loader = Join-Path $src 'meubles.rb'

$version = (Select-String -Path $loader -Pattern "ext\.version\s*=\s*'([^']+)'").Matches[0].Groups[1].Value
if (-not $version) { throw "ext.version not found in $loader" }

$staging = Join-Path ([IO.Path]::GetTempPath()) "meubles-rbz-$([guid]::NewGuid())"
New-Item -ItemType Directory -Force (Join-Path $staging 'meubles') | Out-Null
try {
    Copy-Item $loader $staging
    Get-ChildItem (Join-Path $src 'meubles') -File -Include *.rb, *.py -Recurse |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $staging 'meubles') }

    New-Item -ItemType Directory -Force $dist | Out-Null
    $zip = Join-Path $dist "meubles-$version.zip"
    $rbz = Join-Path $dist "meubles-$version.rbz"
    Remove-Item $zip, $rbz -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip
    Move-Item $zip $rbz
    Write-Host "Built $rbz"
}
finally {
    Remove-Item $staging -Recurse -Force
}
