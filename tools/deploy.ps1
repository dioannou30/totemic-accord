<#
.SYNOPSIS
    Deploy Totemic Accord into the WoW Forever AddOns folder.

.DESCRIPTION
    Copy mode (default) mirrors TotemicAccord/ into
    <WOW_DIR>\_forever_\Interface\AddOns\TotemicAccord, deleting stale files there.

    Link mode (-Link) replaces the target with a directory junction instead, so edits
    in the repo are live in game after a /reload. Handy while iterating.

    WOW_DIR comes from tools\deploy.local (gitignored). If that file is missing, the
    script autodetects likely install locations and asks you to confirm one, then
    saves it.

.PARAMETER Link
    Install as a directory junction instead of copying.

.PARAMETER Check
    Run tools\check.ps1 first and stop if it fails.

.PARAMETER WowDir
    Override the WoW folder for this run (also saved if deploy.local is missing).

.PARAMETER Force
    Do not ask before replacing an existing real folder with a junction.

.EXAMPLE
    .\tools\deploy.ps1
    .\tools\deploy.ps1 -Check
    .\tools\deploy.ps1 -Link
#>
[CmdletBinding()]
param(
    [switch]$Link,
    [switch]$Check,
    [string]$WowDir,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$addonName = 'TotemicAccord'
$flavor = '_forever_'
$source = Join-Path $repo $addonName
$localFile = Join-Path $PSScriptRoot 'deploy.local'

# Print a multi-line explanation and stop, without a PowerShell stack trace on top
# of it -- these messages are meant to be read and acted on.
function Fail {
    param([string]$Message)
    Write-Host ''
    Write-Host $Message -ForegroundColor Red
    Write-Host ''
    exit 1
}

if (-not (Test-Path -LiteralPath $source)) {
    Fail "Addon folder not found: $source"
}

# ---------------------------------------------------------------- optional check
if ($Check) {
    Write-Host 'Running static checks first...' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'check.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Checks failed - not deploying.' -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------- resolve WOW_DIR
function Read-LocalWowDir {
    if (-not (Test-Path -LiteralPath $localFile)) { return $null }
    foreach ($line in Get-Content -LiteralPath $localFile) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t -match '^\s*WOW_DIR\s*=\s*(.+?)\s*$') {
            return $Matches[1].Trim('"').Trim("'")
        }
    }
    return $null
}

function Find-WowDirCandidates {
    $roots = Get-PSDrive -PSProvider FileSystem |
        Where-Object { $_.Free -ne $null } |
        Select-Object -ExpandProperty Root
    $subPaths = @(
        'Program Files (x86)\World of Warcraft',
        'Program Files\World of Warcraft',
        'Games\World of Warcraft',
        'World of Warcraft'
    )
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $roots) {
        foreach ($s in $subPaths) {
            $p = Join-Path $r $s
            if (Test-Path -LiteralPath (Join-Path $p $flavor)) { $found.Add($p) }
        }
    }
    # Prefer installs that actually have the Forever flavor; fall back to any WoW dir.
    if ($found.Count -eq 0) {
        foreach ($r in $roots) {
            foreach ($s in $subPaths) {
                $p = Join-Path $r $s
                if (Test-Path -LiteralPath $p) { $found.Add($p) }
            }
        }
    }
    return $found | Select-Object -Unique
}

function Save-LocalWowDir {
    param([string]$Path)
    @(
        '# Local deploy configuration for Totemic Accord. Gitignored - machine specific.',
        '# Path to the World of Warcraft folder that contains the _forever_ directory.',
        "WOW_DIR=$Path"
    ) | Set-Content -LiteralPath $localFile -Encoding UTF8
    Write-Host "Saved WOW_DIR to $localFile" -ForegroundColor DarkGray
}

$wow = if ($WowDir) { $WowDir } else { Read-LocalWowDir }

if (-not $wow) {
    Write-Host "No $localFile found - looking for a WoW install..." -ForegroundColor Cyan
    $candidates = @(Find-WowDirCandidates)
    if ($candidates.Count -eq 0) {
        Fail @"
Could not find a World of Warcraft folder automatically.
Create $localFile with the path, for example:

    WOW_DIR=D:\World of Warcraft

(That folder is the one containing the $flavor directory.)
"@
    }
    Write-Host ''
    Write-Host 'Found these candidates:'
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $hasFlavor = Test-Path -LiteralPath (Join-Path $candidates[$i] $flavor)
        $mark = if ($hasFlavor) { "has $flavor" } else { "NO $flavor" }
        Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $candidates[$i], $mark)
    }
    Write-Host ''
    $answer = Read-Host "Which one? [1-$($candidates.Count)], or paste a path"
    if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $candidates.Count) {
        $wow = $candidates[[int]$answer - 1]
    } elseif ($answer) {
        $wow = $answer.Trim('"')
    } else {
        Fail 'No selection made.'
    }
    Save-LocalWowDir $wow
} elseif (-not (Test-Path -LiteralPath $localFile)) {
    Save-LocalWowDir $wow
}

