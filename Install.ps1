#Requires -Version 5.1
<#
.SYNOPSIS
    RetroDeck-Win Installer

.DESCRIPTION
    Downloads and installs portable emulators into a single installation folder.
    All emulators are extracted from ZIP/7z archives — no traditional installers needed.

    The data folder (ROMs, BIOS, saves, texture packs, etc.) is completely separate
    from the installation folder and can be located anywhere:
      - A local folder (e.g. C:\Users\You\Documents\retrodeck)
      - An external drive (e.g. E:\retrodeck)
      - A NAS mapped as a drive letter (e.g. Z:\retrodeck)

    During installation you will be asked to select the PARENT folder where RetroDeck-Win
    should store your data. A "retrodeck" subfolder will be created (or reused) inside
    your chosen location. This means you can point it to an existing data folder from a
    previous installation and everything will be preserved.

.PARAMETER InstallRoot
    Where the emulator binaries will be installed.
    Default: %LOCALAPPDATA%\RetroDeck-Win
    Override: .\Install.ps1 -InstallRoot "D:\Games\RetroDeck-Win"

.PARAMETER DataRoot
    Full path to the RetroDeck-Win data folder.
    If omitted, a folder picker dialog will open so you can choose the parent folder.
    Override (skip dialog): .\Install.ps1 -DataRoot "Z:\Gaming\retrodeck"

.PARAMETER SkipExisting
    If set, emulators whose executable already exists will be skipped (no re-download).
    Useful for resuming a partially completed installation.

.PARAMETER DryRun
    If set, the script resolves download URLs and prints what it would do, but
    downloads nothing and creates no folders. Useful for testing.

