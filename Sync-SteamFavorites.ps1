#Requires -Version 5.1
<#
.SYNOPSIS
    RetroDeck-Win Steam Favorites Sync

.DESCRIPTION
    Reads ES-DE's gamelist.xml files, finds all games marked as favorites,
    and adds them as non-Steam shortcuts in Steam's shortcuts.vdf.

    Also installs Steam Input controller templates so that all synced games
    automatically get the RetroDeck-Win hotkey layout (Select as modifier):

      Select + A        → Save State   (F1)
      Select + B        → Load State   (F3)
      Select + X        → Reset        (F5)
      Select + Y        → Screenshot   (F8)
      Select + Start    → Quit         (Escape)
      Select + L1       → Pause        (P)
      Select + R1       → Fast Forward (Tab)
      Select + DPad Up  → Slot +1      (F2)
      Select + DPad Dn  → Slot -1      (Shift+F2)
      Select + DPad Rt  → Fast Forward (Tab)
      Select + DPad Lt  → Rewind       (R)

    Equivalent of RetroDECK's Steam Sync + Steam Input injection on Linux.

    How it works:
      1. Installs .vdf controller templates into Steam\controller_base\templates\
      2. Scans every gamelist.xml under <DataRoot>\gamelists\
      3. Collects all <game> entries where <favorite>true</favorite>
      4. For each favorite, creates a Steam shortcut (shortcuts.vdf)
      5. Downloads box art / hero / logo from SteamGridDB (requires API key in
         retrodeck-win.json; skipped gracefully if key is absent)
      6. Associates the RetroDeck-Win controller template with each shortcut
         by writing the controller_config entry in localconfig.vdf
      7. Saves a hash of the gamelist state to detect future changes

    Steam must be closed while this script runs, or it will overwrite
    the files on exit and your changes will be lost.

.PARAMETER InstallRoot
    Path where RetroDeck-Win is installed.
    Default: %LOCALAPPDATA%\RetroDeck-Win

.PARAMETER DataRoot
    Path to the RetroDeck-Win data library.
    If omitted, the value stored in retrodeck-win.json is used.

.PARAMETER SteamPath
    Path to your Steam installation.
    Default: auto-detected from the registry.

.PARAMETER Remove
    Remove all RetroDeck-Win shortcuts from Steam instead of adding them.
    Also removes the controller template associations from localconfig.vdf.

.PARAMETER DryRun
    Show what would be added/removed without writing any files.

.PARAMETER Force
    Skip the gamelist hash check and always perform a full sync,
    even if no changes are detected.

.EXAMPLE
    # Sync favorites (normal usage — called by Launch-RetroDeckWin.ps1)
    .\Sync-SteamFavorites.ps1

    # Force a full re-sync even if nothing changed
    .\Sync-SteamFavorites.ps1 -Force

    # Remove all RetroDeck-Win shortcuts from Steam
    .\Sync-SteamFavorites.ps1 -Remove

    # Preview changes without writing
    .\Sync-SteamFavorites.ps1 -DryRun

.NOTES
    Steam must be closed before running this script.
    Inspired by the RetroDECK project (https://github.com/retrodeck/retrodeck).
    shortcuts.vdf format:   https://developer.valvesoftware.com/wiki/Steam_Library_Shortcuts
    Steam Input templates:  https://retrodeck.readthedocs.io/en/latest/wiki_development/general/steam-input/
#>

param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\RetroDeck-Win",
    [string]$DataRoot    = "",
    [string]$SteamPath   = "",
    [switch]$Remove,
    [switch]$DryRun,
    [switch]$Force
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

 Steam Favorites Sync
 ─────────────────────────────────────────────────────────────────

"@ -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────────
#  Load retrodeck-win.json
# ─────────────────────────────────────────────────────────────────────────────
$configFile = Join-Path $InstallRoot "retrodeck-win.json"
if (-not (Test-Path $configFile)) {
    Write-Fail "retrodeck-win.json not found at '$InstallRoot'."
    Write-Host "  Run Install.ps1 first or pass -InstallRoot with the correct path." -ForegroundColor Yellow
    exit 1
}

$config        = Get-Content $configFile -Raw | ConvertFrom-Json
$EmulatorsRoot = $config.emulators_root
if ($DataRoot -eq "") { $DataRoot = $config.data_root }

Write-Host "  Data library  : $DataRoot" -ForegroundColor White
Write-Host "  Emulators     : $EmulatorsRoot" -ForegroundColor White

# ─────────────────────────────────────────────────────────────────────────────
#  Locate Steam installation
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Locating Steam"

if ($SteamPath -eq "") {
    $regPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"
    )
    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            $val = (Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue).SteamPath
            if ($val -and (Test-Path $val)) { $SteamPath = $val; break }
        }
    }
}

if ($SteamPath -eq "" -or -not (Test-Path $SteamPath)) {
    foreach ($d in @("C:\Program Files (x86)\Steam","C:\Program Files\Steam")) {
        if (Test-Path $d) { $SteamPath = $d; break }
    }
}

if ($SteamPath -eq "" -or -not (Test-Path $SteamPath)) {
    Write-Fail "Steam installation not found. Pass -SteamPath 'C:\Path\To\Steam'."
    exit 1
}
Write-OK "Steam found: $SteamPath"

# ─────────────────────────────────────────────────────────────────────────────
#  Find Steam user account
# ─────────────────────────────────────────────────────────────────────────────
$userdataRoot = Join-Path $SteamPath "userdata"
if (-not (Test-Path $userdataRoot)) {
    Write-Fail "Steam userdata folder not found. Log in to Steam at least once."
    exit 1
}

