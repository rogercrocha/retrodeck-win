#Requires -Version 5.1
<#
.SYNOPSIS
    RetroDeck-Win Path Configurator

.DESCRIPTION
    Applies (or re-applies) data folder mappings to all installed emulators.

    Run this script in two situations:

      1. After first-time emulator launch
         Some emulators only generate their config files the first time they
         are launched. After launching each emulator once, run this script to
         map their config paths to your RetroDeck-Win data folder.

      2. After moving your data library to a new location
         If you relocate your data folder (e.g. to a new NAS, a different
         drive letter, or a new path), run this script with -DataRoot pointing
         to the new location. All emulator configs and Junction Points will be
         updated automatically.

    This script reads retrodeck-win.json from the installation root to determine
    the current paths. Pass -DataRoot to override the saved data_root value.

.PARAMETER InstallRoot
    Path where RetroDeck-Win is installed.
    Default: %LOCALAPPDATA%\RetroDeck-Win

.PARAMETER DataRoot
    New path for the data library. If omitted, the value stored in
    retrodeck-win.json is used. Pass this to relocate your data:
    .\Configure-Paths.ps1 -DataRoot "Z:\NewNAS\retrodeck"

.EXAMPLE
    # Re-apply current paths (e.g. after launching emulators for the first time)
    .\Configure-Paths.ps1

    # Move data library to a new NAS location
    .\Configure-Paths.ps1 -DataRoot "Z:\Gaming\retrodeck"

    # Use a non-default installation root
    .\Configure-Paths.ps1 -InstallRoot "D:\Games\RetroDeck-Win"

.NOTES
    Must be run as Administrator (required for Junction Points).
    Inspired by the RetroDECK project (https://github.com/retrodeck/retrodeck).
#>

param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\RetroDeck-Win",
    [string]$DataRoot    = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
#  Output helpers — keep consistent with Install.ps1
# ─────────────────────────────────────────────────────────────────────────────
function Write-Header { param($msg) Write-Host "`n═══ $msg ═══`n" -ForegroundColor Cyan }
function Write-Step   { param($msg) Write-Host "  → $msg" -ForegroundColor White }
function Write-OK     { param($msg) Write-Host "  ✔ $msg" -ForegroundColor Green }
function Write-Skip   { param($msg) Write-Host "  ⊘ $msg" -ForegroundColor DarkGray }
function Write-Warn   { param($msg) Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Fail   { param($msg) Write-Host "  ✘ $msg" -ForegroundColor Red }
function Write-Info   { param($msg) Write-Host "    $msg" -ForegroundColor DarkGray }

# ─────────────────────────────────────────────────────────────────────────────
#  Administrator check — Junction Points require elevation
# ─────────────────────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
               [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Fail "This script must be run as Administrator (required for Junction Points)."
    Write-Host "  Right-click PowerShell → 'Run as Administrator', then re-run." -ForegroundColor Yellow
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
#  Load saved configuration from retrodeck-win.json
# ─────────────────────────────────────────────────────────────────────────────
$configFile = Join-Path $InstallRoot "retrodeck-win.json"
if (-not (Test-Path $configFile)) {
    Write-Fail "retrodeck-win.json not found at '$InstallRoot'."
    Write-Host "  Make sure Install.ps1 was run first and that -InstallRoot is correct." -ForegroundColor Yellow
    exit 1
}

$config        = Get-Content $configFile -Raw | ConvertFrom-Json
$EmulatorsRoot = $config.emulators_root

# -DataRoot parameter takes priority over the saved value
if ($DataRoot -eq "") {
    $DataRoot = $config.data_root
}

# ─────────────────────────────────────────────────────────────────────────────
#  Banner
# ─────────────────────────────────────────────────────────────────────────────
Write-Host @"

  ____      _         ____  _____ ____ _  __  __        ___
 |  _ \ ___| |_ _ __ |  _ \| ____/ ___| |/ / \ \      / (_)_ __
 | |_) / _ \ __| '__| | | | |  _|| |   | ' /   \ \ /\ / /| | '_ \
 |  _ <  __/ |_| |  | |_| | |___| |___| . \    \ V  V / | | | | |
 |_| \_\___|\__|_|  |____/|_____\____|_|\_\    \_/\_/  |_|_|_| |_|

 Path Configurator
 ─────────────────────────────────────────────────────────────────

"@ -ForegroundColor Cyan

Write-Host "  Installation  : $InstallRoot" -ForegroundColor White
Write-Host "  Emulators     : $EmulatorsRoot" -ForegroundColor White
Write-Host "  Data library  : $DataRoot" -ForegroundColor White

if ($DataRoot -ne $config.data_root) {
    Write-Host ""
    Write-Warn "Data root is changing:"
    Write-Host "  From: $($config.data_root)" -ForegroundColor DarkGray
    Write-Host "  To  : $DataRoot" -ForegroundColor DarkGray
    Write-Warn "Make sure the new path is accessible before continuing."
}

Write-Host ""
Write-Host "  This script will:" -ForegroundColor DarkGray
Write-Host "    • Edit each emulator's config file to point to the data library" -ForegroundColor DarkGray
Write-Host "    • Create or update Junction Points for hardcoded emulator paths" -ForegroundColor DarkGray
Write-Host "    • Emulators whose config doesn't exist yet will be reported as skipped" -ForegroundColor DarkGray
Write-Host "      (launch them once to generate their config, then re-run this script)" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $DataRoot)) {
    Write-Warn "Data folder '$DataRoot' does not exist yet — it will be created."
    New-Item -ItemType Directory -Path $DataRoot -Force | Out-Null
    Write-OK "Created: $DataRoot"
    Write-Host ""
}