if (-not (Test-Path -LiteralPath $wow)) {
    Fail "WOW_DIR does not exist: $wow"
}

# ---------------------------------------------------------------- check flavor
$flavorDir = Join-Path $wow $flavor
if (-not (Test-Path -LiteralPath $flavorDir)) {
    $others = Get-ChildItem -LiteralPath $wow -Directory -Filter '_*_' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name
    $list = if ($others) { ($others | ForEach-Object { "  $_" }) -join "`n" } else { '  (none)' }
    Fail @"
$flavor not found in: $wow

Flavor folders that ARE there:
$list

Totemic Accord targets WoW Forever, which installs as $flavor.
Point WOW_DIR at the right install in $localFile.
"@
}

$addonsDir = Join-Path $flavorDir 'Interface\AddOns'
$target = Join-Path $addonsDir $addonName

if (-not (Test-Path -LiteralPath $addonsDir)) {
    New-Item -ItemType Directory -Force -Path $addonsDir | Out-Null
    Write-Host "Created $addonsDir" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- deploy
function Test-IsLink {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

Write-Host ''
if ($Link) {
    if (Test-Path -LiteralPath $target) {
        if (Test-IsLink $target) {
            # Replacing a junction with a junction: just drop the old one.
            cmd /c rmdir "$target" | Out-Null
        } else {
            $fileCount = (Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue).Count
            Write-Host "The target is a REAL folder with $fileCount file(s):" -ForegroundColor Yellow
            Write-Host "  $target" -ForegroundColor Yellow
            Write-Host 'Link mode must delete it and put a junction in its place.' -ForegroundColor Yellow
            if (-not $Force) {
                $ok = Read-Host 'Delete it and replace with a junction? [y/N]'
                if ($ok -notmatch '^(y|yes)$') { Write-Host 'Aborted.'; exit 1 }
            }
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
    cmd /c mklink /J "$target" "$source" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "mklink failed (exit $LASTEXITCODE)" }
    Write-Host 'LINKED (junction)' -ForegroundColor Green
    Write-Host "  $target" -ForegroundColor Green
    Write-Host "  -> $source" -ForegroundColor Green
    $mode = 'link'
} else {
    if (Test-IsLink $target) {
        Write-Host 'Target is currently a junction; removing it to copy instead.' -ForegroundColor Yellow
        cmd /c rmdir "$target" | Out-Null
    }
    # /MIR mirrors and deletes stale files in the target.
    # /NFL /NDL /NJH /NJS /NP keeps the output short; /R:2 /W:1 avoids long retry stalls.
    $roboArgs = @($source, $target, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:2', '/W:1')
    $out = & robocopy @roboArgs 2>&1
    # robocopy: 0-7 are success (8+ real failure). 1=copied, 2=extra removed, 3=both.
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        $out | ForEach-Object { Write-Host $_ }
        throw "robocopy failed (exit $rc)"
    }
    $copied = (Get-ChildItem -LiteralPath $target -Recurse -File).Count
    Write-Host 'COPIED (mirrored)' -ForegroundColor Green
    Write-Host "  $source" -ForegroundColor Green
    Write-Host "  -> $target  ($copied file(s))" -ForegroundColor Green
    if ($rc -band 2) { Write-Host '  stale files in the target were deleted' -ForegroundColor DarkGray }
    $mode = 'copy'
}

Write-Host ''
Write-Host 'In game:' -ForegroundColor Cyan
Write-Host '  Lua/XML changes  -> /reload is enough'
Write-Host '  NEW files or TOC changes -> fully restart the game client'
if ($mode -eq 'copy') {
    Write-Host '  (copy mode: re-run this script after every change)'
} else {
    Write-Host '  (link mode: edits are live, just /reload)'
}
Write-Host ''
Write-Host "Tip: /console scriptErrors 1   shows Lua errors in game" -ForegroundColor DarkGray
exit 0