$userFolders = Get-ChildItem -Path $userdataRoot -Directory |
               Where-Object { $_.Name -match '^\d+$' }

if ($userFolders.Count -eq 0) {
    Write-Fail "No Steam user accounts found in '$userdataRoot'."
    exit 1
}

if ($userFolders.Count -gt 1) {
    Write-Warn "Multiple Steam accounts detected:"
    $i = 0; foreach ($u in $userFolders) { Write-Host ("    [{0}] {1}" -f $i, $u.Name) -ForegroundColor White; $i++ }
    $choice = Read-Host "  Which account to sync? (0-$($userFolders.Count - 1))"
    $steamUserFolder = $userFolders[[int]$choice].FullName
} else {
    $steamUserFolder = $userFolders[0].FullName
    Write-OK "Steam user: $($userFolders[0].Name)"
}

$shortcutsVdf  = Join-Path $steamUserFolder "config\shortcuts.vdf"
$localconfigVdf= Join-Path $steamUserFolder "config\localconfig.vdf"
$configDir     = Split-Path $shortcutsVdf -Parent
if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }

# ─────────────────────────────────────────────────────────────────────────────
#  Check Steam is closed
# ─────────────────────────────────────────────────────────────────────────────
$steamProcess = Get-Process -Name "steam" -ErrorAction SilentlyContinue
if ($steamProcess) {
    Write-Warn "Steam is currently running."
    Write-Host "  Steam will overwrite shortcuts.vdf when it exits, losing your new shortcuts." -ForegroundColor Yellow
    $ok = Read-Host "  Close Steam now, then press Y to continue (or N to abort)"
    if ($ok -notmatch "^[yY]") { Write-Host "  Cancelled." -ForegroundColor Yellow; exit 0 }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Steam Input templates
#
#  Template files live in: <InstallRoot>\steam-input\*.vdf
#  They are copied to:     <SteamPath>\controller_base\templates\
#
#  Template filename → controller_type mapping:
#    RetroDeck-Win_controller_xbox_hotkeys.vdf     → controller_xbox360
#    RetroDeck-Win_controller_xboxone_hotkeys.vdf  → controller_xboxone
#    RetroDeck-Win_controller_ps4_hotkeys.vdf      → controller_ps4
#    RetroDeck-Win_controller_ps5_hotkeys.vdf      → controller_ps5
#    RetroDeck-Win_controller_switch_pro_hotkeys.vdf→ controller_switch_pro
#    RetroDeck-Win_controller_generic_hotkeys.vdf  → controller_generic
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Installing Steam Input controller templates"

$templateSrcDir = Join-Path $InstallRoot "steam-input"
$templateDstDir = Join-Path $SteamPath "controller_base\templates"

# Map controller_type → template filename (used later for localconfig.vdf)
$controllerTemplateMap = @{
    # Xbox
    "controller_xbox360"                 = "RetroDeck-Win_controller_xbox_hotkeys.vdf"
    "controller_xboxone"                 = "RetroDeck-Win_controller_xboxone_hotkeys.vdf"
    # PlayStation
    "controller_ps3"                     = "RetroDeck-Win_controller_ps3_hotkeys.vdf"
    "controller_ps4"                     = "RetroDeck-Win_controller_ps4_hotkeys.vdf"
    "controller_ps5"                     = "RetroDeck-Win_controller_ps5_hotkeys.vdf"
    "controller_ps5_edge"                = "RetroDeck-Win_controller_ps5edge_hotkeys.vdf"
    # Nintendo
    "controller_switch_pro"              = "RetroDeck-Win_controller_switch_pro_hotkeys.vdf"
    # Valve
    "controller_steamcontroller_gordon"  = "RetroDeck-Win_controller_gordon_hotkeys.vdf"
    # Generic / fallback
    "controller_generic"                 = "RetroDeck-Win_controller_generic_hotkeys.vdf"
}

if (-not (Test-Path $templateSrcDir)) {
    Write-Warn "steam-input folder not found at '$templateSrcDir' — skipping template install."
    Write-Info "Place the .vdf template files in that folder to enable controller hotkeys."
} elseif (-not (Test-Path $templateDstDir)) {
    Write-Warn "Steam controller_base\templates folder not found — skipping template install."
} else {
    $vdfFiles = Get-ChildItem -Path $templateSrcDir -Filter "RetroDeck-Win_*.vdf"
    if ($vdfFiles.Count -eq 0) {
        Write-Warn "No RetroDeck-Win_*.vdf files found in '$templateSrcDir'."
    } else {
        foreach ($vdf in $vdfFiles) {
            $dst = Join-Path $templateDstDir $vdf.Name
            if ($DryRun) {
                Write-Skip "[DRY RUN] Would copy: $($vdf.Name)"
            } else {
                Copy-Item $vdf.FullName $dst -Force
                Write-OK "Installed: $($vdf.Name)"
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Gamelist hash check — skip sync if nothing changed
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Checking for changes"

function Get-GamelistHash {
    param([string]$GamelistRoot)
    $files = Get-ChildItem -Path $GamelistRoot -Recurse -Filter "gamelist.xml" -ErrorAction SilentlyContinue |
             Sort-Object FullName
    if ($files.Count -eq 0) { return "" }
    $combined = ($files | ForEach-Object {
        "$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)|$($_.Length)"
    }) -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
    return [System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-',''
}

$gamelistRoot = Join-Path $DataRoot "gamelists"
$currentHash  = ""

if (Test-Path $gamelistRoot) {
    $currentHash = Get-GamelistHash -GamelistRoot $gamelistRoot
}

$savedHash = if ($config.PSObject.Properties["gamelist_hash"]) { $config.gamelist_hash } else { "" }

if (-not $Force -and -not $Remove -and $currentHash -ne "" -and $currentHash -eq $savedHash) {
    Write-OK "No changes detected in gamelists — sync skipped."
    Write-Info "Use -Force to sync anyway."
    exit 0
}

if ($currentHash -ne $savedHash) {
    Write-Step "Gamelist changes detected — proceeding with sync."
} elseif ($Force) {
    Write-Step "-Force flag set — running full sync."
} elseif ($Remove) {
    Write-Step "-Remove flag set — removing all RetroDeck-Win shortcuts."
}

# ─────────────────────────────────────────────────────────────────────────────
#  System → emulator map
# ─────────────────────────────────────────────────────────────────────────────
$systemMap = @(
    # RetroArch systems
    @{ System="nes";         Exe="RetroArch\retroarch.exe"; Args="-L cores\nestopia_libretro.dll `"{ROM}`"" }
    @{ System="snes";        Exe="RetroArch\retroarch.exe"; Args="-L cores\snes9x_libretro.dll `"{ROM}`"" }
    @{ System="gb";          Exe="RetroArch\retroarch.exe"; Args="-L cores\gambatte_libretro.dll `"{ROM}`"" }
    @{ System="gbc";         Exe="RetroArch\retroarch.exe"; Args="-L cores\gambatte_libretro.dll `"{ROM}`"" }
    @{ System="gba";         Exe="RetroArch\retroarch.exe"; Args="-L cores\mgba_libretro.dll `"{ROM}`"" }
    @{ System="genesis";     Exe="RetroArch\retroarch.exe"; Args="-L cores\genesis_plus_gx_libretro.dll `"{ROM}`"" }
    @{ System="megadrive";   Exe="RetroArch\retroarch.exe"; Args="-L cores\genesis_plus_gx_libretro.dll `"{ROM}`"" }
    @{ System="mastersystem";Exe="RetroArch\retroarch.exe"; Args="-L cores\genesis_plus_gx_libretro.dll `"{ROM}`"" }
    @{ System="gamegear";    Exe="RetroArch\retroarch.exe"; Args="-L cores\genesis_plus_gx_libretro.dll `"{ROM}`"" }
    @{ System="n64";         Exe="RetroArch\retroarch.exe"; Args="-L cores\mupen64plus_next_libretro.dll `"{ROM}`"" }
    @{ System="psx";         Exe="RetroArch\retroarch.exe"; Args="-L cores\mednafen_psx_libretro.dll `"{ROM}`"" }
    @{ System="pce";         Exe="RetroArch\retroarch.exe"; Args="-L cores\mednafen_pce_libretro.dll `"{ROM}`"" }
    @{ System="pcengine";    Exe="RetroArch\retroarch.exe"; Args="-L cores\mednafen_pce_libretro.dll `"{ROM}`"" }
    @{ System="segacd";      Exe="RetroArch\retroarch.exe"; Args="-L cores\genesis_plus_gx_libretro.dll `"{ROM}`"" }
    @{ System="sega32x";     Exe="RetroArch\retroarch.exe"; Args="-L cores\picodrive_libretro.dll `"{ROM}`"" }
    @{ System="atari2600";   Exe="RetroArch\retroarch.exe"; Args="-L cores\stella2014_libretro.dll `"{ROM}`"" }
    @{ System="atari7800";   Exe="RetroArch\retroarch.exe"; Args="-L cores\prosystem_libretro.dll `"{ROM}`"" }
    @{ System="fds";         Exe="RetroArch\retroarch.exe"; Args="-L cores\nestopia_libretro.dll `"{ROM}`"" }
    @{ System="msx";         Exe="RetroArch\retroarch.exe"; Args="-L cores\bluemsx_libretro.dll `"{ROM}`"" }
    @{ System="msx2";        Exe="RetroArch\retroarch.exe"; Args="-L cores\bluemsx_libretro.dll `"{ROM}`"" }
    @{ System="virtualboy";  Exe="RetroArch\retroarch.exe"; Args="-L cores\mednafen_vb_libretro.dll `"{ROM}`"" }
    @{ System="lynx";        Exe="RetroArch\retroarch.exe"; Args="-L cores\mednafen_lynx_libretro.dll `"{ROM}`"" }
    @{ System="ngp";         Exe="RetroArch\retroarch.exe"; Args="-L cores\mednafen_ngp_libretro.dll `"{ROM}`"" }
    @{ System="ngpc";        Exe="RetroArch\retroarch.exe"; Args="-L cores\mednafen_ngp_libretro.dll `"{ROM}`"" }
    @{ System="wonderswan";  Exe="RetroArch\retroarch.exe"; Args="-L cores\mednafen_wswan_libretro.dll `"{ROM}`"" }
    @{ System="wonderswancolor"; Exe="RetroArch\retroarch.exe"; Args="-L cores\mednafen_wswan_libretro.dll `"{ROM}`"" }
    # Standalone emulators
    @{ System="nds";  Exe="melonDS\melonDS.exe";                              Args="`"{ROM}`"" }
    @{ System="ps2";  Exe="PCSX2\pcsx2-qt.exe";                               Args="`"{ROM}`"" }
    @{ System="psp";  Exe="PPSSPP\PPSSPPWindows64.exe";                       Args="`"{ROM}`"" }
    @{ System="gc";   Exe="Dolphin\Dolphin.exe";                              Args="-b -e `"{ROM}`"" }
    @{ System="wii";  Exe="Dolphin\Dolphin.exe";                              Args="-b -e `"{ROM}`"" }
    @{ System="ps3";  Exe="RPCS3\rpcs3.exe";                                  Args="--no-gui `"{ROM}`"" }
    @{ System="xbox"; Exe="xemu\xemu.exe";                                    Args="-dvd_path `"{ROM}`"" }
    @{ System="psvita"; Exe="Vita3K\Vita3K.exe";                              Args="-r `"{ROM}`"" }
    @{ System="wiiu"; Exe="Cemu\Cemu.exe";                                    Args="-f -g `"{ROM}`"" }
    @{ System="3ds";  Exe="Azahar\azahar.exe";                                Args="`"{ROM}`"" }
    @{ System="doom"; Exe="GZDoom\gzdoom.exe";                                Args="-iwad `"{ROM}`"" }
    @{ System="arcade"; Exe="MAME\mame.exe";                                  Args="`"{ROM}`"" }
    @{ System="mame"; Exe="MAME\mame.exe";                                    Args="`"{ROM}`"" }
    @{ System="flash"; Exe="Ruffle\ruffle.exe";                               Args="`"{ROM}`"" }
)

$systemLookup = @{}
foreach ($e in $systemMap) {
    if (-not $systemLookup.ContainsKey($e.System)) { $systemLookup[$e.System] = $e }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Scan gamelists for favorites
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Scanning ES-DE gamelists for favorites"

$favorites = [System.Collections.Generic.List[hashtable]]::new()

if (-not (Test-Path $gamelistRoot)) {
    Write-Warn "Gamelists folder not found: $gamelistRoot"
    Write-Info "Scrape your games in ES-DE, mark favorites, then re-run this script."
    if (-not $Remove) { exit 0 }
} else {
    $gamelistFiles = Get-ChildItem -Path $gamelistRoot -Recurse -Filter "gamelist.xml" -ErrorAction SilentlyContinue

    foreach ($glFile in $gamelistFiles) {
        $systemName = $glFile.Directory.Name
        [xml]$gl = Get-Content $glFile.FullName -Raw -Encoding UTF8
        $favGames = $gl.gameList.game | Where-Object { $_.favorite -eq "true" }
        if (-not $favGames) { continue }
        $count = @($favGames).Count
        Write-Step "$systemName — $count favorite(s)"

        foreach ($game in $favGames) {
            $romRelPath = $game.path -replace '^\./','  '
            $romRelPath = $romRelPath.Trim()
            $romFullPath = if ([System.IO.Path]::IsPathRooted($romRelPath)) {
                $romRelPath
            } else {
                Join-Path (Join-Path $DataRoot "roms\$systemName") $romRelPath
            }
            $gameName  = if ($game.name) { $game.name } else { [System.IO.Path]::GetFileNameWithoutExtension($romFullPath) }
            $emuEntry  = $systemLookup[$systemName]
            if (-not $emuEntry) { Write-Skip "  $gameName — no emulator mapping for '$systemName'"; continue }

            $exeFullPath = Join-Path $EmulatorsRoot $emuEntry.Exe
            $launchArgs  = $emuEntry.Args -replace '\{ROM\}', $romFullPath

            $favorites.Add(@{
                Name     = $gameName
                Exe      = "`"$exeFullPath`""
                StartDir = Split-Path $exeFullPath -Parent
                Args     = $launchArgs
                System   = $systemName
            })
        }
    }
    Write-Host ""
    Write-OK "Total favorites found: $($favorites.Count)"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Binary VDF helpers for shortcuts.vdf
# ─────────────────────────────────────────────────────────────────────────────
function Get-Crc32 {
    param([byte[]]$Bytes)
    $table = [uint32[]]::new(256)
    for ($i = 0; $i -lt 256; $i++) {
        [uint32]$c = $i
        for ($j = 0; $j -lt 8; $j++) {
            if ($c -band 1) { $c = 0xEDB88320 -bxor ($c -shr 1) } else { $c = $c -shr 1 }
        }
        $table[$i] = $c
    }
    [uint32]$crc = 0xFFFFFFFF
    foreach ($b in $Bytes) { $idx = ($crc -bxor $b) -band 0xFF; $crc = ($crc -shr 8) -bxor $table[$idx] }
    return $crc -bxor 0xFFFFFFFF
}

function Get-SteamAppId {
    param([string]$AppName, [string]$Exe)
    $combined = $AppName + $Exe + "`0"
    $enc   = [System.Text.Encoding]::GetEncoding(1252)
    $bytes = $enc.GetBytes($combined)
    $crc   = Get-Crc32 -Bytes $bytes
    return [uint32]($crc -bor 0x80000000)
}

function Read-NullString {
    param([System.IO.BinaryReader]$Reader)
    $bytes = [System.Collections.Generic.List[byte]]::new()
    while ($true) { $b = $Reader.ReadByte(); if ($b -eq 0) { break }; $bytes.Add($b) }
    return [System.Text.Encoding]::UTF8.GetString($bytes.ToArray())
}

function Skip-VdfDict {
    param([System.IO.BinaryReader]$Reader)
    while ($true) {
        $type = $Reader.ReadByte()
        if ($type -eq 0x08) { return }
        Read-NullString $Reader | Out-Null
        switch ($type) {
            0x00 { Skip-VdfDict $Reader }
            0x01 { Read-NullString $Reader | Out-Null }
            0x02 { $Reader.ReadInt32() | Out-Null }
        }
    }
}

function Read-ShortcutsVdf {
    param([string]$Path)
    $list = [System.Collections.Generic.List[hashtable]]::new()
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) { return $list }
    $fs = [System.IO.File]::OpenRead($Path)
    $reader = [System.IO.BinaryReader]::new($fs, [System.Text.Encoding]::UTF8)
    try {
        $rootType = $reader.ReadByte(); $rootKey = Read-NullString $reader
        if ($rootType -ne 0 -or $rootKey -ne "shortcuts") { Write-Warn "shortcuts.vdf has unexpected root — will overwrite."; return $list }
        while ($true) {
            $type = $reader.ReadByte(); if ($type -eq 0x08) { break }; if ($type -ne 0x00) { break }
            $idxKey = Read-NullString $reader
            $sc = @{ idx=$idxKey; AppName=""; Exe=""; StartDir=""; Icon=""; LaunchOptions=""; Tags=@() }
            while ($true) {
                $fType = $reader.ReadByte(); if ($fType -eq 0x08) { break }
                $fKey = Read-NullString $reader
                switch ($fType) {
                    0x00 {
                        if ($fKey -eq "tags") {
                            $tags = [System.Collections.Generic.List[string]]::new()
                            while ($true) { $tType=$reader.ReadByte(); if ($tType -eq 0x08){break}; Read-NullString $reader|Out-Null; $tags.Add((Read-NullString $reader)) }
                            $sc.Tags = $tags.ToArray()
                        } else { Skip-VdfDict $reader }
                    }
                    0x01 {
                        $val = Read-NullString $reader
                        switch ($fKey) { "AppName"{$sc.AppName=$val} "Exe"{$sc.Exe=$val} "StartDir"{$sc.StartDir=$val} "icon"{$sc.Icon=$val} "LaunchOptions"{$sc.LaunchOptions=$val} }
                    }
                    0x02 { $reader.ReadInt32() | Out-Null }
                }
            }
            $list.Add($sc)
        }
    } finally { $reader.Close(); $fs.Close() }
    return $list
}

function Write-StringField { param([System.IO.BinaryWriter]$W,[string]$K,[string]$V)
    $W.Write([byte]0x01); $W.Write([System.Text.Encoding]::ASCII.GetBytes($K)); $W.Write([byte]0x00)
    $W.Write([System.Text.Encoding]::UTF8.GetBytes($V)); $W.Write([byte]0x00) }

function Write-Int32Field { param([System.IO.BinaryWriter]$W,[string]$K,[int]$V)
    $W.Write([byte]0x02); $W.Write([System.Text.Encoding]::ASCII.GetBytes($K)); $W.Write([byte]0x00); $W.Write([int32]$V) }

function Write-BoolField { param([System.IO.BinaryWriter]$W,[string]$K,[bool]$V) Write-Int32Field $W $K ([int]$V) }

function Write-ShortcutEntry {
    param([System.IO.BinaryWriter]$Writer, [int]$Index, [hashtable]$Sc)
    $appId = Get-SteamAppId -AppName $Sc.AppName -Exe $Sc.Exe
    $Writer.Write([byte]0x00); $Writer.Write([System.Text.Encoding]::ASCII.GetBytes($Index.ToString())); $Writer.Write([byte]0x00)
    Write-Int32Field  $Writer "appid"               ([int][uint32]$appId)
    Write-StringField $Writer "AppName"             $Sc.AppName
    Write-StringField $Writer "Exe"                 $Sc.Exe
    Write-StringField $Writer "StartDir"            ($Sc.StartDir -as [string] ?? "")
    Write-StringField $Writer "icon"                ($Sc.Icon -as [string] ?? "")
    Write-StringField $Writer "ShortcutPath"        ""
    Write-StringField $Writer "LaunchOptions"       ($Sc.LaunchOptions -as [string] ?? "")
    Write-BoolField   $Writer "IsHidden"            $false
    Write-BoolField   $Writer "AllowDesktopConfig"  $true
    Write-BoolField   $Writer "AllowOverlay"        $true
    Write-BoolField   $Writer "OpenVR"              $false
    Write-BoolField   $Writer "Devkit"              $false
    Write-StringField $Writer "DevkitGameID"        ""
    Write-Int32Field  $Writer "DevkitOverrideAppID" 0
    Write-Int32Field  $Writer "LastPlayTime"        0
    Write-StringField $Writer "FlatpakAppID"        ""
    Write-StringField $Writer "sortas"              ""
    # tags dict
    $Writer.Write([byte]0x00); $Writer.Write([System.Text.Encoding]::ASCII.GetBytes("tags")); $Writer.Write([byte]0x00)
    $tags = if ($Sc.Tags) { $Sc.Tags } else { @() }
    $ti = 0
    foreach ($tag in $tags) {
        $Writer.Write([byte]0x01); $Writer.Write([System.Text.Encoding]::ASCII.GetBytes($ti.ToString())); $Writer.Write([byte]0x00)
        $Writer.Write([System.Text.Encoding]::UTF8.GetBytes($tag)); $Writer.Write([byte]0x00); $ti++
    }
    $Writer.Write([byte]0x08)   # end tags
    $Writer.Write([byte]0x08)   # end shortcut
}

function Write-ShortcutsVdf {
    param([string]$Path, [System.Collections.Generic.List[hashtable]]$Shortcuts)
    $ms = [System.IO.MemoryStream]::new()
    $w  = [System.IO.BinaryWriter]::new($ms, [System.Text.Encoding]::UTF8)
    $w.Write([byte]0x00); $w.Write([System.Text.Encoding]::ASCII.GetBytes("shortcuts")); $w.Write([byte]0x00)
    $idx = 0
    foreach ($sc in $Shortcuts) { Write-ShortcutEntry $w $idx $sc; $idx++ }
    $w.Write([byte]0x08); $w.Write([byte]0x08); $w.Flush()
    [System.IO.File]::WriteAllBytes($Path, $ms.ToArray())
    $w.Close()
}

# ─────────────────────────────────────────────────────────────────────────────
#  Text VDF helpers for localconfig.vdf
#
#  localconfig.vdf is a text-format KeyValues file. We patch just the
#  controller_config section under each AppID inside "apps" → "shortcuts".
#
#  Structure we inject (per AppID):
#    "apps"
#    {
#      "<appid_decimal>"
#      {
#        "controller_config"
#        {
#          "<controller_type>"
#          {
#            "DEFAULT_FOR_TYPE"    "1"
#            "template"            "RetroDeck-Win_controller_<X>_hotkeys.vdf"
#          }
#          ...
#        }
#      }
#    }
# ─────────────────────────────────────────────────────────────────────────────

function Build-ControllerConfigBlock {
    # Returns the controller_config VDF text block for a given AppID
    param([string]$Indent = "`t`t`t")
    $i1 = $Indent
    $i2 = $Indent + "`t"
    $i3 = $Indent + "`t`t"
    $i4 = $Indent + "`t`t`t"

    $block = "${i1}`"controller_config`"`n${i1}{`n"
    foreach ($kvp in $script:controllerTemplateMap.GetEnumerator()) {
        $ctype    = $kvp.Key
        $template = $kvp.Value
        $block += "${i2}`"$ctype`"`n${i2}{`n"
        $block += "${i3}`"DEFAULT_FOR_TYPE`"`t`t`"1`"`n"
        $block += "${i3}`"template`"`t`t`"$template`"`n"
        $block += "${i2}}`n"
    }
    $block += "${i1}}`n"
    return $block
}

function Update-LocalConfigVdf {
    param(
        [string]$Path,
        [uint32[]]$AppIds,   # AppIDs to ADD controller_config for
        [uint32[]]$RemoveIds # AppIDs to REMOVE controller_config for
    )

    if (-not (Test-Path $Path)) {
        Write-Warn "localconfig.vdf not found — skipping controller template association."
        Write-Info "Launch Steam once and re-run to create localconfig.vdf."
        return
    }

    $content = Get-Content $Path -Raw -Encoding UTF8

    # ── Remove entries for old/removed AppIDs ─────────────────────────────
    foreach ($id in $RemoveIds) {
        # Match the AppID block and remove its controller_config subsection
        # Pattern: find "<id>" { ... controller_config { ... } ... }
        # We remove only the controller_config sub-block, leaving other keys
        $pattern = "(?s)(`"$id`"\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*?)(`\s*`"controller_config`"\s*\{(?:[^{}]|\{[^{}]*\})*\})"
        $content = $content -replace $pattern, '$1'
    }

    # ── Add/update entries for new AppIDs ─────────────────────────────────
    $configBlock = Build-ControllerConfigBlock -Indent "`t`t`t"

    foreach ($id in $AppIds) {
        $idStr = $id.ToString()

        if ($content -match "`"$idStr`"\s*\{") {
            # AppID block exists — inject controller_config if not already present
            if ($content -notmatch "`"$idStr`"\s*\{[^}]*`"controller_config`"") {
                # Insert controller_config right after the opening brace of this AppID block
                $content = $content -replace "(`"$idStr`"\s*\{)", "`$1`n$configBlock"
            }
            # If already present, leave it — don't overwrite user customizations
        } else {
            # AppID block doesn't exist — append it inside the "apps" section
            # Find the "apps" section and insert before its closing brace
            $appEntry = "`t`t`"$idStr`"`n`t`t{`n$configBlock`t`t}`n"
            $content = $content -replace '("apps"\s*\{)', "`$1`n$appEntry"
        }
    }

    if ($DryRun) {
        Write-Skip "[DRY RUN] Would update localconfig.vdf for $($AppIds.Count) AppIDs."
        return
    }

    # Backup
    Copy-Item $Path ($Path + ".bak") -Force

    Set-Content -Path $Path -Value $content -Encoding UTF8 -NoNewline
    Write-OK "localconfig.vdf updated — $($AppIds.Count) AppID(s) associated with RetroDeck-Win templates."
}

# ─────────────────────────────────────────────────────────────────────────────
#  Read existing shortcuts, split RetroDeck-Win vs user
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Updating shortcuts.vdf"

Write-Step "Reading existing shortcuts.vdf..."
$existingShortcuts = Read-ShortcutsVdf -Path $shortcutsVdf

$userShortcuts = [System.Collections.Generic.List[hashtable]]::new()
$rdwOldIds     = [System.Collections.Generic.List[uint32]]::new()
$rdwCount      = 0

foreach ($sc in $existingShortcuts) {
    if ($sc.Tags -contains "RetroDeck-Win") {
        $rdwCount++
        # Collect old AppIDs for localconfig.vdf cleanup
        $oldId = Get-SteamAppId -AppName $sc.AppName -Exe $sc.Exe
        $rdwOldIds.Add($oldId)
    } else {
        $userShortcuts.Add($sc)
    }
}
Write-Info "Found $($existingShortcuts.Count) existing shortcuts ($rdwCount RetroDeck-Win, $($userShortcuts.Count) user)"

# ─────────────────────────────────────────────────────────────────────────────
#  Remove mode
# ─────────────────────────────────────────────────────────────────────────────
if ($Remove) {
    Write-Step "Remove mode: stripping $rdwCount RetroDeck-Win shortcuts..."
    if ($DryRun) {
        Write-OK "[DRY RUN] Would remove $rdwCount shortcuts and their controller associations."
    } else {
        if (Test-Path $shortcutsVdf) { Copy-Item $shortcutsVdf ($shortcutsVdf+".bak") -Force }
        Write-ShortcutsVdf -Path $shortcutsVdf -Shortcuts $userShortcuts
        Write-OK "Removed $rdwCount RetroDeck-Win shortcuts. $($userShortcuts.Count) user shortcuts kept."
        # Clean up localconfig.vdf
        Update-LocalConfigVdf -Path $localconfigVdf -AppIds @() -RemoveIds $rdwOldIds.ToArray()
        # Clear saved hash so next run does a full sync
        $config | Add-Member -MemberType NoteProperty -Name "gamelist_hash" -Value "" -Force
        $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configFile -Encoding UTF8
    }
    Write-Host ""
    Write-Host "  Restart Steam to apply changes." -ForegroundColor Yellow
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
#  Build new RetroDeck-Win shortcut entries and collect their AppIDs
# ─────────────────────────────────────────────────────────────────────────────
$newRdwShortcuts = [System.Collections.Generic.List[hashtable]]::new()
$newAppIds       = [System.Collections.Generic.List[uint32]]::new()

foreach ($fav in $favorites) {
    $sc = @{
        AppName      = $fav.Name
        Exe          = $fav.Exe
        StartDir     = $fav.StartDir
        Icon         = ""
        LaunchOptions= $fav.Args
        Tags         = @("RetroDeck-Win")
    }
    $newRdwShortcuts.Add($sc)
    $newAppIds.Add((Get-SteamAppId -AppName $fav.Name -Exe $fav.Exe))
}

# Merge: user shortcuts first, then RetroDeck-Win shortcuts
$merged = [System.Collections.Generic.List[hashtable]]::new()
foreach ($sc in $userShortcuts)   { $merged.Add($sc) }
foreach ($sc in $newRdwShortcuts) { $merged.Add($sc) }

Write-Step "Preparing $($newRdwShortcuts.Count) RetroDeck-Win shortcuts..."

if ($DryRun) {
    Write-OK "[DRY RUN] Would write $($merged.Count) total shortcuts to:"
    Write-Info $shortcutsVdf
    Write-Host ""
    Write-Host "  Games that would be added:" -ForegroundColor White
    foreach ($sc in $newRdwShortcuts) {
        Write-Host ("    {0,-40} [{1}]" -f $sc.AppName, $sc.LaunchOptions) -ForegroundColor DarkGray
    }
    exit 0
}

# Backup and write shortcuts.vdf
if (Test-Path $shortcutsVdf) { Copy-Item $shortcutsVdf ($shortcutsVdf+".bak") -Force; Write-Info "Backup: $shortcutsVdf.bak" }
Write-ShortcutsVdf -Path $shortcutsVdf -Shortcuts $merged
Write-OK "shortcuts.vdf written — $($merged.Count) total ($($newRdwShortcuts.Count) from RetroDeck-Win)"

# ─────────────────────────────────────────────────────────────────────────────
#  SteamGridDB artwork download
#
#  Steam stores per-shortcut artwork in:
#    <SteamPath>\userdata\<id>\config\grid\
#
#  File naming convention for non-Steam shortcuts (by AppID):
#    <appid>.png        → Grid / landscape box art  (920×430 recommended)
#    <appid>p.png       → Portrait / poster          (600×900 recommended)
#    <appid>_hero.png   → Hero / banner              (1920×620 recommended)
#    <appid>_logo.png   → Logo (transparent PNG)
#
#  We search SteamGridDB by game name, take the first result for each
#  image type (prefer PNG, highest-rated), and download it.
#  If a file already exists it is not re-downloaded unless -Force is set,
#  so subsequent syncs are fast.
#
#  Requires:
#    retrodeck-win.json field: "steamgriddb_api_key"
#    Obtain a free key at https://www.steamgriddb.com (Avatar → Preferences → API)
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Downloading artwork from SteamGridDB"

$sgdbKey = if ($config.PSObject.Properties["steamgriddb_api_key"]) { $config.steamgriddb_api_key } else { "" }

if ($sgdbKey -eq "" -or $null -eq $sgdbKey) {
    Write-Skip "SteamGridDB API key not configured — skipping artwork download."
    Write-Info "To enable artwork, add your key to retrodeck-win.json:"
    Write-Info "  1. Go to https://www.steamgriddb.com and log in with your Steam account"
    Write-Info "  2. Avatar → Preferences → API → Generate API Key"
    Write-Info "  3. Set `"steamgriddb_api_key`": `"<your key>`" in retrodeck-win.json"
} elseif ($DryRun) {
    Write-Skip "[DRY RUN] Would download artwork for $($newRdwShortcuts.Count) games from SteamGridDB."
} else {
    $gridDir = Join-Path $steamUserFolder "config\grid"
    if (-not (Test-Path $gridDir)) { New-Item -ItemType Directory -Path $gridDir -Force | Out-Null }

    # SteamGridDB API base and headers (Bearer token auth)
    $sgdbBase    = "https://www.steamgriddb.com/api/v2"
    $sgdbHeaders = @{ Authorization = "Bearer $sgdbKey" }

    # Image types: Steam filename suffix → SteamGridDB endpoint + query params
    # Each entry: Suffix, Endpoint (under /game/<id>/), QueryString
    $imageTypes = @(
        @{ Suffix = ""       ; Endpoint = "grids"  ; Query = "dimensions=920x430,460x215&mimes=image/png&limit=1" }
        @{ Suffix = "p"      ; Endpoint = "grids"  ; Query = "dimensions=600x900&mimes=image/png&limit=1" }
        @{ Suffix = "_hero"  ; Endpoint = "heroes" ; Query = "mimes=image/png&limit=1" }
        @{ Suffix = "_logo"  ; Endpoint = "logos"  ; Query = "mimes=image/png&limit=1" }
    )

    $artTotal = 0; $artSkipped = 0; $artFailed = 0

    foreach ($fav in $favorites) {
        # Compute the same AppID that was written to shortcuts.vdf
        # (must match exactly — uses quoted exe path)
        $appIdUint = Get-SteamAppId -AppName $fav.Name -Exe $fav.Exe
        $appIdStr  = $appIdUint.ToString()

        Write-Step "Artwork: $($fav.Name)"

        # ── Step 1: search SteamGridDB for this game name ────────────────────
        $searchUri = "$sgdbBase/search/autocomplete/$([Uri]::EscapeDataString($fav.Name))"
        try {
            $searchResp = Invoke-RestMethod -Uri $searchUri -Headers $sgdbHeaders -Method GET -ErrorAction Stop
        } catch {
            Write-Warn "  Search failed for '$($fav.Name)': $($_.Exception.Message)"
            $artFailed++
            continue
        }

        if (-not $searchResp.success -or $searchResp.data.Count -eq 0) {
            Write-Skip "  Not found on SteamGridDB: $($fav.Name)"
            $artSkipped++
            continue
        }

        # Pick the first (best-match) result
        $sgdbGameId = $searchResp.data[0].id

        # ── Step 2: download each image type ─────────────────────────────────
        foreach ($imgType in $imageTypes) {
            $destFile = Join-Path $gridDir ("$appIdStr$($imgType.Suffix).png")

            # Skip if already present and not forced
            if ((Test-Path $destFile) -and -not $Force) {
                $artSkipped++
                continue
            }

            $imgUri = "$sgdbBase/$($imgType.Endpoint)/game/$sgdbGameId`?$($imgType.Query)"
            try {
                $imgResp = Invoke-RestMethod -Uri $imgUri -Headers $sgdbHeaders -Method GET -ErrorAction Stop
            } catch {
                # Non-fatal: some games simply lack certain image types
                continue
            }

            if (-not $imgResp.success -or $imgResp.data.Count -eq 0) { continue }

            $imageUrl = $imgResp.data[0].url
            try {
                Invoke-WebRequest -Uri $imageUrl -OutFile $destFile -ErrorAction Stop
                $artTotal++
            } catch {
                Write-Warn "  Failed to download $($imgType.Suffix) for '$($fav.Name)': $($_.Exception.Message)"
                $artFailed++
            }
        }
    }

    Write-OK "Artwork: $artTotal downloaded, $artSkipped skipped (already present), $artFailed failed."
    if ($artFailed -gt 0) {
        Write-Info "Failed downloads are non-fatal — games still appear in Steam without art."
        Write-Info "Re-run with -Force to retry all artwork."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Update localconfig.vdf — associate controller templates with each AppID
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Associating Steam Input templates"

# Remove old AppIDs, add new ones
$idsToRemove = $rdwOldIds.ToArray()
$idsToAdd    = $newAppIds.ToArray()

Update-LocalConfigVdf -Path $localconfigVdf -AppIds $idsToAdd -RemoveIds $idsToRemove

# ─────────────────────────────────────────────────────────────────────────────
#  Save gamelist hash to retrodeck-win.json
# ─────────────────────────────────────────────────────────────────────────────
if ($currentHash -ne "") {
    $config | Add-Member -MemberType NoteProperty -Name "gamelist_hash" -Value $currentHash -Force
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configFile -Encoding UTF8
    Write-OK "Gamelist hash saved — future syncs will skip if nothing changes."
}

# ─────────────────────────────────────────────────────────────────────────────
#  Done
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Done"
Write-Host "  $($newRdwShortcuts.Count) games synced to Steam." -ForegroundColor White
Write-Host ""
Write-Host "  ── Controller hotkeys ────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  All synced games have the RetroDeck-Win Steam Input template." -ForegroundColor DarkGray
Write-Host "  Hold Select as modifier:" -ForegroundColor DarkGray
Write-Host "    Select+A=Save  Select+B=Load  Select+Y=Screenshot  Select+X=Reset" -ForegroundColor DarkGray
Write-Host "    Select+Start=Quit  Select+L1=Pause  Select+R1=Fast Forward" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ── Next steps ────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  1. Start Steam (or restart it if it was open)." -ForegroundColor DarkGray
Write-Host "  2. Your favorite games appear in Steam under 'Games'." -ForegroundColor DarkGray
Write-Host "  3. To remove, run: .\Sync-SteamFavorites.ps1 -Remove" -ForegroundColor Cyan
Write-Host "  4. To force a full re-sync (incl. re-download artwork): .\Sync-SteamFavorites.ps1 -Force" -ForegroundColor Cyan
$sgdbKeyCheck = if ($config.PSObject.Properties["steamgriddb_api_key"]) { $config.steamgriddb_api_key } else { "" }
if ($sgdbKeyCheck -eq "" -or $null -eq $sgdbKeyCheck) {
Write-Host ""
Write-Host "  ── Artwork not configured ────────────────────────────────────────" -ForegroundColor Yellow
Write-Host "  Games were added to Steam without box art." -ForegroundColor Yellow
Write-Host "  To enable artwork, add your SteamGridDB API key to retrodeck-win.json:" -ForegroundColor Yellow
Write-Host "    https://www.steamgriddb.com → Avatar → Preferences → API" -ForegroundColor DarkGray
Write-Host "  Then re-run: .\Sync-SteamFavorites.ps1 -Force" -ForegroundColor Cyan
}
Write-Host ""