.NOTES
    Must be run as Administrator (required for Program Files and Junction Points).
    PowerShell execution policy: run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
    if you get a "cannot be loaded" error.

    Inspired by the RetroDECK project (https://github.com/retrodeck/retrodeck).
    RetroDECK is a Linux/Steam Deck all-in-one emulation platform. This project
    adapts its library layout and path-mapping philosophy to Windows 11.
#>

param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\RetroDeck-Win",
    [string]$DataRoot    = "",   # Empty = open folder picker dialog
    [switch]$SkipExisting,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
#  Output helpers — consistent visual style throughout the script
# ─────────────────────────────────────────────────────────────────────────────
function Write-Header { param($msg) Write-Host "`n═══ $msg ═══`n" -ForegroundColor Cyan }
function Write-Step   { param($msg) Write-Host "  → $msg" -ForegroundColor White }
function Write-OK     { param($msg) Write-Host "  ✔ $msg" -ForegroundColor Green }
function Write-Skip   { param($msg) Write-Host "  ⊘ $msg" -ForegroundColor DarkGray }
function Write-Warn   { param($msg) Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Fail   { param($msg) Write-Host "  ✘ $msg" -ForegroundColor Red }
function Write-Info   { param($msg) Write-Host "    $msg" -ForegroundColor DarkGray }

# ─────────────────────────────────────────────────────────────────────────────
#  Installation folder structure (under $InstallRoot)
# ─────────────────────────────────────────────────────────────────────────────
$Paths = @{
    Root      = $InstallRoot
    Emulators = Join-Path $InstallRoot "emulators"
    Temp      = Join-Path $env:TEMP    "RetroDeck-Win-Install"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Data folder structure — all subfolders created inside $DataRoot.
#  Layout mirrors the RetroDECK convention so saves, BIOS and ROMs are
#  organised the same way across Linux and Windows installations.
# ─────────────────────────────────────────────────────────────────────────────
$DataPaths = @(
    # ROM folders — one per system, matching ES-DE / RetroDECK system names
    "roms\3ds",       "roms\arcade",     "roms\atari2600",  "roms\atari5200",
    "roms\atari7800", "roms\atarijaguar","roms\atarilynx",  "roms\c64",
    "roms\dreamcast", "roms\ds",         "roms\gamegear",   "roms\gb",
    "roms\gba",       "roms\gbc",        "roms\genesis",    "roms\mastersystem",
    "roms\msx",       "roms\n64",        "roms\nds",        "roms\nes",
    "roms\ngp",       "roms\pce",        "roms\pico8",      "roms\ps2",
    "roms\ps3",       "roms\psp",        "roms\psvita",     "roms\psx",
    "roms\saturn",    "roms\scummvm",    "roms\sega32x",    "roms\segacd",
    "roms\sfc",       "roms\snes",       "roms\switch",     "roms\wii",
    "roms\wiiu",      "roms\xbox",

    # Shared top-level data folders
    "bios", "saves", "states", "screenshots", "mods",
    "texture_packs", "shaders", "borders", "cheats", "themes", "logs",

    # Per-emulator save subfolders (mirrors RetroDECK component_prepare.sh layout)
    "saves\psx\duckstation\memcards",
    "saves\ps2\pcsx2\memcards",
    "saves\ps3\rpcs3",
    "saves\gc\dolphin\EU", "saves\gc\dolphin\US", "saves\gc\dolphin\JP",
    "saves\wii\dolphin",
    "saves\gba",
    "saves\nds",
    "saves\psp\ppsspp",
    "saves\doom",

    # Per-emulator state subfolders
    "states\psx\duckstation",
    "states\ps2\pcsx2",
    "states\ps3\rpcs3",
    "states\dolphin",
    "states\nds",
    "states\psp\ppsspp",
    "states\doom",

    # Per-emulator screenshot subfolders
    "screenshots\retroarch",
    "screenshots\PCSX2",
    "screenshots\Duckstation",
    "screenshots\Dolphin",
    "screenshots\doom",

    # Texture pack subfolders
    "texture_packs\PCSX2\textures",
    "texture_packs\Duckstation\textures",
    "texture_packs\Dolphin\Textures",
    "texture_packs\PPSSPP\TEXTURES",

    # Mod / patch subfolders
    "mods\PCSX2\patches",
    "mods\Dolphin\GraphicMods",

    # Storage (covers, videos, emulator-internal virtual drives, etc.)
    "storage\PCSX2\covers",
    "storage\PCSX2\videos",
    "storage\rpcs3\dev_hdd0",
    "storage\rpcs3\dev_hdd1",
    "storage\rpcs3\dev_flash",
    "storage\rpcs3\dev_flash2",
    "storage\rpcs3\dev_flash3",
    "storage\Dolphin\Dump",
    "storage\cemu\mlc",
    "storage\azahar\nand"
)

# ─────────────────────────────────────────────────────────────────────────────
#  Emulator component definitions
#
#  Each entry describes one emulator. Fields:
#    Name        — display name
#    Description — system(s) emulated
#    Folder      — subfolder under $Paths.Emulators
#    Exe         — main executable filename (used to detect existing installs)
#    ApiUrl      — GitHub Releases API endpoint (omit if using DirectUrl)
#    AssetFilter — wildcard pattern to match the right release asset
#    AssetExclude— wildcard pattern to EXCLUDE from matches (e.g. debug symbols)
#    DirectUrl   — direct download URL when GitHub API is not used
#    FallbackUrl — fallback URL if the primary API call fails
#    SelfExtracting — $true if the archive is a self-extracting EXE (handled by 7-Zip)
#    Note        — printed as a warning during installation
# ─────────────────────────────────────────────────────────────────────────────
$Components = @(

    @{
        Name        = "RetroArch"
        Description = "Multi-system frontend (libretro cores)"
        Folder      = "retroarch"
        # RetroArch distributes via its own buildbot, not GitHub Releases.
        # The stable build URL follows a predictable pattern; update the version number as needed.
        ApiUrl      = $null
        DirectUrl   = "https://buildbot.libretro.com/stable/1.22.0/windows/x86_64/RetroArch.7z"
        Archive     = "RetroArch.7z"
        Exe         = "retroarch.exe"
    }

    @{
        Name        = "PCSX2"
        Description = "Sony PlayStation 2"
        Folder      = "pcsx2"
        ApiUrl      = "https://api.github.com/repos/PCSX2/pcsx2/releases/latest"
        AssetFilter = "*windows-x64-Qt.7z"
        # Exclude the debug symbols package which matches the same pattern
        AssetExclude = "*symbols*"
        Archive     = "pcsx2.7z"
        Exe         = "pcsx2-qt.exe"
    }

    @{
        Name        = "DuckStation"
        Description = "Sony PlayStation 1"
        Folder      = "duckstation"
        # DuckStation uses a rolling "latest" tag instead of numbered releases.
        # The standard releases/latest endpoint returns nothing — use releases/tags/latest instead.
        ApiUrl      = "https://api.github.com/repos/stenzek/duckstation/releases/tags/latest"
        AssetFilter = "duckstation-windows-x64-release.zip"
        Archive     = "duckstation.zip"
        Exe         = "duckstation-qt-x64-ReleaseLTCG.exe"
    }

    @{
        Name        = "Dolphin"
        Description = "Nintendo GameCube & Wii"
        Folder      = "dolphin"
        ApiUrl      = $null
        # Dolphin does not use GitHub Releases. The official download URL follows
        # the pattern: dl.dolphin-emu.org/releases/<version>/dolphin-<version>-x64.7z
        # Update the version number when a new stable release is available:
        # https://dolphin-emu.org/download/
        DirectUrl   = "https://dl.dolphin-emu.org/releases/2603a/dolphin-2603a-x64.7z"
        Archive     = "dolphin.7z"
        Exe         = "Dolphin.exe"
        Note        = "Dolphin version 2603a (March 2026). To update, edit DirectUrl in Install.ps1 — see https://dolphin-emu.org/download/"
    }

    @{
        Name        = "RPCS3"
        Description = "Sony PlayStation 3"
        Folder      = "rpcs3"
        ApiUrl      = $null
        # RPCS3 distributes via rpcs3.net which redirects to the latest 7z build.
        # The GitHub API for rpcs3-binaries-win is unreliable; the official redirect is preferred.
        DirectUrl   = "https://rpcs3.net/latest-windows-x64"
        Archive     = "rpcs3.7z"
        Exe         = "rpcs3.exe"
        Note        = "RPCS3 requires the Microsoft Visual C++ 2019 Redistributable (x64). Download at https://aka.ms/vs/17/release/vc_redist.x64.exe"
    }

    @{
        Name        = "melonDS"
        Description = "Nintendo DS / DSi"
        Folder      = "melonds"
        ApiUrl      = "https://api.github.com/repos/melonDS-emu/melonDS/releases/latest"
        AssetFilter = "melonDS_windows_x64.zip"
        Archive     = "melonds.zip"
        Exe         = "melonDS.exe"
    }

    @{
        Name        = "PPSSPP"
        Description = "Sony PlayStation Portable"
        Folder      = "ppsspp"
        ApiUrl      = "https://api.github.com/repos/hrydgard/ppsspp/releases/latest"
        AssetFilter = "ppsspp_win.zip"
        Archive     = "ppsspp.zip"
        Exe         = "PPSSPPWindows64.exe"
        # PPSSPP's GitHub API has a history of rate-limiting; a versioned fallback is provided.
        FallbackUrl = "https://www.ppsspp.org/files/1_18_1/ppsspp_win.zip"
    }

    @{
        Name        = "Cemu"
        Description = "Nintendo Wii U"
        Folder      = "cemu"
        ApiUrl      = "https://api.github.com/repos/cemu-project/Cemu/releases/latest"
        AssetFilter = "cemu-*-windows-x64.zip"
        Archive     = "cemu.zip"
        Exe         = "Cemu.exe"
    }

    @{
        Name        = "Xemu"
        Description = "Microsoft Xbox (original)"
        Folder      = "xemu"
        ApiUrl      = "https://api.github.com/repos/xemu-project/xemu/releases/latest"
        AssetFilter = "xemu-win-release.zip"
        Archive     = "xemu.zip"
        Exe         = "xemu.exe"
    }

    @{
        Name        = "Vita3K"
        Description = "Sony PlayStation Vita"
        Folder      = "vita3k"
        ApiUrl      = "https://api.github.com/repos/Vita3K/Vita3K/releases/latest"
        AssetFilter = "Windows.zip"
        Archive     = "vita3k.zip"
        Exe         = "Vita3K.exe"
    }

    @{
        Name        = "MAME"
        Description = "Arcade & multi-system"
        Folder      = "mame"
        ApiUrl      = $null
        # MAME's GitHub API is frequently rate-limited due to the large repo size.
        # A direct versioned URL is used instead. Check https://www.mamedev.org/release.php for updates.
        DirectUrl      = "https://github.com/mamedev/mame/releases/download/mame0274/mame0274b_64bit.exe"
        Archive        = "mame.exe"
        Exe            = "mame.exe"
        SelfExtracting = $true
        Note           = "MAME v0.274. The archive is a self-extracting EXE handled by 7-Zip. See https://www.mamedev.org/release.php for the latest version."
    }

    @{
        Name        = "GZDoom"
        Description = "Doom engine / source ports"
        Folder      = "gzdoom"
        ApiUrl      = "https://api.github.com/repos/ZDoom/gzdoom/releases/latest"
        AssetFilter = "gzdoom-*-Windows-64bit.zip"
        Archive     = "gzdoom.zip"
        Exe         = "gzdoom.exe"
    }

    @{
        Name        = "Azahar"
        Description = "Nintendo 3DS (Citra fork)"
        Folder      = "azahar"
        ApiUrl      = "https://api.github.com/repos/azahar-emu/azahar/releases/latest"
        AssetFilter = "azahar-*-windows-msvc.zip"
        Archive     = "azahar.zip"
        Exe         = "azahar.exe"
    }

    @{
        Name        = "Ruffle"
        Description = "Adobe Flash Player (emulated)"
        Folder      = "ruffle"
        ApiUrl      = "https://api.github.com/repos/ruffle-rs/ruffle/releases/latest"
        AssetFilter = "ruffle-*-windows-x86_64.zip"
        Archive     = "ruffle.zip"
        Exe         = "ruffle.exe"
    }

)

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Select-DataFolder
#
#  Opens the native Windows folder picker and asks the user to select the
#  PARENT folder where the RetroDeck-Win data should live.
#
#  A "retrodeck" subfolder will be created (or reused) inside the chosen
#  location. This lets users:
#    - Point to an empty drive/folder for a fresh installation
#    - Point to a folder that already contains a "RetroDeck-Win" directory
#      to resume using an existing library (saves, ROMs, BIOS, etc.)
#
#  If the dialog is unavailable (e.g. Server Core), falls back to Documents.
# ─────────────────────────────────────────────────────────────────────────────
function Select-DataFolder {
    $default = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "RetroDeck-Win"

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = (
            "Select the PARENT folder for your RetroDeck-Win data library.`n" +
            "`n" +
            "A 'retrodeck' subfolder will be created inside your chosen location.`n" +
            "This folder stores all your ROMs, BIOS files, saves, texture packs and more.`n" +
            "`n" +
            "Examples:`n" +
            "  • Select 'Documents'   → data goes to Documents\retrodeck`n" +
            "  • Select 'E:\'         → data goes to E:\retrodeck`n" +
            "  • Select 'Z:\'         → data goes to Z:\retrodeck  (NAS)`n" +
            "`n" +
            "To reuse an existing library, navigate to the folder that already`n" +
            "CONTAINS a 'RetroDeck-Win' folder and select it."
        )
        $dialog.SelectedPath        = ([Environment]::GetFolderPath("MyDocuments"))
        $dialog.ShowNewFolderButton = $true

        $result = $dialog.ShowDialog()

        if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $dialog.SelectedPath) {
            $chosen = $dialog.SelectedPath
            # If the user navigated into the RetroDeck-Win folder itself, use it directly.
            # Otherwise append the subfolder name so it ends up inside the chosen parent.
            if ($chosen -notmatch "(?i)\\RetroDeck-Win$") {
                $chosen = Join-Path $chosen "RetroDeck-Win"
            }
            return $chosen
        }
    }
    catch {
        Write-Warn "Folder picker dialog unavailable ($_). Falling back to Documents."
    }

    return $default
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Write-RetroDeckConfig
#
#  Saves the main configuration file (retrodeck-win.json) to the installation
#  root. This file is read by Configure-Paths.ps1 and any future tooling.
#  Inspired by the retrodeck.json / rd_conf pattern in the original RetroDECK.
# ─────────────────────────────────────────────────────────────────────────────
function Write-RetroDeckConfig {
    param([string]$InstallRoot, [string]$DataRoot, [string]$SteamGridDbApiKey = "")
    $path = Join-Path $InstallRoot "retrodeck-win.json"
    @{
        install_version       = "0.1.0"
        install_date          = (Get-Date -Format "yyyy-MM-dd")
        install_root          = $InstallRoot
        data_root             = $DataRoot
        emulators_root        = (Join-Path $InstallRoot "emulators")
        steamgriddb_api_key   = $SteamGridDbApiKey
    } | ConvertTo-Json -Depth 3 | Set-Content -Path $path -Encoding UTF8
    Write-OK "Configuration saved: $path"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Set-IniValue
#
#  Edits a single key in an INI-style config file.
#  Supports both "Key=Value" and "Key = Value" spacing styles.
#  When $Section is provided, only the matching [Section] block is modified.
#
#  This is the PowerShell equivalent of set_setting_value() in RetroDECK's
#  framework.sh, which performs the same in-place INI/config editing on Linux.
# ─────────────────────────────────────────────────────────────────────────────
function Set-IniValue {
    param(
        [string]$File,
        [string]$Key,
        [string]$Value,
        [string]$Section = ""
    )

    if (-not (Test-Path $File)) {
        Write-Warn "Set-IniValue: file not found: $File"
        return
    }

    $lines     = Get-Content $File -Encoding UTF8
    $inSection = ($Section -eq "")  # No section specified = always "in section"
    $found     = $false

    $result = for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Track which [Section] we are currently inside
        if ($line -match '^\s*\[(.+)\]\s*$') {
            $currentSection = $matches[1]
            $inSection = ($Section -eq "" -or $currentSection -eq $Section)
        }

        if ($inSection -and -not $found) {
            if ($line -match "^\s*$([regex]::Escape($Key))\s*=") {
                # Preserve the original spacing style around the equals sign
                if ($line -match "\s=\s") {
                    $line = "$Key = $Value"
                } else {
                    $line = "$Key=$Value"
                }
                $found = $true
            }
        }
        $line
    }

    if (-not $found) {
        Write-Warn "Set-IniValue: key '$Key' not found in '$File' (section: '$Section') — skipped."
        return
    }

    ($result -join "`n") | Set-Content -Path $File -Encoding UTF8 -NoNewline
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: New-Junction
#
#  Creates a Windows Junction Point from $Link to $Target.
#  Junction Points are the Windows equivalent of Linux directory symlinks.
#  They are used here to redirect emulator-internal hardcoded paths to the
#  user's chosen data folder — mirroring what RetroDECK's dir_prep() does.
#
#  - If $Target does not exist it is created.
#  - If $Link already exists as a junction it is replaced.
#  - If $Link already exists as a real folder a warning is printed and the
#    operation is skipped to avoid accidentally destroying data.
#
#  Requires Administrator privileges.
# ─────────────────────────────────────────────────────────────────────────────
function New-Junction {
    param([string]$Link, [string]$Target)

    # Ensure the target (data folder side) exists
    if (-not (Test-Path $Target)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }

    # Handle existing link path
    if (Test-Path $Link) {
        $item = Get-Item $Link -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # Existing junction — safe to replace
            Remove-Item $Link -Force -Recurse
        } else {
            Write-Warn "New-Junction: '$Link' already exists as a real folder — skipping to protect data."
            return
        }
    }

    # Create parent directory if needed
    $parent = Split-Path $Link -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    New-Item -ItemType Junction -Path $Link -Target $Target | Out-Null
    Write-Info "Junction: $Link"
    Write-Info "       → $Target"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Set-EmulatorPaths
#
#  Applies data folder mappings to every installed emulator.
#  This is the equivalent of running the "postmove" action on all
#  component_prepare.sh scripts in the original RetroDECK framework.
#
#  Strategy (same as RetroDECK):
#    1. For emulators whose config file exposes path settings:
#       → Edit the config file directly with Set-IniValue (or regex for XML/YAML)
#    2. For paths that are hardcoded inside the emulator:
#       → Create a Junction Point redirecting the expected location to $DataRoot
#
#  This function is also called by Configure-Paths.ps1 for re-mapping after
#  the data folder is moved to a new location (e.g. a different NAS).
# ─────────────────────────────────────────────────────────────────────────────
function Set-EmulatorPaths {
    param([string]$EmulatorsRoot, [string]$DataRoot)

    Write-Header "Mapping data folders into emulator configs"

    # Short path aliases — mirror the variable names from RetroDECK's all_vars.sh
    $bios     = Join-Path $DataRoot "bios"
    $roms     = Join-Path $DataRoot "roms"
    $saves    = Join-Path $DataRoot "saves"
    $states   = Join-Path $DataRoot "states"
    $shots    = Join-Path $DataRoot "screenshots"
    $textures = Join-Path $DataRoot "texture_packs"
    $mods     = Join-Path $DataRoot "mods"
    $shaders  = Join-Path $DataRoot "shaders"
    $storage  = Join-Path $DataRoot "storage"
    $logs     = Join-Path $DataRoot "logs"
    $cheats   = Join-Path $DataRoot "cheats"
    $borders  = Join-Path $DataRoot "borders"

    # ── RetroArch ─────────────────────────────────────────────────────────────
    # RetroArch's config exposes all relevant paths — pure INI editing, no junctions needed.
    Write-Step "RetroArch"
    $raConfig = Join-Path $EmulatorsRoot "retroarch\retroarch.cfg"
    if (Test-Path $raConfig) {
        Set-IniValue $raConfig "savefile_directory"         $saves
        Set-IniValue $raConfig "savestate_directory"        $states
        Set-IniValue $raConfig "screenshot_directory"       (Join-Path $shots "retroarch")
        Set-IniValue $raConfig "system_directory"           $bios
        Set-IniValue $raConfig "rgui_browser_directory"     $roms
        Set-IniValue $raConfig "cheat_database_path"        (Join-Path $cheats "retroarch")
        Set-IniValue $raConfig "video_shader_dir"           (Join-Path $shaders "retroarch\shaders")
        Set-IniValue $raConfig "overlay_directory"          (Join-Path $borders "retroarch")
        Set-IniValue $raConfig "log_dir"                    (Join-Path $logs "retroarch")
        Write-OK "RetroArch — paths configured"
    } else {
        Write-Skip "RetroArch — config not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $raConfig"
    }

    # ── PCSX2 ─────────────────────────────────────────────────────────────────
    # PCSX2 stores its config in an "inis" subfolder next to the executable when
    # launched with -portable, or in %AppData%\PCSX2\inis otherwise.
    Write-Step "PCSX2"
    $pcsx2Config = Join-Path $EmulatorsRoot "pcsx2\inis\PCSX2.ini"
    if (-not (Test-Path $pcsx2Config)) {
        $pcsx2Config = Join-Path $env:APPDATA "PCSX2\inis\PCSX2.ini"
    }
    if (Test-Path $pcsx2Config) {
        Set-IniValue $pcsx2Config "Bios"          $bios                                    "Folders"
        Set-IniValue $pcsx2Config "RecursivePaths" (Join-Path $roms "ps2")                 "GameList"
        Set-IniValue $pcsx2Config "Snapshots"     (Join-Path $shots "PCSX2")               "Folders"
        Set-IniValue $pcsx2Config "SaveStates"    (Join-Path $states "ps2\pcsx2")          "Folders"
        Set-IniValue $pcsx2Config "MemoryCards"   (Join-Path $saves "ps2\pcsx2\memcards")  "Folders"
        Set-IniValue $pcsx2Config "Logs"          (Join-Path $logs "PCSX2")                "Folders"
        Set-IniValue $pcsx2Config "Cheats"        (Join-Path $cheats "PCSX2")              "Folders"
        Set-IniValue $pcsx2Config "Textures"      (Join-Path $textures "PCSX2\textures")   "Folders"
        Set-IniValue $pcsx2Config "Videos"        (Join-Path $storage "PCSX2\videos")      "Folders"
        Set-IniValue $pcsx2Config "Covers"        (Join-Path $storage "PCSX2\covers")      "Folders"
        Write-OK "PCSX2 — paths configured"
    } else {
        Write-Skip "PCSX2 — config not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $pcsx2Config"
    }

    # ── DuckStation ───────────────────────────────────────────────────────────
    # DuckStation exposes most paths via settings.ini, but save-states and texture
    # replacements use hardcoded subfolders — those are redirected with junctions.
    Write-Step "DuckStation"
    $dsConfig = Join-Path $EmulatorsRoot "duckstation\settings.ini"
    if (-not (Test-Path $dsConfig)) {
        $dsConfig = Join-Path $env:APPDATA "DuckStation\settings.ini"
    }
    if (Test-Path $dsConfig) {
        Set-IniValue $dsConfig "SearchDirectory" $bios                                                   "BIOS"
        Set-IniValue $dsConfig "RecursivePaths"  (Join-Path $roms "psx")                                 "GameList"
        Set-IniValue $dsConfig "Card1Path"       (Join-Path $saves "psx\duckstation\memcards\shared_card_1.mcd") "MemoryCards"
        Set-IniValue $dsConfig "Card2Path"       (Join-Path $saves "psx\duckstation\memcards\shared_card_2.mcd") "MemoryCards"
        Set-IniValue $dsConfig "Directory"       (Join-Path $saves "psx\duckstation\memcards")           "MemoryCards"
        # Save-states path is hardcoded inside DuckStation — use a junction
        New-Junction -Link   (Join-Path $EmulatorsRoot "duckstation\savestates") `
                     -Target (Join-Path $states "psx\duckstation")
        # Texture replacements folder — also hardcoded
        New-Junction -Link   (Join-Path $EmulatorsRoot "duckstation\textures") `
                     -Target (Join-Path $textures "Duckstation\textures")
        Write-OK "DuckStation — paths configured"
    } else {
        Write-Skip "DuckStation — config not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $dsConfig"
    }

    # ── Dolphin ───────────────────────────────────────────────────────────────
    # Dolphin exposes ROM paths and GBA BIOS via Dolphin.ini.
    # GameCube/Wii save folders, state saves and texture packs are managed
    # through a fixed folder tree in %AppData% (or User\ in portable mode)
    # — those require junctions.
    Write-Step "Dolphin"
    $dolphinConfig = Join-Path $env:APPDATA "Dolphin Emulator\Config\Dolphin.ini"
    $dolphinUserDir = Join-Path $EmulatorsRoot "dolphin\User"
    if (-not (Test-Path $dolphinConfig) -and (Test-Path $dolphinUserDir)) {
        # Portable mode: Dolphin stores data in User\ next to the executable
        $dolphinConfig = Join-Path $dolphinUserDir "Config\Dolphin.ini"
    }
    if (Test-Path $dolphinConfig) {
        Set-IniValue $dolphinConfig "ISOPath0"      (Join-Path $roms "wii")                 "General"
        Set-IniValue $dolphinConfig "ISOPath1"      (Join-Path $roms "gc")                  "General"
        Set-IniValue $dolphinConfig "WiiSDCardPath" (Join-Path $saves "wii\dolphin\sd.raw") "General"
        Set-IniValue $dolphinConfig "BIOS"          (Join-Path $bios "gba_bios.bin")        "GBA"
        Set-IniValue $dolphinConfig "SavesPath"     (Join-Path $saves "gba")                "GBA"

        # Determine which data root Dolphin is actually using
        $dp = if (Test-Path $dolphinUserDir) { $dolphinUserDir } `
              else { Join-Path $env:APPDATA "Dolphin Emulator" }

        New-Junction -Link (Join-Path $dp "GC\EUR")              -Target (Join-Path $saves "gc\dolphin\EU")
        New-Junction -Link (Join-Path $dp "GC\USA")              -Target (Join-Path $saves "gc\dolphin\US")
        New-Junction -Link (Join-Path $dp "GC\JAP")              -Target (Join-Path $saves "gc\dolphin\JP")
        New-Junction -Link (Join-Path $dp "Wii")                 -Target (Join-Path $saves "wii\dolphin")
        New-Junction -Link (Join-Path $dp "StateSaves")          -Target (Join-Path $states "dolphin")
        New-Junction -Link (Join-Path $dp "Load\Textures")       -Target (Join-Path $textures "Dolphin\Textures")
        New-Junction -Link (Join-Path $dp "Load\GraphicMods")    -Target (Join-Path $mods "Dolphin\GraphicMods")
        Write-OK "Dolphin — paths configured"
    } else {
        Write-Skip "Dolphin — config not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $dolphinConfig"
    }

    # ── RPCS3 ─────────────────────────────────────────────────────────────────
    # RPCS3 uses a YAML file (vfs.yml) for virtual filesystem configuration.
    # The $(EmulatorDir) variable and /games/ path are edited with regex.
    # Save data is redirected via a junction into the shared saves folder.
    Write-Step "RPCS3"
    $rpcs3VFS = Join-Path $EmulatorsRoot "rpcs3\config\vfs.yml"
    if (-not (Test-Path $rpcs3VFS)) {
        $rpcs3VFS = Join-Path $env:APPDATA "rpcs3\config\vfs.yml"
    }
    if (Test-Path $rpcs3VFS) {
        $rpcs3Storage = Join-Path $storage "rpcs3"
        $content = Get-Content $rpcs3VFS -Raw -Encoding UTF8
        $content = $content -replace '(?m)^\$\(EmulatorDir\):\s*.*$', "`$(EmulatorDir): $rpcs3Storage/"
        $content = $content -replace '(?m)^/games/:\s*.*$',           "/games/: $(Join-Path $roms 'ps3')/"
        Set-Content -Path $rpcs3VFS -Value $content -Encoding UTF8
        New-Junction -Link (Join-Path $rpcs3Storage "dev_hdd0\home\00000001\savedata") `
                     -Target (Join-Path $saves "ps3\rpcs3")
        New-Junction -Link (Join-Path $EmulatorsRoot "rpcs3\config\savestates") `
                     -Target (Join-Path $states "ps3\rpcs3")
        Write-OK "RPCS3 — paths configured"
    } else {
        Write-Skip "RPCS3 — vfs.yml not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $rpcs3VFS"
        Write-Info "Launch RPCS3 once to generate its config, then re-run Configure-Paths.ps1"
    }

    # ── melonDS ───────────────────────────────────────────────────────────────
    # melonDS exposes BIOS, firmware, save and state paths via its INI config.
    Write-Step "melonDS"
    $melonConfig = Join-Path $EmulatorsRoot "melonds\melonDS.ini"
    if (-not (Test-Path $melonConfig)) {
        $melonConfig = Join-Path $env:APPDATA "melonDS\melonDS.ini"
    }
    if (Test-Path $melonConfig) {
        Set-IniValue $melonConfig "BIOS9Path"     (Join-Path $bios "bios9.bin")
        Set-IniValue $melonConfig "BIOS7Path"     (Join-Path $bios "bios7.bin")
        Set-IniValue $melonConfig "FirmwarePath"  (Join-Path $bios "firmware.bin")
        Set-IniValue $melonConfig "DSiBIOS9Path"  (Join-Path $bios "dsi_bios9.bin")
        Set-IniValue $melonConfig "DSiBIOS7Path"  (Join-Path $bios "dsi_bios7.bin")
        Set-IniValue $melonConfig "SaveFilePath"  (Join-Path $saves "nds")
        Set-IniValue $melonConfig "SaveStatePath" (Join-Path $states "nds")
        Write-OK "melonDS — paths configured"
    } else {
        Write-Skip "melonDS — config not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $melonConfig"
    }

    # ── PPSSPP ────────────────────────────────────────────────────────────────
    # PPSSPP uses a "memstick" folder tree next to the executable.
    # All user data (saves, states, textures) lives in fixed subfolders of
    # memstick\PSP\ — redirected with junctions.
    Write-Step "PPSSPP"
    $ppssppMemstick = Join-Path $EmulatorsRoot "ppsspp\memstick\PSP"
    if (Test-Path $ppssppMemstick) {
        New-Junction -Link (Join-Path $ppssppMemstick "SAVEDATA")    -Target (Join-Path $saves "psp\ppsspp")
        New-Junction -Link (Join-Path $ppssppMemstick "PPSSPP_STATE")-Target (Join-Path $states "psp\ppsspp")
        New-Junction -Link (Join-Path $ppssppMemstick "TEXTURES")    -Target (Join-Path $textures "PPSSPP\TEXTURES")
        Write-OK "PPSSPP — paths configured"
    } else {
        Write-Skip "PPSSPP — memstick folder not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $ppssppMemstick"
        Write-Info "Launch PPSSPP once to generate its memstick tree, then re-run Configure-Paths.ps1"
    }

    # ── Cemu ──────────────────────────────────────────────────────────────────
    # Cemu uses an XML settings file. Game paths and the MLC (system/save data)
    # location are patched with regex since Cemu does not ship an XML library
    # that is easily accessible from PowerShell without additional dependencies.
    Write-Step "Cemu"
    $cemuConfig = Join-Path $EmulatorsRoot "cemu\settings.xml"
    if (Test-Path $cemuConfig) {
        $content = Get-Content $cemuConfig -Raw -Encoding UTF8
        $content = $content -replace '(?s)(<GamePaths>).*?(</GamePaths>)',
                                      "<GamePaths><Entry>$(Join-Path $roms 'wiiu')</Entry></GamePaths>"
        $content = $content -replace '(?s)(<mlc_path>).*?(</mlc_path>)',
                                      "<mlc_path>$(Join-Path $storage 'cemu\mlc')</mlc_path>"
        Set-Content -Path $cemuConfig -Value $content -Encoding UTF8
        Write-OK "Cemu — paths configured"
    } else {
        Write-Skip "Cemu — settings.xml not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $cemuConfig"
    }

    # ── GZDoom ────────────────────────────────────────────────────────────────
    # GZDoom creates its INI in %AppData%\GZDoom or next to the executable.
    Write-Step "GZDoom"
    $gzdoomConfig = Join-Path $EmulatorsRoot "gzdoom\gzdoom.ini"
    if (-not (Test-Path $gzdoomConfig)) {
        $gzdoomConfig = Join-Path $env:APPDATA "GZDoom\gzdoom.ini"
    }
    if (Test-Path $gzdoomConfig) {
        Set-IniValue $gzdoomConfig "SaveDir"        (Join-Path $saves "doom")  "GlobalSettings"
        Set-IniValue $gzdoomConfig "AutoSave"       (Join-Path $states "doom") "GlobalSettings"
        Set-IniValue $gzdoomConfig "Screenshot_Dir" (Join-Path $shots "doom")  "GlobalSettings"
        Write-OK "GZDoom — paths configured"
    } else {
        Write-Skip "GZDoom — config not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $gzdoomConfig"
    }

    # ── Azahar (3DS) ──────────────────────────────────────────────────────────
    # Azahar (Citra fork) stores its config in %AppData%\Azahar\config or
    # in a config\ subfolder next to the executable in portable mode.
    Write-Step "Azahar"
    $azaharConfig = Join-Path $env:APPDATA "Azahar\config\qt-config.ini"
    if (-not (Test-Path $azaharConfig)) {
        $azaharConfig = Join-Path $EmulatorsRoot "azahar\config\qt-config.ini"
    }
    if (Test-Path $azaharConfig) {
        Set-IniValue $azaharConfig "game_dir_deprecated" (Join-Path $roms "3ds")            "UI"
        Set-IniValue $azaharConfig "sdmc_dir"            (Join-Path $saves "3ds")           "Data Storage"
        Set-IniValue $azaharConfig "nand_dir"            (Join-Path $storage "azahar\nand") "Data Storage"
        Write-OK "Azahar — paths configured"
    } else {
        Write-Skip "Azahar — config not found, will be mapped on next run of Configure-Paths.ps1"
        Write-Info "Expected: $azaharConfig"
    }

    Write-Host ""
    Write-Warn "Emulators marked as 'config not found' need to be launched once to generate"
    Write-Warn "their config files. Then run Configure-Paths.ps1 to complete the mapping."
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Set-EmulatorHotkeys
#
#  Pre-configures keyboard hotkeys in every emulator so that the RetroDeck-Win
#  Steam Input layout works from the very first launch.
#
#  The Steam Input templates map controller combos (Select + button) to
#  keyboard shortcuts. The emulators must be configured to respond to those
#  same keyboard shortcuts:
#
#    Key      → Action (common across emulators)
#    ─────────────────────────────────────────────
#    F1       → Save State
#    F3       → Load State
#    F5       → Reset
#    F8       → Screenshot
#    Escape   → Quit / Exit
#    P        → Pause / Resume
#    Tab      → Fast Forward (hold)
#    R        → Rewind (hold)
#    F2       → Save Slot + 1
#    Shift+F2 → Save Slot - 1
#
#  Each emulator has its own config format. Where a key is already bound to
#  a different function, only the RetroDeck-Win hotkeys are written — existing
#  gameplay bindings are left untouched.
#
#  This function is safe to re-run: it only modifies the specific keys listed
#  above, and silently skips any config file that doesn't exist yet (those
#  emulators need to be launched once first).
# ─────────────────────────────────────────────────────────────────────────────
function Set-EmulatorHotkeys {
    param([string]$EmulatorsRoot)

    Write-Header "Configuring emulator hotkeys"

    # ── RetroArch ─────────────────────────────────────────────────────────────
    # RetroArch uses retroarch.cfg — hotkeys are plain INI key=value.
    # All keys use the form: input_<action> = "key_name"
    # Full key name list: https://docs.libretro.com/guides/input-and-controls/
    Write-Step "RetroArch"
    $raConfig = Join-Path $EmulatorsRoot "retroarch\retroarch.cfg"
    if (Test-Path $raConfig) {
        Set-IniValue $raConfig "input_save_state"       "`"f1`""
        Set-IniValue $raConfig "input_load_state"       "`"f3`""
        Set-IniValue $raConfig "input_reset"            "`"f5`""
        Set-IniValue $raConfig "input_screenshot"       "`"f8`""
        Set-IniValue $raConfig "input_exit_emulator"    "`"escape`""
        Set-IniValue $raConfig "input_pause_toggle"     "`"p`""
        Set-IniValue $raConfig "input_hold_fast_forward"`"`"tab`""
        Set-IniValue $raConfig "input_rewind"           "`"r`""
        Set-IniValue $raConfig "input_state_slot_increase" "`"f2`""
        Set-IniValue $raConfig "input_state_slot_decrease" "`"nul`""  # Shift+F2 not single-key; slot- is less critical
        # Enable rewind buffer (disabled by default; required for 'R' to work)
        Set-IniValue $raConfig "rewind_enable"          "`"true`""
        Write-OK "RetroArch — hotkeys configured"
    } else {
        Write-Skip "RetroArch — config not found, hotkeys will be set on next Configure-Paths.ps1 run"
    }

    # ── PCSX2 ─────────────────────────────────────────────────────────────────
    # PCSX2 stores hotkeys in PCSX2.ini under [Hotkeys] section.
    # Key names are Qt key names (e.g. "F1", "Escape", "P").
    Write-Step "PCSX2"
    $pcsx2Config = Join-Path $EmulatorsRoot "pcsx2\inis\PCSX2.ini"
    if (-not (Test-Path $pcsx2Config)) { $pcsx2Config = Join-Path $env:APPDATA "PCSX2\inis\PCSX2.ini" }
    if (Test-Path $pcsx2Config) {
        Set-IniValue $pcsx2Config "SaveState"         "F1"         "Hotkeys"
        Set-IniValue $pcsx2Config "LoadStateFromSlot" "F3"         "Hotkeys"
        Set-IniValue $pcsx2Config "Reset"             "F5"         "Hotkeys"
        Set-IniValue $pcsx2Config "Screenshot"        "F8"         "Hotkeys"
        Set-IniValue $pcsx2Config "TogglePause"       "P"          "Hotkeys"
        Set-IniValue $pcsx2Config "HoldTurbo"         "Tab"        "Hotkeys"
        Write-OK "PCSX2 — hotkeys configured"
    } else {
        Write-Skip "PCSX2 — config not found, hotkeys will be set on next Configure-Paths.ps1 run"
    }

    # ── DuckStation ───────────────────────────────────────────────────────────
    # DuckStation uses settings.ini with a [Hotkeys] section.
    # Key names follow Qt conventions.
    Write-Step "DuckStation"
    $dsConfig = Join-Path $EmulatorsRoot "duckstation\settings.ini"
    if (-not (Test-Path $dsConfig)) { $dsConfig = Join-Path $env:APPDATA "DuckStation\settings.ini" }
    if (Test-Path $dsConfig) {
        Set-IniValue $dsConfig "SaveSelectedSaveState" "F1"      "Hotkeys"
        Set-IniValue $dsConfig "LoadSelectedSaveState" "F3"      "Hotkeys"
        Set-IniValue $dsConfig "Reset"                 "F5"      "Hotkeys"
        Set-IniValue $dsConfig "Screenshot"            "F8"      "Hotkeys"
        Set-IniValue $dsConfig "Quit"                  "Escape"  "Hotkeys"
        Set-IniValue $dsConfig "TogglePause"           "P"       "Hotkeys"
        Set-IniValue $dsConfig "HoldTurboSpeed"        "Tab"     "Hotkeys"
        Set-IniValue $dsConfig "Rewind"                "R"       "Hotkeys"
        Set-IniValue $dsConfig "SelectNextSaveStateSlot" "F2"    "Hotkeys"
        Write-OK "DuckStation — hotkeys configured"
    } else {
        Write-Skip "DuckStation — config not found, hotkeys will be set on next Configure-Paths.ps1 run"
    }

    # ── Dolphin ───────────────────────────────────────────────────────────────
    # Dolphin stores hotkeys in HotkeyConfig.ini.
    # Key codes are Dolphin-specific integer values, but the [Hotkeys] section
    # can also accept named keys via "Device = Keyboard/0/..." entries.
    # We use the GCPad/Hotkey ini format: KEY_F1, KEY_F3, etc.
    # Note: Dolphin does not support save states for Wii out of the box.
    Write-Step "Dolphin"
    $dolphinHotkeyIni = Join-Path $env:APPDATA "Dolphin Emulator\Config\HotkeyConfig.ini"
    if (-not (Test-Path $dolphinHotkeyIni)) {
        $dolphinHotkeyIni = Join-Path $EmulatorsRoot "dolphin\User\Config\HotkeyConfig.ini"
    }
    if (Test-Path $dolphinHotkeyIni) {
        Set-IniValue $dolphinHotkeyIni "Save_State"       "`$4&Keyboard/0/F1`$"          "Hotkeys"
        Set-IniValue $dolphinHotkeyIni "Load_State"       "`$4&Keyboard/0/F3`$"          "Hotkeys"
        Set-IniValue $dolphinHotkeyIni "Reset"            "`$4&Keyboard/0/F5`$"          "Hotkeys"
        Set-IniValue $dolphinHotkeyIni "Take_Screenshot"  "`$4&Keyboard/0/F8`$"          "Hotkeys"
        Set-IniValue $dolphinHotkeyIni "Stop"             "`$4&Keyboard/0/ESCAPE`$"      "Hotkeys"
        Set-IniValue $dolphinHotkeyIni "Toggle_Pause"     "`$4&Keyboard/0/P`$"           "Hotkeys"
        Set-IniValue $dolphinHotkeyIni "Frame_Advance"    "`$4&Keyboard/0/TAB`$"         "Hotkeys"
        Write-OK "Dolphin — hotkeys configured"
    } else {
        Write-Skip "Dolphin — HotkeyConfig.ini not found, hotkeys will be set on next Configure-Paths.ps1 run"
    }

    # ── melonDS ───────────────────────────────────────────────────────────────
    # melonDS stores key bindings in melonDS.ini.
    # Save/load state use function keys; pause and quit use named binds.
    # Key values are Qt key codes (integers): F1=16777264, F3=16777266,
    # F5=16777268, F8=16777271, Escape=16777216, P=80, Tab=16777217, R=82.
    Write-Step "melonDS"
    $melonConfig = Join-Path $EmulatorsRoot "melonds\melonDS.ini"
    if (-not (Test-Path $melonConfig)) { $melonConfig = Join-Path $env:APPDATA "melonDS\melonDS.ini" }
    if (Test-Path $melonConfig) {
        Set-IniValue $melonConfig "HotkeyStateSave"     "16777264"  # F1
        Set-IniValue $melonConfig "HotkeyStateLoad"     "16777266"  # F3
        Set-IniValue $melonConfig "HotkeyReset"         "16777268"  # F5
        Set-IniValue $melonConfig "HotkeyScreenshot"    "16777271"  # F8
        Set-IniValue $melonConfig "HotkeyQuit"          "16777216"  # Escape
        Set-IniValue $melonConfig "HotkeyPause"         "80"        # P
        Set-IniValue $melonConfig "HotkeyFrameLimitToggle" "16777217"  # Tab (fast-forward)
        Write-OK "melonDS — hotkeys configured"
    } else {
        Write-Skip "melonDS — config not found, hotkeys will be set on next Configure-Paths.ps1 run"
    }

    # ── PPSSPP ────────────────────────────────────────────────────────────────
    # PPSSPP stores hotkeys in controls.ini under [ControlMapping] section.
    # Keyboard key codes are the Windows VK_ codes as decimal integers.
    # F1=112, F3=114, F5=116, F8=119, Escape=27, P=80, Tab=9, R=82.
    # Each action can have multiple bindings: "Key <code> 0" (keyboard device 0).
    Write-Step "PPSSPP"
    $ppssppControls = Join-Path $EmulatorsRoot "ppsspp\memstick\PSP\SYSTEM\controls.ini"
    if (Test-Path $ppssppControls) {
        Set-IniValue $ppssppControls "Save State"       "Key 112 0"    "ControlMapping"
        Set-IniValue $ppssppControls "Load State"       "Key 114 0"    "ControlMapping"
        Set-IniValue $ppssppControls "Reset"            "Key 116 0"    "ControlMapping"
        Set-IniValue $ppssppControls "Screenshot"       "Key 119 0"    "ControlMapping"
        Set-IniValue $ppssppControls "Pause"            "Key 80 0"     "ControlMapping"
        Set-IniValue $ppssppControls "Fast-forward"     "Key 9 0"      "ControlMapping"
        Set-IniValue $ppssppControls "Rewind"           "Key 82 0"     "ControlMapping"
        Write-OK "PPSSPP — hotkeys configured"
    } else {
        Write-Skip "PPSSPP — controls.ini not found (launch PPSSPP once first), will be set on next Configure-Paths.ps1 run"
    }

    # ── Azahar (3DS) ──────────────────────────────────────────────────────────
    # Azahar uses qt-config.ini; hotkeys live in [Shortcuts] section.
    # Key values are Qt key names (human-readable strings).
    Write-Step "Azahar"
    $azaharConfig = Join-Path $env:APPDATA "Azahar\config\qt-config.ini"
    if (-not (Test-Path $azaharConfig)) { $azaharConfig = Join-Path $EmulatorsRoot "azahar\config\qt-config.ini" }
    if (Test-Path $azaharConfig) {
        Set-IniValue $azaharConfig "main/hotkeys/Save State/KeySeq"       "F1"      "Shortcuts"
        Set-IniValue $azaharConfig "main/hotkeys/Load State/KeySeq"       "F3"      "Shortcuts"
        Set-IniValue $azaharConfig "main/hotkeys/Restart Emulation/KeySeq" "F5"     "Shortcuts"
        Set-IniValue $azaharConfig "main/hotkeys/Screenshot/KeySeq"       "F8"      "Shortcuts"
        Set-IniValue $azaharConfig "main/hotkeys/Stop Emulation/KeySeq"   "Escape"  "Shortcuts"
        Set-IniValue $azaharConfig "main/hotkeys/Toggle Pause/KeySeq"     "P"       "Shortcuts"
        Write-OK "Azahar — hotkeys configured"
    } else {
        Write-Skip "Azahar — config not found, hotkeys will be set on next Configure-Paths.ps1 run"
    }

    # ── GZDoom ────────────────────────────────────────────────────────────────
    # GZDoom uses gzdoom.ini with [Bindings] and [DoubleBindings] sections.
    # GZDoom already uses F1/F3/F5/F8 for menu, save, load and screenshot by default
    # in many builds. We verify/enforce our layout.
    Write-Step "GZDoom"
    $gzdoomConfig = Join-Path $EmulatorsRoot "gzdoom\gzdoom.ini"
    if (-not (Test-Path $gzdoomConfig)) { $gzdoomConfig = Join-Path $env:APPDATA "GZDoom\gzdoom.ini" }
    if (Test-Path $gzdoomConfig) {
        Set-IniValue $gzdoomConfig "F1"       "pause"       "Bindings"
        Set-IniValue $gzdoomConfig "F3"       "quickload"   "Bindings"
        Set-IniValue $gzdoomConfig "F5"       "+restart"    "Bindings"
        Set-IniValue $gzdoomConfig "F8"       "screenshot"  "Bindings"
        Set-IniValue $gzdoomConfig "Escape"   "menu_main"   "Bindings"
        Set-IniValue $gzdoomConfig "Tab"      "+speed"      "Bindings"  # fast-forward / sprint modifier
        Write-OK "GZDoom — hotkeys configured"
    } else {
        Write-Skip "GZDoom — config not found, hotkeys will be set on next Configure-Paths.ps1 run"
    }

    # ── Cemu (Wii U) ──────────────────────────────────────────────────────────
    # Cemu stores input configuration in controllerProfiles\. Hotkeys are in
    # settings.xml under <HotKeys>. Each action is a virtual key code (decimal).
    # F1=112, F3=114, F5=116, F8=119, Escape=27, P=80, Tab=9.
    # Note: Cemu save states (Shift+F1..F4) are different from our layout;
    # we map only screenshot and pause here to avoid conflicts.
    Write-Step "Cemu"
    $cemuConfig = Join-Path $EmulatorsRoot "cemu\settings.xml"
    if (Test-Path $cemuConfig) {
        $content = Get-Content $cemuConfig -Raw -Encoding UTF8
        # Cemu uses XML for hotkeys; patch or inject the <HotKeys> section
        # Only inject if <HotKeys> already exists in the file
        if ($content -match '<HotKeys>') {
            $content = $content -replace '(<screenshot>)\d*(</screenshot>)', '${1}119${2}'   # F8
            $content = $content -replace '(<pause>)\d*(</pause>)',           '${1}80${2}'    # P
            Set-Content -Path $cemuConfig -Value $content -Encoding UTF8
            Write-OK "Cemu — hotkeys configured (screenshot=F8, pause=P)"
        } else {
            Write-Skip "Cemu — <HotKeys> section not found in settings.xml; launch Cemu once first"
        }
    } else {
        Write-Skip "Cemu — settings.xml not found, hotkeys will be set on next Configure-Paths.ps1 run"
    }

    Write-Host ""
    Write-Warn "Emulators marked as 'config not found' above need to be launched once"
    Write-Warn "to generate their config files. Then run Configure-Paths.ps1 to apply hotkeys."
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: New-Shortcut
#
#  Creates a Windows .lnk shortcut file using WScript.Shell.
#  Handles both direct executables and PowerShell script launchers.
# ─────────────────────────────────────────────────────────────────────────────
function New-Shortcut {
    param(
        [string]$LnkPath,       # Full path to the .lnk file to create
        [string]$TargetPath,    # Executable to launch (e.g. powershell.exe or retroarch.exe)
        [string]$Arguments = "",# Arguments passed to TargetPath
        [string]$WorkDir   = "",# Working directory
        [string]$IconPath  = "",# Path to .exe or .ico for the icon
        [string]$Description= ""# Tooltip shown in Start Menu
    )
    $shell  = New-Object -ComObject WScript.Shell
    $lnk    = $shell.CreateShortcut($LnkPath)
    $lnk.TargetPath       = $TargetPath
    $lnk.Arguments        = $Arguments
    $lnk.WorkingDirectory = if ($WorkDir -ne "") { $WorkDir } else { Split-Path $TargetPath -Parent }
    if ($IconPath  -ne "") { $lnk.IconLocation = $IconPath }
    if ($Description -ne "") { $lnk.Description = $Description }
    $lnk.Save()
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Set-StartMenuShortcuts
#
#  Creates the following Start Menu structure:
#
#    RetroDeck-Win\
#      RetroDeck-Win.lnk              ← Launch-RetroDeckWin.ps1 (main entry point)
#      Emulators\
#        RetroArch.lnk
#        PCSX2.lnk
#        ... (one per installed emulator)
#      Scripts\
#        Sync Steam Favorites.lnk     ← Sync-SteamFavorites.ps1
#        Configure Paths.lnk          ← Configure-Paths.ps1
#        Check BIOS.lnk               ← Check-Bios.ps1
#        Uninstall.lnk                ← Sync-SteamFavorites.ps1 -Remove
#
#  All .ps1 launchers run hidden (no console window) via:
#    powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "..."
#
#  The Emulators sub-group only creates entries for emulators whose .exe
#  actually exists — skipped components don't appear in the menu.
# ─────────────────────────────────────────────────────────────────────────────
function Set-StartMenuShortcuts {
    param([string]$InstallRoot, [string]$EmulatorsRoot)

    Write-Header "Creating Start Menu shortcuts"

    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    # Root group folder
    $smRoot = Join-Path ([Environment]::GetFolderPath("CommonPrograms")) "RetroDeck-Win"
    $smEmu  = Join-Path $smRoot "Emulators"
    $smScr  = Join-Path $smRoot "Scripts"

    foreach ($dir in @($smRoot, $smEmu, $smScr)) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    # ── Main launcher (top-level, most prominent) ─────────────────────────────
    $launchScript = Join-Path $InstallRoot "Launch-RetroDeckWin.ps1"
    $esDExe       = Join-Path $EmulatorsRoot "ES-DE\ES-DE.exe"
    New-Shortcut `
        -LnkPath     (Join-Path $smRoot "RetroDeck-Win.lnk") `
        -TargetPath  $ps `
        -Arguments   "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launchScript`"" `
        -WorkDir     $InstallRoot `
        -IconPath    (if (Test-Path $esDExe) { "$esDExe,0" } else { "$ps,0" }) `
        -Description "Launch RetroDeck-Win (ES-DE + Steam sync)"
    Write-OK "RetroDeck-Win.lnk"

    # ── Emulators sub-group ───────────────────────────────────────────────────
    # One shortcut per component, only if the exe was actually installed.
    foreach ($comp in $script:Components) {
        $exePath = Join-Path $EmulatorsRoot "$($comp.Folder)\$($comp.Exe)"
        if (-not (Test-Path $exePath)) { continue }

        $lnkName = "$($comp.Name).lnk"
        New-Shortcut `
            -LnkPath    (Join-Path $smEmu $lnkName) `
            -TargetPath $exePath `
            -WorkDir    (Split-Path $exePath -Parent) `
            -IconPath   "$exePath,0" `
            -Description $comp.Description
        Write-OK "Emulators\$lnkName"
    }

    # ── Scripts sub-group ─────────────────────────────────────────────────────
    $scripts = @(
        @{
            Name   = "Sync Steam Favorites"
            Script = "Sync-SteamFavorites.ps1"
            Args   = ""
            Desc   = "Sync ES-DE favorites to Steam shortcuts"
        }
        @{
            Name   = "Sync Steam Favorites (Force)"
            Script = "Sync-SteamFavorites.ps1"
            Args   = "-Force"
            Desc   = "Force a full re-sync even if nothing changed"
        }
        @{
            Name   = "Configure Paths"
            Script = "Configure-Paths.ps1"
            Args   = ""
            Desc   = "Remap emulator configs to a new data library location"
        }
        @{
            Name   = "Check BIOS Files"
            Script = "Check-Bios.ps1"
            Args   = "-ShowAll"
            Desc   = "Validate BIOS files by MD5/SHA1 hash"
        }
        @{
            Name   = "Remove from Steam"
            Script = "Sync-SteamFavorites.ps1"
            Args   = "-Remove"
            Desc   = "Remove all RetroDeck-Win shortcuts from Steam"
        }
    )

    foreach ($s in $scripts) {
        $scriptPath = Join-Path $InstallRoot $s.Script
        $argsStr = "-ExecutionPolicy Bypass -File `"$scriptPath`""
        if ($s.Args -ne "") { $argsStr += " $($s.Args)" }
        New-Shortcut `
            -LnkPath    (Join-Path $smScr "$($s.Name).lnk") `
            -TargetPath $ps `
            -Arguments  $argsStr `
            -WorkDir    $InstallRoot `
            -Description $s.Desc
        Write-OK "Scripts\$($s.Name).lnk"
    }

    Write-Host ""
    Write-Info "Start Menu → RetroDeck-Win"
    Write-Info "  RetroDeck-Win.lnk  (main launcher)"
    Write-Info "  Emulators\          (individual emulator shortcuts)"
    Write-Info "  Scripts\            (sync, configure, check BIOS, remove)"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Set-EsdeConfig
#
#  Configures ES-DE's es_settings.xml to point its ROM path at <DataRoot>\roms.
#  ES-DE must have been launched at least once to generate es_settings.xml.
#  If the file doesn't exist yet, a minimal one is created.
#
#  Also sets the media folder (scraped images/videos) to <DataRoot>\media
#  so artwork stays inside the data library alongside ROMs and saves.
# ─────────────────────────────────────────────────────────────────────────────
function Set-EsdeConfig {
    param([string]$EmulatorsRoot, [string]$DataRoot)

    Write-Header "Configuring ES-DE"

    # ES-DE in portable mode stores its config in ES-DE\resources\ next to the exe.
    # In non-portable mode it uses %AppData%\ES-DE\.
    # We check both and use whichever exists; if neither, we create the AppData one.
    $esdePortableConfig = Join-Path $EmulatorsRoot "ES-DE\resources\es_settings.xml"
    $esdeAppDataConfig  = Join-Path $env:APPDATA "ES-DE\es_settings.xml"
    $esdeConfigDir      = ""
    $esdeConfigPath     = ""

    if (Test-Path $esdePortableConfig) {
        $esdeConfigPath = $esdePortableConfig
        $esdeConfigDir  = Split-Path $esdePortableConfig -Parent
        Write-Info "ES-DE config (portable): $esdeConfigPath"
    } elseif (Test-Path $esdeAppDataConfig) {
        $esdeConfigPath = $esdeAppDataConfig
        $esdeConfigDir  = Split-Path $esdeAppDataConfig -Parent
        Write-Info "ES-DE config (AppData): $esdeConfigPath"
    } else {
        # ES-DE not yet launched — create a minimal es_settings.xml in AppData
        $esdeConfigDir = Join-Path $env:APPDATA "ES-DE"
        if (-not (Test-Path $esdeConfigDir)) { New-Item -ItemType Directory -Path $esdeConfigDir -Force | Out-Null }
        $esdeConfigPath = $esdeAppDataConfig
        Write-Info "ES-DE config not found — creating minimal config at: $esdeConfigPath"

        # Minimal es_settings.xml that tells ES-DE where ROMs and media live
        @"
<?xml version="1.0"?>
<settings>
    <string name="ROMDirectory" value="$($DataRoot -replace '\\','/')/roms" />
    <string name="MediaDirectory" value="$($DataRoot -replace '\\','/')/media" />
    <bool name="ScrapeMetadata" value="true" />
</settings>
"@ | Set-Content -Path $esdeConfigPath -Encoding UTF8
        Write-OK "ES-DE — minimal config created"
        return
    }

    # Parse and patch the existing XML
    [xml]$xml = Get-Content $esdeConfigPath -Raw -Encoding UTF8

    # Helper: set or add a <string name="Key" value="..." /> entry
    function Set-EsdeXmlString {
        param([xml]$Doc, [string]$Key, [string]$Value)
        $node = $Doc.settings.ChildNodes | Where-Object { $_.name -eq $Key } | Select-Object -First 1
        if ($node) {
            $node.value = $Value
        } else {
            $el = $Doc.CreateElement("string")
            $el.SetAttribute("name",  $Key)
            $el.SetAttribute("value", $Value)
            $Doc.settings.AppendChild($el) | Out-Null
        }
    }

    # Forward slashes — ES-DE uses UNIX-style paths even on Windows
    $romsPath  = ($DataRoot -replace '\\','/') + "/roms"
    $mediaPath = ($DataRoot -replace '\\','/') + "/media"

    Set-EsdeXmlString -Doc $xml -Key "ROMDirectory"   -Value $romsPath
    Set-EsdeXmlString -Doc $xml -Key "MediaDirectory" -Value $mediaPath

    $xml.Save($esdeConfigPath)
    Write-OK "ES-DE — ROMDirectory  → $romsPath"
    Write-OK "ES-DE — MediaDirectory → $mediaPath"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Add-EsdeSteamShortcut
#
#  Adds the RetroDeck-Win launcher (Launch-RetroDeckWin.ps1) as a non-Steam
#  shortcut so it gets the Steam overlay, Steam Input templates, and appears
#  in the Steam library under "Games".
#
#  This is the equivalent of the Linux "Add RetroDECK to Steam" step.
#  Without this, the Steam Input controller templates never load when ES-DE
#  is open, so the Select+button hotkeys don't work.
#
#  The shortcut is written to shortcuts.vdf (same file Sync-SteamFavorites.ps1
#  manages). It gets the "RetroDeck-Win" tag so Sync can track it, and the
#  controller_config block is injected into localconfig.vdf so all 9 controller
#  types load the hotkey template automatically.
#
#  Steam must be closed while this runs, or it will overwrite shortcuts.vdf.
# ─────────────────────────────────────────────────────────────────────────────
function Add-EsdeSteamShortcut {
    param(
        [string]$InstallRoot,
        [string]$SteamPath
    )

    Write-Header "Adding RetroDeck-Win to Steam"

    # ── Locate Steam ──────────────────────────────────────────────────────────
    if ($SteamPath -eq "" -or -not (Test-Path $SteamPath)) {
        $regPaths = @("HKCU:\Software\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam","HKLM:\SOFTWARE\WOW6432Node\Valve\Steam")
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
        Write-Warn "Steam not found — skipping Steam shortcut creation."
        Write-Info "Run Sync-SteamFavorites.ps1 after installing Steam to add the launcher."
        return
    }
    Write-Info "Steam: $SteamPath"

    # ── Find Steam user ───────────────────────────────────────────────────────
    $userdataRoot = Join-Path $SteamPath "userdata"
    if (-not (Test-Path $userdataRoot)) {
        Write-Warn "Steam userdata not found — log in to Steam at least once, then re-run Install.ps1."
        return
    }
    $userFolders = Get-ChildItem -Path $userdataRoot -Directory | Where-Object { $_.Name -match '^\d+$' }
    if ($userFolders.Count -eq 0) { Write-Warn "No Steam user accounts found."; return }

    # Use first account (same logic as Sync-SteamFavorites.ps1 in single-account case)
    $steamUserFolder = $userFolders[0].FullName
    Write-Info "Steam user: $($userFolders[0].Name)"

    $shortcutsVdf   = Join-Path $steamUserFolder "config\shortcuts.vdf"
    $localconfigVdf = Join-Path $steamUserFolder "config\localconfig.vdf"
    $gridDir        = Join-Path $steamUserFolder "config\grid"
    if (-not (Test-Path $gridDir)) { New-Item -ItemType Directory -Path $gridDir -Force | Out-Null }

    # ── Shortcut definition ───────────────────────────────────────────────────
    $ps            = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $launchScript  = Join-Path $InstallRoot "Launch-RetroDeckWin.ps1"
    $scName        = "RetroDeck-Win"
    $scExe         = "`"$ps`""
    $scArgs        = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launchScript`""
    $scStartDir    = $InstallRoot

    # ── CRC32 / AppID helpers (duplicated here so function is self-contained) ─
    function _Get-Crc32 { param([byte[]]$B)
        $t=[uint32[]]::new(256); for($i=0;$i-lt256;$i++){[uint32]$c=$i;for($j=0;$j-lt8;$j++){if($c-band1){$c=0xEDB88320-bxor($c-shr1)}else{$c=$c-shr1}};$t[$i]=$c}
        [uint32]$r=0xFFFFFFFF; foreach($b in $B){$r=($r-shr8)-bxor$t[($r-bxor$b)-band0xFF]}; return $r-bxor0xFFFFFFFF }
    function _Get-AppId { param([string]$N,[string]$E)
        $bytes=[System.Text.Encoding]::GetEncoding(1252).GetBytes($N+$E+"`0")
        return [uint32]((_Get-Crc32 $bytes)-bor0x80000000) }

    $appId    = _Get-AppId -N $scName -E $scExe
    $appIdInt = [int][uint32]$appId

    # ── Read existing shortcuts.vdf ───────────────────────────────────────────
    # We call Sync-SteamFavorites.ps1 helper logic indirectly by sourcing the
    # binary format — but to keep Install.ps1 self-contained, we write the
    # shortcuts.vdf entry with inline byte helpers here.

    function _Write-StrF { param($W,$K,$V)
        $W.Write([byte]0x01); $W.Write([System.Text.Encoding]::ASCII.GetBytes($K)); $W.Write([byte]0x00)
        $W.Write([System.Text.Encoding]::UTF8.GetBytes($V)); $W.Write([byte]0x00) }
    function _Write-IntF { param($W,$K,$V)
        $W.Write([byte]0x02); $W.Write([System.Text.Encoding]::ASCII.GetBytes($K)); $W.Write([byte]0x00); $W.Write([int32]$V) }

    # Read existing shortcuts to preserve user entries and avoid duplicates
    $existingBytes = if (Test-Path $shortcutsVdf) { [System.IO.File]::ReadAllBytes($shortcutsVdf) } else { @() }

    # Parse existing shortcuts into raw list of byte blobs so we can re-emit them.
    # Strategy: re-read the file, skip any existing "RetroDeck-Win" entry, keep the rest.
    $keepBlobs = [System.Collections.Generic.List[byte[]]]::new()
    if ($existingBytes.Count -gt 0) {
        $ms0 = [System.IO.MemoryStream]::new($existingBytes)
        $r0  = [System.IO.BinaryReader]::new($ms0, [System.Text.Encoding]::UTF8)
        try {
            # Skip root header: type(1) + "shortcuts"(9) + null(1)
            if ($r0.ReadByte() -eq 0) {
                $rk = ""
                while ($true) { $b = $r0.ReadByte(); if ($b -eq 0) { break }; $rk += [char]$b }
            }
            # Read each shortcut entry as a raw blob
            while ($ms0.Position -lt $ms0.Length - 2) {
                $startPos = $ms0.Position
                $entryType = $r0.ReadByte()
                if ($entryType -eq 0x08) { break }  # end of shortcuts dict

                # Read the index key (e.g. "0", "1", ...)
                $idxKey = ""
                while ($true) { $b = $r0.ReadByte(); if ($b -eq 0) { break }; $idxKey += [char]$b }

                # Read all fields of this shortcut entry
                $entryName = ""
                $isRdw = $false
                $fieldBytes = [System.Collections.Generic.List[byte]]::new()
                $fieldBytes.Add($entryType)
                foreach ($kb in [System.Text.Encoding]::ASCII.GetBytes($idxKey)) { $fieldBytes.Add($kb) }
                $fieldBytes.Add(0)

                while ($true) {
                    $fType = $r0.ReadByte()
                    $fieldBytes.Add($fType)
                    if ($fType -eq 0x08) { break }
                    $fKey = ""
                    while ($true) { $b = $r0.ReadByte(); $fieldBytes.Add($b); if ($b -eq 0) { break }; $fKey += [char]$b }
                    switch ($fType) {
                        0x00 {  # sub-dict (tags or other)
                            while ($true) {
                                $tb = $r0.ReadByte(); $fieldBytes.Add($tb)
                                if ($tb -eq 0x08) { break }
                                while ($true) { $b2=$r0.ReadByte(); $fieldBytes.Add($b2); if ($b2-eq0){break} }
                                while ($true) { $b2=$r0.ReadByte(); $fieldBytes.Add($b2); if ($b2-eq0){break} }
                            }
                        }
                        0x01 {  # string
                            $sv = ""
                            while ($true) { $b=$r0.ReadByte(); $fieldBytes.Add($b); if ($b-eq0){break}; $sv += [char]$b }
                            if ($fKey -eq "AppName" -and $sv -eq "RetroDeck-Win") { $isRdw = $true }
                        }
                        0x02 { foreach ($b in $r0.ReadBytes(4)) { $fieldBytes.Add($b) } }  # int32
                    }
                }
                if (-not $isRdw) { $keepBlobs.Add($fieldBytes.ToArray()) }
            }
        } finally { $r0.Close(); $ms0.Close() }
    }

    # ── Write new shortcuts.vdf ───────────────────────────────────────────────
    if (Test-Path $shortcutsVdf) { Copy-Item $shortcutsVdf ($shortcutsVdf+".bak") -Force }

    $ms  = [System.IO.MemoryStream]::new()
    $w   = [System.IO.BinaryWriter]::new($ms, [System.Text.Encoding]::UTF8)

    # Root header
    $w.Write([byte]0x00); $w.Write([System.Text.Encoding]::ASCII.GetBytes("shortcuts")); $w.Write([byte]0x00)

    # Re-emit kept blobs with sequential index keys
    $idx = 0
    foreach ($blob in $keepBlobs) {
        # Replace the original index key with sequential $idx
        $w.Write([byte]0x00)
        $w.Write([System.Text.Encoding]::ASCII.GetBytes($idx.ToString()))
        $w.Write([byte]0x00)
        # Skip the first byte (type=0x00) and the original key+null in the blob
        $keyEnd = 1
        while ($keyEnd -lt $blob.Length -and $blob[$keyEnd] -ne 0) { $keyEnd++ }
        $keyEnd++  # skip null terminator
        $w.Write($blob[$keyEnd..($blob.Length-1)])
        $idx++
    }

    # Append the new RetroDeck-Win launcher entry
    $w.Write([byte]0x00); $w.Write([System.Text.Encoding]::ASCII.GetBytes($idx.ToString())); $w.Write([byte]0x00)
    _Write-IntF  $w "appid"               $appIdInt
    _Write-StrF  $w "AppName"             $scName
    _Write-StrF  $w "Exe"                 $scExe
    _Write-StrF  $w "StartDir"            $scStartDir
    _Write-StrF  $w "icon"                ""
    _Write-StrF  $w "ShortcutPath"        ""
    _Write-StrF  $w "LaunchOptions"       $scArgs
    $w.Write([byte]0x02); $w.Write([System.Text.Encoding]::ASCII.GetBytes("IsHidden")); $w.Write([byte]0x00); $w.Write([int32]0)
    $w.Write([byte]0x02); $w.Write([System.Text.Encoding]::ASCII.GetBytes("AllowDesktopConfig")); $w.Write([byte]0x00); $w.Write([int32]1)
    $w.Write([byte]0x02); $w.Write([System.Text.Encoding]::ASCII.GetBytes("AllowOverlay")); $w.Write([byte]0x00); $w.Write([int32]1)
    $w.Write([byte]0x02); $w.Write([System.Text.Encoding]::ASCII.GetBytes("OpenVR")); $w.Write([byte]0x00); $w.Write([int32]0)
    $w.Write([byte]0x02); $w.Write([System.Text.Encoding]::ASCII.GetBytes("Devkit")); $w.Write([byte]0x00); $w.Write([int32]0)
    _Write-StrF  $w "DevkitGameID"        ""
    $w.Write([byte]0x02); $w.Write([System.Text.Encoding]::ASCII.GetBytes("DevkitOverrideAppID")); $w.Write([byte]0x00); $w.Write([int32]0)
    $w.Write([byte]0x02); $w.Write([System.Text.Encoding]::ASCII.GetBytes("LastPlayTime")); $w.Write([byte]0x00); $w.Write([int32]0)
    _Write-StrF  $w "FlatpakAppID"        ""
    _Write-StrF  $w "sortas"             ""
    # tags dict with "RetroDeck-Win" tag
    $w.Write([byte]0x00); $w.Write([System.Text.Encoding]::ASCII.GetBytes("tags")); $w.Write([byte]0x00)
    $w.Write([byte]0x01); $w.Write([System.Text.Encoding]::ASCII.GetBytes("0")); $w.Write([byte]0x00)
    $w.Write([System.Text.Encoding]::UTF8.GetBytes("RetroDeck-Win")); $w.Write([byte]0x00)
    $w.Write([byte]0x08)  # end tags
    $w.Write([byte]0x08)  # end shortcut entry

    # End of shortcuts dict + root dict
    $w.Write([byte]0x08); $w.Write([byte]0x08)
    $w.Flush()
    [System.IO.File]::WriteAllBytes($shortcutsVdf, $ms.ToArray())
    $w.Close()

    Write-OK "shortcuts.vdf — RetroDeck-Win launcher added (AppID: $appId)"

    # ── Inject controller_config into localconfig.vdf ─────────────────────────
    # Map of controller types → template filenames (same as Sync-SteamFavorites.ps1)
    $ctrlMap = @{
        "controller_xbox360"                = "RetroDeck-Win_controller_xbox_hotkeys.vdf"
        "controller_xboxone"                = "RetroDeck-Win_controller_xboxone_hotkeys.vdf"
        "controller_ps3"                    = "RetroDeck-Win_controller_ps3_hotkeys.vdf"
        "controller_ps4"                    = "RetroDeck-Win_controller_ps4_hotkeys.vdf"
        "controller_ps5"                    = "RetroDeck-Win_controller_ps5_hotkeys.vdf"
        "controller_ps5_edge"               = "RetroDeck-Win_controller_ps5edge_hotkeys.vdf"
        "controller_switch_pro"             = "RetroDeck-Win_controller_switch_pro_hotkeys.vdf"
        "controller_steamcontroller_gordon" = "RetroDeck-Win_controller_gordon_hotkeys.vdf"
        "controller_generic"                = "RetroDeck-Win_controller_generic_hotkeys.vdf"
    }

    if (Test-Path $localconfigVdf) {
        $lc = Get-Content $localconfigVdf -Raw -Encoding UTF8
        $idStr = $appId.ToString()

        # Build controller_config block
        $block = "`t`t`t`"controller_config`"`n`t`t`t{`n"
        foreach ($kvp in $ctrlMap.GetEnumerator()) {
            $block += "`t`t`t`t`"$($kvp.Key)`"`n`t`t`t`t{`n"
            $block += "`t`t`t`t`t`"DEFAULT_FOR_TYPE`"`t`t`"1`"`n"
            $block += "`t`t`t`t`t`"template`"`t`t`"$($kvp.Value)`"`n"
            $block += "`t`t`t`t}`n"
        }
        $block += "`t`t`t}`n"

        # Inject if not already present
        if ($lc -notmatch "`"$idStr`"") {
            $entry = "`t`t`"$idStr`"`n`t`t{`n$block`t`t}`n"
            $lc = $lc -replace '("apps"\s*\{)', "`$1`n$entry"
            Copy-Item $localconfigVdf ($localconfigVdf+".bak") -Force
            Set-Content -Path $localconfigVdf -Value $lc -Encoding UTF8 -NoNewline
            Write-OK "localconfig.vdf — controller templates associated with RetroDeck-Win AppID"
        } else {
            Write-Skip "localconfig.vdf — AppID $idStr already present"
        }
    } else {
        Write-Warn "localconfig.vdf not found — controller templates not associated."
        Write-Info "Launch Steam once and run Sync-SteamFavorites.ps1 to complete this step."
    }

    # ── Install Steam Input templates ─────────────────────────────────────────
    $templateSrc = Join-Path $InstallRoot "steam-input"
    $templateDst = Join-Path $SteamPath "controller_base\templates"
    if ((Test-Path $templateSrc) -and (Test-Path $templateDst)) {
        Get-ChildItem -Path $templateSrc -Filter "RetroDeck-Win_*.vdf" | ForEach-Object {
            Copy-Item $_.FullName (Join-Path $templateDst $_.Name) -Force
        }
        Write-OK "Steam Input templates installed"
    }

    Write-Host ""
    Write-Warn "Restart Steam for the new shortcut to appear in your library."
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Resolve-DownloadUrl
#
#  Queries a GitHub Releases API endpoint and returns the browser_download_url
#  of the first asset matching $AssetFilter (minus any $AssetExclude matches).
#  Returns $null on failure so the caller can decide whether to abort or fallback.
# ─────────────────────────────────────────────────────────────────────────────
function Resolve-DownloadUrl {
    param($ApiUrl, $AssetFilter, $AssetExclude = $null)

    try {
        $headers = @{ "User-Agent" = "RetroDeck-Win-Installer" }
        $release = Invoke-RestMethod -Uri $ApiUrl -Headers $headers
        $assets  = $release.assets | Where-Object { $_.name -like $AssetFilter }

        # Exclude unwanted assets (e.g. debug symbol packages)
        if ($AssetExclude) {
            $assets = $assets | Where-Object { $_.name -notlike $AssetExclude }
        }

        $asset = $assets | Select-Object -First 1

        if ($null -eq $asset) {
            Write-Warn "No asset matching '$AssetFilter' was found. Available assets:"
            $release.assets | ForEach-Object { Write-Info $_.name }
            return $null
        }
        return $asset.browser_download_url
    }
    catch {
        Write-Warn "GitHub API request failed: $_"
        return $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Invoke-Download
#
#  Downloads a file to $Dest with a live progress indicator.
#  Uses WebClient async so progress events fire without blocking the thread.
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Download {
    param($Url, $Dest)

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "RetroDeck-Win-Installer")

    $lastPercent = -1
    $wc.DownloadProgressChanged += {
        $p = $Event.SourceArgs[1].ProgressPercentage
        if ($p -ne $lastPercent -and $p % 5 -eq 0) {
            Write-Host "`r      Downloading... $p%" -NoNewline -ForegroundColor DarkCyan
            $script:lastPercent = $p
        }
    }

    $done = $false
    $wc.DownloadFileCompleted += { $script:done = $true }
    $wc.DownloadFileAsync([Uri]$Url, $Dest)

    while (-not $done) { Start-Sleep -Milliseconds 200 }
    Write-Host "`r      Download complete.    " -ForegroundColor DarkCyan
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Expand-Archive-Smart
#
#  Extracts a ZIP or 7z archive to $Destination.
#  Prefers 7z.exe (handles both formats and self-extracting EXEs).
#  Falls back to PowerShell's built-in Expand-Archive for ZIP only.
# ─────────────────────────────────────────────────────────────────────────────
function Expand-Archive-Smart {
    param($Archive, $Destination)

    $ext = [System.IO.Path]::GetExtension($Archive).ToLower()

    # Locate 7-Zip — check PATH first, then common installation directories
    $7z = Get-Command "7z.exe" -ErrorAction SilentlyContinue
    if ($7z) {
        $7z = $7z.Source
    } else {
        foreach ($candidate in @("C:\Program Files\7-Zip\7z.exe", "C:\Program Files (x86)\7-Zip\7z.exe")) {
            if (Test-Path $candidate) { $7z = $candidate; break }
        }
    }

    if ($7z) {
        Write-Info "Extracting with 7-Zip..."
        & $7z x $Archive -o"$Destination" -y -bso0 -bsp0 | Out-Null
    } elseif ($ext -eq ".zip") {
        Write-Info "7-Zip not found — using PowerShell built-in (ZIP only)..."
        Expand-Archive -Path $Archive -DestinationPath $Destination -Force
    } else {
        throw "7-Zip is required to extract '$Archive' but was not found.`nInstall it from https://www.7-zip.org/ and re-run the installer."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Install-Component
#
#  Handles the full lifecycle for one emulator:
#    1. Skip if already installed (when -SkipExisting is set)
#    2. Resolve the download URL (API or direct)
#    3. Download the archive
#    4. Extract to the emulator subfolder
#    5. Flatten any nested subfolder the archive may have created
#    6. Verify the expected executable exists
# ─────────────────────────────────────────────────────────────────────────────
function Install-Component {
    param($Component)

    $destFolder = Join-Path $Paths.Emulators $Component.Folder
    $exePath    = Join-Path $destFolder $Component.Exe

    Write-Step "[$($Component.Name)]  $($Component.Description)"

    # Skip if already installed
    if ($SkipExisting -and (Test-Path $exePath)) {
        Write-Skip "$($Component.Name) already installed — skipping (use without -SkipExisting to reinstall)"
        return
    }

    # Print any special notice for this component
    if ($Component.Note) { Write-Warn $Component.Note }

    # ── Resolve download URL ──────────────────────────────────
    $url = $null

    if ($Component.ApiUrl) {
        Write-Info "Querying GitHub Releases API for latest version..."
        $exclude = if ($Component.AssetExclude) { $Component.AssetExclude } else { $null }
        $url = Resolve-DownloadUrl -ApiUrl $Component.ApiUrl `
                                   -AssetFilter $Component.AssetFilter `
                                   -AssetExclude $exclude

        if (-not $url -and $Component.FallbackUrl) {
            Write-Warn "API returned no result — falling back to hardcoded URL."
            $url = $Component.FallbackUrl
        }

        if (-not $url) {
            Write-Fail "$($Component.Name): could not resolve a download URL — skipping."
            return
        }
    } elseif ($Component.DirectUrl) {
        $url = $Component.DirectUrl
        Write-Info "Using direct URL (no API lookup needed)."
    } else {
        Write-Fail "$($Component.Name): no URL configured — skipping."
        return
    }

    Write-Info "URL: $url"

    if ($DryRun) {
        Write-OK "[DRY RUN] $($Component.Name) would be downloaded from: $url"
        return
    }

    # ── Download ──────────────────────────────────────────────
    $archivePath = Join-Path $Paths.Temp $Component.Archive
    try {
        Invoke-Download -Url $url -Dest $archivePath
    } catch {
        Write-Fail "$($Component.Name): download failed — $_"
        return
    }

    # ── Create destination folder ─────────────────────────────
    if (-not (Test-Path $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
    }

    # ── Extract archive ───────────────────────────────────────
    Write-Info "Extracting to: $destFolder"
    try {
        Expand-Archive-Smart -Archive $archivePath -Destination $destFolder
    } catch {
        Write-Fail "$($Component.Name): extraction failed — $_"
        return
    }

    # Clean up the downloaded archive
    Remove-Item $archivePath -Force -ErrorAction SilentlyContinue

    # ── Flatten nested subfolders ─────────────────────────────
    # Some archives extract into a versioned subfolder (e.g. "dolphin-2603a\").
    # Move everything up to $destFolder so paths remain consistent.
    $exeFinal = Get-ChildItem -Path $destFolder -Filter $Component.Exe -Recurse | Select-Object -First 1
    if ($exeFinal) {
        if ($exeFinal.DirectoryName -ne $destFolder) {
            Write-Info "Moving files from subfolder to root (archive created a nested directory)..."
            Get-ChildItem -Path $exeFinal.DirectoryName | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $destFolder -Force
            }
            Remove-Item -Path $exeFinal.DirectoryName -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-OK "$($Component.Name) installed → $destFolder\$($Component.Exe)"
    } else {
        Write-Warn "$($Component.Name): executable '$($Component.Exe)' not found after extraction."
        Write-Warn "Check the folder manually: $destFolder"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Initialize-DataFolders
#
#  Creates the full data folder tree inside $DataRoot.
#  Existing folders are left untouched — safe to run on top of a prior install.
# ─────────────────────────────────────────────────────────────────────────────
function Initialize-DataFolders {
    param([string]$DataRoot)

    Write-Header "Creating data folder structure"
    Write-Step "Data root: $DataRoot"

    $created  = 0
    $existing = 0
    foreach ($rel in $DataPaths) {
        $full = Join-Path $DataRoot $rel
        if (-not (Test-Path $full)) {
            New-Item -ItemType Directory -Path $full -Force | Out-Null
            $created++
        } else {
            $existing++
        }
    }

    Write-OK "$created folders created, $existing already existed — data root is ready."
}

# ─────────────────────────────────────────────────────────────────────────────
#  Function: Write-EmulatorRegistry
#
#  Writes emulators.json to the installation root listing every component
#  along with its install status. Used by launchers and future tooling.
# ─────────────────────────────────────────────────────────────────────────────
function Write-EmulatorRegistry {
    param([string]$EmulatorsRoot)

    $regPath  = Join-Path $Paths.Root "emulators.json"
    $registry = $Components | ForEach-Object {
        $exePath = Join-Path (Join-Path $EmulatorsRoot $_.Folder) $_.Exe
        [PSCustomObject]@{
            name        = $_.Name
            description = $_.Description
            folder      = $_.Folder
            exe         = $_.Exe
            fullPath    = $exePath
            installed   = (Test-Path $exePath)
        }
    }
    $registry | ConvertTo-Json -Depth 3 | Set-Content -Path $regPath -Encoding UTF8
    Write-OK "Emulator registry saved: $regPath"
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────────────────
Write-Host @"

  ____      _         ____  _____ ____ _  __  __        ___
 |  _ \ ___| |_ _ __ |  _ \| ____/ ___| |/ / \ \      / (_)_ __
 | |_) / _ \ __| '__| | | | |  _|| |   | ' /   \ \ /\ / /| | '_ \
 |  _ <  __/ |_| |  | |_| | |___| |___| . \    \ V  V / | | | | |
 |_| \_\___|\__|_|  |____/|_____\____|_|\_\    \_/\_/  |_|_|_| |_|

 Windows Emulation Suite — Installer v0.1.0
 ─────────────────────────────────────────────────────────────────
 Inspired by the RetroDECK project (https://github.com/retrodeck/retrodeck)

"@ -ForegroundColor Cyan

# ── Administrator check ───────────────────────────────────────────────────────
# Both installing to Program Files and creating Junction Points require elevation.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
               [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Fail "This script must be run as Administrator."
    Write-Host ""
    Write-Host "  Two things require elevation:" -ForegroundColor Yellow
    Write-Host "    1. Writing to '$InstallRoot' (AppData\Local)" -ForegroundColor Yellow
    Write-Host "    2. Creating Junction Points for emulator data redirection" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Right-click PowerShell → 'Run as Administrator', then re-run the script." -ForegroundColor Yellow
    Write-Host "  To install elsewhere use: .\Install.ps1 -InstallRoot `"D:\Games\RetroDeck-Win`"" -ForegroundColor DarkGray
    exit 1
}

# ── Data folder selection ─────────────────────────────────────────────────────
if ($DataRoot -eq "") {
    Write-Host ""
    Write-Host "  ┌─ WHERE SHOULD YOUR DATA LIBRARY LIVE? ─────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  │                                                                  │" -ForegroundColor Cyan
    Write-Host "  │  RetroDeck-Win separates emulator binaries from your data.      │" -ForegroundColor Cyan
    Write-Host "  │  Your ROMs, BIOS files, saves, texture packs and more will all  │" -ForegroundColor Cyan
    Write-Host "  │  live in a 'RetroDeck-Win' folder at a location you choose.     │" -ForegroundColor Cyan
    Write-Host "  │                                                                  │" -ForegroundColor Cyan
    Write-Host "  │  A folder picker will open. SELECT THE PARENT FOLDER:           │" -ForegroundColor Cyan
    Write-Host "  │                                                                  │" -ForegroundColor Cyan
    Write-Host "  │  • Fresh install on local drive → select Documents or any       │" -ForegroundColor Cyan
    Write-Host "  │    folder; 'RetroDeck-Win' will be created inside it.           │" -ForegroundColor Cyan
    Write-Host "  │                                                                  │" -ForegroundColor Cyan
    Write-Host "  │  • NAS / external drive → map your NAS as a drive letter        │" -ForegroundColor Cyan
    Write-Host "  │    (e.g. Z:\) and select that drive root.                       │" -ForegroundColor Cyan
    Write-Host "  │                                                                  │" -ForegroundColor Cyan
    Write-Host "  │  • Existing library → navigate to the folder that already       │" -ForegroundColor Cyan
    Write-Host "  │    CONTAINS your 'RetroDeck-Win' data folder and select it.     │" -ForegroundColor Cyan
    Write-Host "  │    Your ROMs, saves and BIOS will be preserved.                 │" -ForegroundColor Cyan
    Write-Host "  │                                                                  │" -ForegroundColor Cyan
    Write-Host "  └──────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Press Enter to open the folder picker..." -ForegroundColor DarkGray
    $null = Read-Host
    $DataRoot = Select-DataFolder
    Write-Host ""
    Write-OK "Data folder selected: $DataRoot"
}

# ── Installation summary ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ── Installation Plan ────────────────────────────────────────────" -ForegroundColor White
Write-Host "  Emulator binaries  : $($Paths.Root)" -ForegroundColor White
Write-Host "  Data library       : $DataRoot" -ForegroundColor White
Write-Host "  Number of emulators: $($Components.Count)" -ForegroundColor White
Write-Host ""
Write-Host "  What this installer will do:" -ForegroundColor DarkGray
Write-Host "    1. Download $($Components.Count) portable emulators (no system-wide installation)" -ForegroundColor DarkGray
Write-Host "    2. Extract each emulator to $($Paths.Emulators)" -ForegroundColor DarkGray
Write-Host "    3. Create the data folder tree at $DataRoot" -ForegroundColor DarkGray
Write-Host "    4. Edit each emulator's config to point to $DataRoot" -ForegroundColor DarkGray
Write-Host "    5. Pre-configure keyboard hotkeys (F1/F3/F5/F8/Esc/P/Tab/R) in each emulator" -ForegroundColor DarkGray
Write-Host "    6. Configure ES-DE to find ROMs in $DataRoot\roms" -ForegroundColor DarkGray
Write-Host "    7. Create Junction Points where emulators use hardcoded paths" -ForegroundColor DarkGray
Write-Host "    8. Create Start Menu shortcuts (RetroDeck-Win \ Emulators + Scripts)" -ForegroundColor DarkGray
Write-Host "    9. Add RetroDeck-Win as a non-Steam shortcut (overlay + Steam Input)" -ForegroundColor DarkGray
Write-Host "   10. Save retrodeck-win.json with the installation configuration" -ForegroundColor DarkGray
Write-Host ""
if ($DryRun)       { Write-Host "  [DRY RUN MODE — nothing will be downloaded or created]" -ForegroundColor Yellow }
if ($SkipExisting) { Write-Host "  [SKIP EXISTING — already-installed emulators will be skipped]" -ForegroundColor DarkGray }
Write-Host ""

# ── SteamGridDB API key ───────────────────────────────────────────────────────
# SteamGridDB provides artwork (box art, heroes, logos) for games added to Steam.
# An API key is required for every user — it is tied to a personal Steam account
# and cannot be bundled with the software (that would violate SteamGridDB's ToS).
#
# How to get your key (free):
#   1. Go to https://www.steamgriddb.com  and log in with your Steam account
#   2. Click your avatar → Preferences → API → Generate API Key
#   3. Paste it here
#
# The key is stored in retrodeck-win.json and used by Sync-SteamFavorites.ps1.
# Artwork sync is optional — shortcuts work perfectly without it; games just
# appear in Steam without box art until you provide a key.
Write-Host ""
Write-Host "  ┌─ STEAMGRIDDB ARTWORK (OPTIONAL) ───────────────────────────────┐" -ForegroundColor Cyan
Write-Host "  │                                                                  │" -ForegroundColor Cyan
Write-Host "  │  RetroDeck-Win can download box art, hero images, and logos     │" -ForegroundColor Cyan
Write-Host "  │  from SteamGridDB when it syncs your favorites to Steam.        │" -ForegroundColor Cyan
Write-Host "  │                                                                  │" -ForegroundColor Cyan
Write-Host "  │  To enable artwork:                                              │" -ForegroundColor Cyan
Write-Host "  │    1. Go to https://www.steamgriddb.com                         │" -ForegroundColor Cyan
Write-Host "  │    2. Log in with your Steam account                            │" -ForegroundColor Cyan
Write-Host "  │    3. Avatar → Preferences → API → Generate API Key            │" -ForegroundColor Cyan
Write-Host "  │    4. Paste your key below                                      │" -ForegroundColor Cyan
Write-Host "  │                                                                  │" -ForegroundColor Cyan
Write-Host "  │  Leave blank to skip — you can add the key later in             │" -ForegroundColor Cyan
Write-Host "  │  retrodeck-win.json (field: steamgriddb_api_key)                │" -ForegroundColor Cyan
Write-Host "  └──────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""
$SteamGridDbApiKey = (Read-Host "  SteamGridDB API Key (press Enter to skip)").Trim()
if ($SteamGridDbApiKey -ne "") {
    Write-OK "API key saved."
} else {
    Write-Skip "No API key — artwork sync disabled. Add it later to retrodeck-win.json if desired."
}
Write-Host ""

$confirm = Read-Host "  Proceed with installation? (Y/N)"
if ($confirm -notmatch "^[yY]") { Write-Host "  Cancelled." -ForegroundColor Yellow; exit 0 }

# ── Create installation folders ───────────────────────────────────────────────
Write-Header "Preparing installation folders"
foreach ($key in $Paths.Keys) {
    $p = $Paths[$key]
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Write-OK "Created: $p"
    } else {
        Write-Skip "Already exists: $p"
    }
}

# ── Download and extract emulators ───────────────────────────────────────────
Write-Header "Installing emulators ($($Components.Count) components)"
$successCount = 0
$failCount    = 0

foreach ($component in $Components) {
    Write-Host ""
    try {
        Install-Component -Component $component
        $successCount++
    } catch {
        Write-Fail "Unexpected error installing $($component.Name): $_"
        $failCount++
    }
}

# ── Set up data folder and emulator configs ───────────────────────────────────
if (-not $DryRun) {
    Initialize-DataFolders  -DataRoot $DataRoot
    Write-RetroDeckConfig   -InstallRoot $Paths.Root -DataRoot $DataRoot -SteamGridDbApiKey $SteamGridDbApiKey
    Write-EmulatorRegistry  -EmulatorsRoot $Paths.Emulators
    Set-EmulatorPaths       -EmulatorsRoot $Paths.Emulators -DataRoot $DataRoot
    Set-EmulatorHotkeys     -EmulatorsRoot $Paths.Emulators
    Set-EsdeConfig          -EmulatorsRoot $Paths.Emulators -DataRoot $DataRoot
    Set-StartMenuShortcuts  -InstallRoot $Paths.Root -EmulatorsRoot $Paths.Emulators
    Add-EsdeSteamShortcut   -InstallRoot $Paths.Root -SteamPath $SteamPath
}

# ── Final summary ─────────────────────────────────────────────────────────────
Write-Header "Installation complete"
Write-Host "  ✔ Successfully installed : $successCount emulators" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  ✘ Failed                 : $failCount emulators" -ForegroundColor Red
}
Write-Host ""
Write-Host "  Emulator binaries : $($Paths.Emulators)" -ForegroundColor White
Write-Host "  Data library      : $DataRoot" -ForegroundColor White
Write-Host "  Configuration     : $(Join-Path $Paths.Root 'retrodeck-win.json')" -ForegroundColor White
Write-Host ""
Write-Host "  ── How to start playing ─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  1. Restart Steam so 'RetroDeck-Win' appears in your library." -ForegroundColor DarkGray
Write-Host "  2. Copy ROMs to  : $DataRoot\roms\<system>" -ForegroundColor DarkGray
Write-Host "  3. Copy BIOS to  : $DataRoot\bios\" -ForegroundColor DarkGray
Write-Host "  4. Launch RetroDeck-Win from:" -ForegroundColor DarkGray
Write-Host "       • Steam library  (recommended — enables controller hotkeys)" -ForegroundColor DarkGray
Write-Host "       • Start Menu → RetroDeck-Win → RetroDeck-Win" -ForegroundColor DarkGray
Write-Host "  5. In ES-DE, mark games as favorites (north button / Y / Triangle)." -ForegroundColor DarkGray
Write-Host "     When you exit ES-DE, they sync automatically to Steam." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ── Troubleshooting ──────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  • Emulators shown as 'config not found' above → launch each once," -ForegroundColor DarkGray
Write-Host "    then run: Start Menu → RetroDeck-Win → Scripts → Configure Paths" -ForegroundColor DarkGray
Write-Host "  • Validate BIOS files : Start Menu → RetroDeck-Win → Scripts → Check BIOS Files" -ForegroundColor DarkGray
Write-Host "  • Move data to NAS    : .\Configure-Paths.ps1 -DataRoot `"Z:\retrodeck`"" -ForegroundColor Cyan
Write-Host "  • Remove from Steam   : Start Menu → RetroDeck-Win → Scripts → Remove from Steam" -ForegroundColor DarkGray
Write-Host ""