$confirm = Read-Host "  Apply path configuration? (Y/N)"
if ($confirm -notmatch "^[yY]") { Write-Host "  Cancelled." -ForegroundColor Yellow; exit 0 }

# ─────────────────────────────────────────────────────────────────────────────
#  Load Set-IniValue, New-Junction and Set-EmulatorPaths from Install.ps1.
#
#  Instead of duplicating those functions here, we dot-source the Install.ps1
#  up to (but not including) the MAIN block. This keeps the two scripts in sync
#  automatically whenever Install.ps1 is updated.
# ─────────────────────────────────────────────────────────────────────────────
$installScript = Join-Path $InstallRoot "Install.ps1"
if (-not (Test-Path $installScript)) {
    # Fallback: look in the same folder as this script (development / repo usage)
    $installScript = Join-Path $PSScriptRoot "Install.ps1"
}
if (-not (Test-Path $installScript)) {
    Write-Fail "Install.ps1 not found. Place Configure-Paths.ps1 in the same folder as Install.ps1."
    exit 1
}

Write-Info "Loading functions from Install.ps1..."

# Extract everything before the MAIN block and evaluate it as a script block.
# The MAIN block starts with the comment line "# ── MAIN ──" or the banner.
$scriptContent  = Get-Content $installScript -Raw
$mainSplitToken = "#  MAIN`r`n# ─────"
if ($scriptContent -notcontains $mainSplitToken) {
    $mainSplitToken = "#  MAIN`n# ─────"
}
$functionsOnly = ($scriptContent -split [regex]::Escape($mainSplitToken))[0]
Invoke-Expression $functionsOnly

# ─────────────────────────────────────────────────────────────────────────────
#  Apply the path mapping
# ─────────────────────────────────────────────────────────────────────────────
Set-EmulatorPaths -EmulatorsRoot $EmulatorsRoot -DataRoot $DataRoot

# ─────────────────────────────────────────────────────────────────────────────
#  Persist the (possibly new) DataRoot back to retrodeck-win.json
# ─────────────────────────────────────────────────────────────────────────────
if ($DataRoot -ne $config.data_root) {
    Write-Header "Updating configuration"
    $config.data_root = $DataRoot
    $config | ConvertTo-Json -Depth 3 | Set-Content -Path $configFile -Encoding UTF8
    Write-OK "retrodeck-win.json updated — new data_root: $DataRoot"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Done
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Done"
Write-Host "  Path mapping applied to all available emulator configs." -ForegroundColor White
Write-Host ""
Write-Host "  ── Reminders ────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  • Emulators reported as 'config not found': launch them once, then" -ForegroundColor DarkGray
Write-Host "    re-run this script." -ForegroundColor DarkGray
Write-Host "  • To move your data library again in the future:" -ForegroundColor DarkGray
Write-Host "    1. Move the RetroDeck-Win folder to the new location" -ForegroundColor DarkGray
Write-Host "    2. Run: .\Configure-Paths.ps1 -DataRoot `"<new path>`"" -ForegroundColor Cyan
Write-Host ""
