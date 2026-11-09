<#
.SYNOPSIS
    Zip TotemicAccord/ into dist/TotemicAccord-<version>.zip for sharing.

.DESCRIPTION
    The version is read from the ## Version line of TotemicAccord.toc, so the TOC
    stays the single source of truth. The zip contains a single TotemicAccord/
    folder at its root, which is what players extract into Interface/AddOns.
#>
[CmdletBinding()]
param([string]$Version)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$addonName = 'TotemicAccord'
$source = Join-Path $repo $addonName
$toc = Join-Path $source "$addonName.toc"

if (-not $Version) {
    if (-not (Test-Path -LiteralPath $toc)) { throw "TOC not found: $toc" }
    $line = Select-String -LiteralPath $toc -Pattern '^##\s*Version:\s*(.+)$' | Select-Object -First 1
    if (-not $line) { throw "No '## Version:' line in $toc" }
    $Version = $line.Matches[0].Groups[1].Value.Trim()
}

$distDir = Join-Path $repo 'dist'
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$zip = Join-Path $distDir "$addonName-$Version.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

Compress-Archive -Path $source -DestinationPath $zip -CompressionLevel Optimal

$size = [math]::Round((Get-Item -LiteralPath $zip).Length / 1KB)
Write-Host "Packaged $addonName $Version" -ForegroundColor Green
Write-Host "  $zip  (${size} KB)" -ForegroundColor Green
Write-Host ''
Write-Host 'Tell your friends: extract so the folder lands at' -ForegroundColor DarkGray
Write-Host "  <WoW>\_forever_\Interface\AddOns\$addonName" -ForegroundColor DarkGray
