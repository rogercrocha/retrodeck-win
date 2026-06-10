#Requires -Version 5.1
<#
.SYNOPSIS
    RetroDeck-Win launcher — starts ES-DE and syncs Steam on exit.

.DESCRIPTION
    This script is the main entry point for RetroDeck-Win.
    It replaces calling ES-DE directly.

    What it does:
      1. Validates paths (install root, data library, ES-DE executable).
      2. Computes a hash of all gamelist.xml files to detect favorites changes.
      3. Launches ES-DE and waits for the user to close it.
      4. After ES-DE exits, re-computes the gamelist hash.
      5. If the hash changed (new favorites added/removed), automatically
         runs Sync-SteamFavorites.ps1 to update Steam shortcuts.
      6. If the hash is unchanged, skips the sync entirely (fast exit).

    No background processes. No scheduled tasks. No daemons.
    The detection and sync happen once, after each ES-DE session.

.PARAMETER InstallRoot
    Path where RetroDeck-Win is installed.
    Default: %LOCALAPPDATA%\RetroDeck-Win

.PARAMETER DataRoot
    Path to the RetroDeck-Win data library (ROMs, saves, etc.).
    If omitted, the value stored in retrodeck-win.json is used.

.PARAMETER SteamPath
    Path to your Steam installation.
    If omitted, auto-detected from the registry.

.PARAMETER ForcSync
    Run Sync-SteamFavorites.ps1 unconditionally after ES-DE closes,
    even if no gamelist changes are detected.

.PARAMETER NoSync
    Launch ES-DE without syncing Steam after it exits.
    Useful for quick sessions or troubleshooting.

.EXAMPLE
    # Normal launch (double-click or shortcut target)
    .\Launch-RetroDeckWin.ps1

    # Force a Steam sync even if nothing changed
    .\Launch-RetroDeckWin.ps1 -ForceSync

    # Launch ES-DE without any post-exit sync
    .\Launch-RetroDeckWin.ps1 -NoSync

.NOTES
    To create a desktop shortcut that runs this script:
      Target: powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LOCALAPPDATA%\RetroDeck-Win\Launch-RetroDeckWin.ps1"
      Start in: %LOCALAPPDATA%\RetroDeck-Win
#>

param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\RetroDeck-Win",
    [string]$DataRoot    = "",
    [string]$SteamPath   = "",
    [switch]$ForceSync,
    [switch]$NoSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
#  Output helpers
# ─────────────────────────────────────────────────────────────────────────────
function Write-Header { param($msg) Write-Host "`n═══ $msg ═══`n" -ForegroundColor Cyan }
function Write-Step   { param($msg) Write-Host "  → $msg" -ForegroundColor White }
function Write-OK     { param($msg) Write-Host "  ✔ $msg" -ForegroundColor Green }
function Write-Skip   { param($msg) Write-Host "  ⊘ $msg" -ForegroundColor DarkGray }
function Write-Warn   { param($msg) Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Fail   { param($msg) Write-Host "  ✘ $msg" -ForegroundColor Red }
function Write-Info   { param($msg) Write-Host "    $msg" -ForegroundColor DarkGray }

# ─────────────────────────────────────────────────────────────────────────────
#  Banner
# ─────────────────────────────────────────────────────────────────────────────
Write-Host @"

  ____      _         ____  _____ ____ _  __  __        ___
 |  _ \ ___| |_ _ __ |  _ \| ____/ ___| |/ / \ \      / (_)_ __
 | |_) / _ \ __| '__| | | | |  _|| |   | ' /   \ \ /\ / /| | '_ \
 |  _ <  __/ |_| |  | |_| | |___| |___| . \    \ V  V / | | | | |
 |_| \_\___|\__|_|  |____/|_____\____|_|\_\    \_/\_/  |_|_|_| |_|

 Launcher
 ─────────────────────────────────────────────────────────────────

"@ -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────────
#  Load retrodeck-win.json
# ─────────────────────────────────────────────────────────────────────────────
$configFile = Join-Path $InstallRoot "retrodeck-win.json"
if (-not (Test-Path $configFile)) {
    Write-Fail "retrodeck-win.json not found at '$InstallRoot'."
    Write-Host "  Run Install.ps1 first to set up RetroDeck-Win." -ForegroundColor Yellow
    Read-Host "  Press Enter to exit"
    exit 1
}

$config = Get-Content $configFile -Raw | ConvertFrom-Json

if ($DataRoot -eq "") { $DataRoot = $config.data_root }

$esDePath = if ($config.PSObject.Properties["esde_path"]) {
    $config.esde_path
} else {
    Join-Path $InstallRoot "ES-DE\ES-DE.exe"
}

