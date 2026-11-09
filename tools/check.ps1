<#
.SYNOPSIS
    Totemic Accord - run all static checks.

.DESCRIPTION
    Three checks, in order:
      1. luac 5.1 -p      syntax, against the same Lua version WoW runs
      2. check_api.py     every API we call exists on Forever
      3. luacheck         accidental globals, unused locals, undefined API
                          (fed the generated Forever API surface via .luacheckrc)

    Tools are resolved by PATH first, then by known install locations, because a
    freshly installed tool is not on PATH in already-running shells.

.PARAMETER Fix
    Also run StyLua to format the code (modifies files).

.EXAMPLE
    .\tools\check.ps1
    .\tools\check.ps1 -Fix
#>
[CmdletBinding()]
param(
    [switch]$Fix
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Resolve-Tool {
    param([string]$Name, [string[]]$Candidates)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in $Candidates) {
        $expanded = [Environment]::ExpandEnvironmentVariables($c)
        if (Test-Path -LiteralPath $expanded) { return $expanded }
    }
    return $null
}

$luac = Resolve-Tool 'luac5.1' @(
    'C:\ProgramData\chocolatey\lib\lua51\tools\luac5.1.exe',
    '%LOCALAPPDATA%\Programs\lua\luac5.1.exe'
)
$luacheck = Resolve-Tool 'luacheck' @(
    '%LOCALAPPDATA%\Programs\luacheck\luacheck.exe',
    'C:\ProgramData\chocolatey\bin\luacheck.exe'
)
$python = Resolve-Tool 'python' @('C:\Python314\python.exe')
$stylua = Resolve-Tool 'stylua' @('%LOCALAPPDATA%\Microsoft\WinGet\Links\stylua.exe')

# Our Lua only -- never the vendored libraries.
$luaFiles = Get-ChildItem -Path 'TotemicAccord' -Filter '*.lua' -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\Libs\\' } |
    ForEach-Object { Resolve-Path -Relative $_.FullName }

$failures = @()

Write-Host ''
Write-Host '=== 1/3  Lua 5.1 syntax (luac -p) ===' -ForegroundColor Cyan
if (-not $luac) {
    Write-Host '  SKIPPED - luac5.1 not found (choco install lua51)' -ForegroundColor Yellow
} elseif (-not $luaFiles) {
    Write-Host '  nothing to check yet' -ForegroundColor DarkGray
} else {
    $syntaxBad = $false
    foreach ($f in $luaFiles) {
        $out = & $luac -p $f 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAIL $f" -ForegroundColor Red
            $out | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
            $syntaxBad = $true
        }
    }
    if ($syntaxBad) { $failures += 'luac -p' }
    else { Write-Host "  OK - $($luaFiles.Count) file(s)" -ForegroundColor Green }
}

Write-Host ''
Write-Host '=== 2/3  Forever API allowlist (check_api.py) ===' -ForegroundColor Cyan
if (-not $python) {
    Write-Host '  SKIPPED - python not found' -ForegroundColor Yellow
} elseif (-not (Test-Path 'reference/wow-ui-source/Interface')) {
    Write-Host '  SKIPPED - reference/wow-ui-source missing. Clone it with:' -ForegroundColor Yellow
    Write-Host '    git clone --depth 1 --branch forever https://github.com/Gethe/wow-ui-source reference/wow-ui-source' -ForegroundColor Yellow
} else {
    # Regenerate the globals list so .luacheckrc lints against current Forever.
    & $python 'tools/check_api.py' --emit-luacheck 'tools/wow_globals.lua'
    if ($LASTEXITCODE -ne 0) { $failures += 'check_api --emit-luacheck' }

    & $python 'tools/check_api.py'
    if ($LASTEXITCODE -ne 0) { $failures += 'check_api' }
}

Write-Host ''
Write-Host '=== 3/3  luacheck ===' -ForegroundColor Cyan
if (-not $luacheck) {
    Write-Host '  SKIPPED - luacheck not found' -ForegroundColor Yellow
} elseif (-not $luaFiles) {
    Write-Host '  nothing to check yet' -ForegroundColor DarkGray
} else {
    if (-not (Test-Path 'tools/wow_globals.lua')) {
        Write-Host '  NOTE: tools/wow_globals.lua missing - .luacheckrc is falling back to' -ForegroundColor Yellow
        Write-Host '        its small curated API list, so API coverage is incomplete.' -ForegroundColor Yellow
    }
    & $luacheck $luaFiles
    if ($LASTEXITCODE -ne 0) { $failures += 'luacheck' }
}

if ($Fix) {
    Write-Host ''
    Write-Host '=== format (StyLua) ===' -ForegroundColor Cyan
    if (-not $stylua) {
        Write-Host '  SKIPPED - stylua not found' -ForegroundColor Yellow
    } elseif ($luaFiles) {
        & $stylua $luaFiles
        Write-Host '  formatted' -ForegroundColor Green
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "CHECK FAILED: $($failures -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