Write-Host "  Install root  : $InstallRoot" -ForegroundColor White
Write-Host "  Data library  : $DataRoot" -ForegroundColor White
Write-Host "  ES-DE path    : $esDePath" -ForegroundColor White
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
#  Validate ES-DE executable
# ─────────────────────────────────────────────────────────────────────────────
if (-not (Test-Path $esDePath)) {
    Write-Fail "ES-DE not found at '$esDePath'."
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "    1. Download ES-DE from https://es-de.org and install to:"
    Write-Host "       $InstallRoot\ES-DE\" -ForegroundColor White
    Write-Host "    2. Update the 'esde_path' entry in retrodeck-win.json if installed elsewhere."
    Write-Host ""
    Read-Host "  Press Enter to exit"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
#  Gamelist hash helper
#
#  Hashes the name, size, and modification time of every gamelist.xml file.
#  This detects:
#    - New games added to a gamelist
#    - Games removed from a gamelist
#    - Changes to existing entries (e.g., favorite toggled)
#  It does NOT require reading the file contents, so it is fast even over NAS.
# ─────────────────────────────────────────────────────────────────────────────
function Get-GamelistHash {
    param([string]$GamelistRoot)
    $files = Get-ChildItem -Path $GamelistRoot -Recurse -Filter "gamelist.xml" `
             -ErrorAction SilentlyContinue | Sort-Object FullName
    if ($files.Count -eq 0) { return "" }
    $combined = ($files | ForEach-Object {
        "$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)|$($_.Length)"
    }) -join "`n"
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
    return [System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-',''
}

# ─────────────────────────────────────────────────────────────────────────────
#  Compute pre-launch gamelist hash
# ─────────────────────────────────────────────────────────────────────────────
$gamelistRoot = Join-Path $DataRoot "gamelists"
$hashBefore   = ""

if (Test-Path $gamelistRoot) {
    Write-Step "Computing gamelist snapshot before launch..."
    $hashBefore = Get-GamelistHash -GamelistRoot $gamelistRoot
    Write-Info "Hash: $($hashBefore.Substring(0,16))..."
} else {
    Write-Warn "Gamelists folder not found: $gamelistRoot"
    Write-Info "Scrape your games in ES-DE to generate gamelists."
}

# Retrieve the last saved hash from config (used to detect cumulative drift)
$savedHash = if ($config.PSObject.Properties["gamelist_hash"]) { $config.gamelist_hash } else { "" }

Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
#  Launch ES-DE
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Launching ES-DE"
Write-Step "Starting: $esDePath"
Write-Host ""

try {
    $esdeProcess = Start-Process -FilePath $esDePath -PassThru -ErrorAction Stop
} catch {
    Write-Fail "Failed to launch ES-DE: $_"
    Read-Host "  Press Enter to exit"
    exit 1
}

Write-OK "ES-DE started (PID $($esdeProcess.Id))"
Write-Info "Waiting for ES-DE to close..."
Write-Host ""

# Wait for the ES-DE process to exit
$esdeProcess.WaitForExit()

$exitCode = $esdeProcess.ExitCode
Write-Step "ES-DE closed (exit code: $exitCode)"

# ─────────────────────────────────────────────────────────────────────────────
#  Check for gamelist changes after ES-DE exits
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Checking for favorites changes"

if ($NoSync) {
    Write-Skip "NoSync flag set — skipping Steam sync."
    Write-Info "Run Sync-SteamFavorites.ps1 manually to sync when ready."
    Write-Host ""
    exit 0
}

$hashAfter = ""
if (Test-Path $gamelistRoot) {
    $hashAfter = Get-GamelistHash -GamelistRoot $gamelistRoot
}

# Determine whether sync is needed:
# - ForceSync: always sync
# - Hash changed vs. before-launch snapshot: favorites were modified this session
# - Hash changed vs. saved (last sync): accumulated drift from previous sessions

$syncReason = ""

if ($ForceSync) {
    $syncReason = "forced via -ForceSync"
} elseif ($hashBefore -ne $hashAfter -and $hashAfter -ne "") {
    $syncReason = "gamelist changed during this ES-DE session"
} elseif ($savedHash -ne $hashAfter -and $hashAfter -ne "" -and $savedHash -ne "") {
    $syncReason = "gamelist differs from last Steam sync"
}

if ($syncReason -eq "") {
    Write-OK "No changes detected — Steam sync skipped."
    Write-Info "Your Steam shortcuts are already up to date."
    Write-Host ""
    exit 0
}

Write-Step "Change detected: $syncReason."
Write-Step "Running Steam sync..."
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
#  Run Sync-SteamFavorites.ps1
# ─────────────────────────────────────────────────────────────────────────────
$syncScript = Join-Path $InstallRoot "Sync-SteamFavorites.ps1"

if (-not (Test-Path $syncScript)) {
    Write-Fail "Sync-SteamFavorites.ps1 not found at '$syncScript'."
    Write-Info "The sync script must be in the same folder as this launcher."
    Read-Host "  Press Enter to exit"
    exit 1
}

# Build arguments to pass through
$syncArgs = @()
if ($DataRoot   -ne "") { $syncArgs += "-DataRoot";   $syncArgs += "`"$DataRoot`"" }
if ($SteamPath  -ne "") { $syncArgs += "-SteamPath";  $syncArgs += "`"$SteamPath`"" }
if ($ForceSync)         { $syncArgs += "-Force" }

try {
    & powershell.exe -ExecutionPolicy Bypass -File $syncScript `
        -InstallRoot $InstallRoot @syncArgs
    $syncExitCode = $LASTEXITCODE
} catch {
    Write-Fail "Steam sync failed: $_"
    $syncExitCode = 1
}

if ($syncExitCode -eq 0) {
    Write-Header "All done"
    Write-OK "ES-DE session complete. Steam shortcuts are up to date."
} else {
    Write-Header "Sync had issues"
    Write-Warn "Sync-SteamFavorites.ps1 exited with code $syncExitCode."
    Write-Info "Run it manually to see the full output:"
    Write-Info "  .\Sync-SteamFavorites.ps1"
}

Write-Host ""
