#Requires -Version 5.1
<#
.SYNOPSIS
    RetroDeck-Win BIOS Validator

.DESCRIPTION
    Checks your BIOS folder against a curated list of known-good file hashes
    (MD5 and SHA1) and reports the status of each required BIOS file:

      ✔  Present and verified  — hash matches a known-good dump
      ⚠  Present but unknown   — file exists but hash doesn't match any known dump
                                  (may work, may not — different region or revision)
      ✘  Missing               — required file not found

    This script never downloads or modifies files. It is read-only.

    IMPORTANT — BIOS files are copyrighted by their respective hardware manufacturers.
    You must dump them from hardware you legally own. See: https://retrodeck.readthedocs.io/en/latest/wiki_management/bios-firmware/

.PARAMETER InstallRoot
    Path where RetroDeck-Win is installed.
    Default: %LOCALAPPDATA%\RetroDeck-Win

.PARAMETER DataRoot
    Path to your RetroDeck-Win data library.
    If omitted, read from retrodeck-win.json.

.PARAMETER System
    Filter to a single system (e.g. "ps1", "nds", "gba").
    If omitted, all systems are checked.

.PARAMETER ShowAll
    Show all entries including verified ones.
    By default only missing/unknown files are listed.

.EXAMPLE
    # Check all BIOS files
    .\Check-Bios.ps1

    # Check only PS1 BIOS files
    .\Check-Bios.ps1 -System ps1

    # Show full report including verified files
    .\Check-Bios.ps1 -ShowAll

.NOTES
    BIOS files must be placed in: <DataRoot>\bios\
    Inspired by the RetroDECK project BIOS checker.
    Hash list sourced from No-Intro, Redump, and community documentation.
#>

param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\RetroDeck-Win",
    [string]$DataRoot    = "",
    [string]$System      = "",
    [switch]$ShowAll
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

 BIOS Validator
 ─────────────────────────────────────────────────────────────────

"@ -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────────
#  Load config
# ─────────────────────────────────────────────────────────────────────────────
$configFile = Join-Path $InstallRoot "retrodeck-win.json"
if (Test-Path $configFile) {
    $config = Get-Content $configFile -Raw | ConvertFrom-Json
    if ($DataRoot -eq "") { $DataRoot = $config.data_root }
} elseif ($DataRoot -eq "") {
    Write-Fail "retrodeck-win.json not found and -DataRoot not specified."
    Write-Host "  Run Install.ps1 first, or pass -DataRoot to your data library." -ForegroundColor Yellow
    exit 1
}

$biosRoot = Join-Path $DataRoot "bios"

Write-Host "  Data library : $DataRoot" -ForegroundColor White
Write-Host "  BIOS folder  : $biosRoot" -ForegroundColor White
if ($System -ne "") { Write-Host "  Filter       : $System" -ForegroundColor White }
Write-Host ""

if (-not (Test-Path $biosRoot)) {
    Write-Warn "BIOS folder does not exist: $biosRoot"
    Write-Info "Create it and copy your BIOS files there, then re-run this script."
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
#  Known-good BIOS hash list
#
#  Format per entry:
#    System   — short system ID (matches gamelist system folder name)
#    File     — filename relative to the bios\ root (may include subfolders)
#    Required — if $true, its absence is reported as an error; $false = optional
#    MD5      — known-good MD5 hash(es) as an array (empty = any hash accepted)
#    SHA1     — known-good SHA1 hash(es) as an array (empty = any hash accepted)
#    Notes    — human-readable context shown in the report
#
#  Sources: No-Intro, Redump, RetroDECK wiki, libretro BIOS documentation,
#           DuckStation / PCSX2 / RPCS3 documentation.
# ─────────────────────────────────────────────────────────────────────────────
$biosDatabase = @(

    # ── PlayStation 1 (RetroArch mednafen_psx / DuckStation) ─────────────────
    @{
        System   = "psx"
        File     = "scph5500.bin"
        Required = $false
        MD5      = @("8dd7d5296a650fac7319bce665a6a53c")
        SHA1     = @("c53ca5908936d412331790f4426c6c33a3c8252a")
        Notes    = "PS1 BIOS v3.0 (Japan) — required for Japanese games"
    }
    @{
        System   = "psx"
        File     = "scph5501.bin"
        Required = $true
        MD5      = @("490f666e1afb15b7362b406ed1cea246")
        SHA1     = @("0555c6fae8906f3f09baf5988f00e55f88e9f30b")
        Notes    = "PS1 BIOS v3.0 (USA) — most commonly required"
    }
    @{
        System   = "psx"
        File     = "scph5502.bin"
        Required = $false
        MD5      = @("32736f17079d0b2b7024407c39bd3050")
        SHA1     = @("f6bc2d1f5eb6593de7d089c425ac681d8ffed8e1")
        Notes    = "PS1 BIOS v3.0 (Europe)"
    }

    # ── PlayStation 2 (PCSX2) ─────────────────────────────────────────────────
    @{
        System   = "ps2"
        File     = "ps2-0230j-20080220.bin"
        Required = $false
        MD5      = @()
        SHA1     = @()
        Notes    = "PS2 BIOS 2.30 Japan — dump from your own PS2"
    }
    @{
        System   = "ps2"
        File     = "ps2-0230a-20080220.bin"
        Required = $false
        MD5      = @()
        SHA1     = @()
        Notes    = "PS2 BIOS 2.30 USA — dump from your own PS2"
    }
    @{
        System   = "ps2"
        File     = "ps2-0230e-20080220.bin"
        Required = $false
        MD5      = @()
        SHA1     = @()
        Notes    = "PS2 BIOS 2.30 Europe — dump from your own PS2"
    }

    # ── Nintendo DS (melonDS) ─────────────────────────────────────────────────
    @{
        System   = "nds"
        File     = "bios7.bin"
        Required = $true
        MD5      = @("df692a80a5b1bc90728bc3dfc76cd948")
        SHA1     = @("62c9b67a1aa18e579ceb9be2a1c47f4c03acf5b5")
        Notes    = "NDS ARM7 BIOS (7 KB)"
    }
    @{
        System   = "nds"
        File     = "bios9.bin"
        Required = $true
        MD5      = @("a392174eb3e572fed6447e956bde4b25")
        SHA1     = @("2616262c78b0b36d1ffd90d4c0d8f8ef74b8c71a")
        Notes    = "NDS ARM9 BIOS (4 KB)"
    }
    @{
        System   = "nds"
        File     = "firmware.bin"
        Required = $true
        MD5      = @()
        SHA1     = @()
        Notes    = "NDS firmware — varies by console serial; any 256 KB dump from your DS"
    }
    @{
        System   = "nds"
        File     = "dsi_bios7.bin"
        Required = $false
        MD5      = @()
        SHA1     = @()
        Notes    = "DSi ARM7 BIOS — required for DSi mode"
    }
    @{
        System   = "nds"
        File     = "dsi_bios9.bin"
        Required = $false
        MD5      = @()
        SHA1     = @()
        Notes    = "DSi ARM9 BIOS — required for DSi mode"
    }

    # ── Game Boy Advance (RetroArch mGBA) ─────────────────────────────────────
    # Note: mGBA has an open-source BIOS replacement (mgba_bios.bin built-in).
    # The real BIOS improves compatibility but is not required for most games.
    @{
        System   = "gba"
        File     = "gba_bios.bin"
        Required = $false
        MD5      = @("a860e8c0b6d573d191e4ec7db1b1e4f6")
        SHA1     = @("300c20df6731a33952ded8c436f7f186d25d3492")
        Notes    = "Official GBA BIOS (optional — mGBA has a built-in open-source replacement)"
    }

    # ── Sega CD / Mega-CD (RetroArch genesis_plus_gx) ────────────────────────
    @{
        System   = "segacd"
        File     = "bios_CD_U.bin"
        Required = $true
        MD5      = @("2efd74e3232ff260e371b99f84024f7f")
        SHA1     = @("f891e0ea651e2232af0c5efd2a9efd18765bfc7d")
        Notes    = "Sega CD BIOS v1.10 (USA)"
    }
    @{
        System   = "segacd"
        File     = "bios_CD_E.bin"
        Required = $false
        MD5      = @("e66fa1dc5820d254611fdcdba0662372")
        SHA1     = @("c6d10268f9ed29ef53cdb22fde35ccaa0296f386")
        Notes    = "Mega-CD BIOS v1.00 (Europe)"
    }
    @{
        System   = "segacd"
        File     = "bios_CD_J.bin"
        Required = $false
        MD5      = @("278a9397d192149e84e820ac621a8edd")
        SHA1     = @("c6d10268f9ed29ef53cdb22fde35ccaa0296f386")
        Notes    = "Mega-CD BIOS v1.00p (Japan)"
    }

    # ── PC Engine CD / TurboGrafx-CD (RetroArch mednafen_pce) ────────────────
    @{
        System   = "pcengine"
        File     = "syscard3.pce"
        Required = $true
        MD5      = @("38179df8f4ac870017db21ebcbf53114")
        SHA1     = @("4c2126b5f6fd569e80f29f7d429df30e8d41b6d5")
        Notes    = "PC Engine Super System Card 3.0 — required for CD-ROM games"
    }

    # ── Nintendo GameCube / Wii (Dolphin) ─────────────────────────────────────
    # Dolphin does not strictly require a BIOS/IPL for most games, but some
    # games use it for region-specific behavior. Optional.
    @{
        System   = "gc"
        File     = "GC\USA\IPL.bin"
        Required = $false
        MD5      = @("019e39822a9ca3029124f74dd4d55ac4")
        SHA1     = @()
        Notes    = "GameCube IPL / BIOS (USA) — optional, improves compatibility"
    }
    @{
        System   = "gc"
        File     = "GC\EUR\IPL.bin"
        Required = $false
        MD5      = @("b5ef5e8bd1da4e9b8e4f12197a2f8bba")
        SHA1     = @()
        Notes    = "GameCube IPL / BIOS (Europe) — optional"
    }
    @{
        System   = "gc"
        File     = "GC\JAP\IPL.bin"
        Required = $false
        MD5      = @("6DAC1F3714515734CF928CC3CBFF2B04")
        SHA1     = @()
        Notes    = "GameCube IPL / BIOS (Japan) — optional"
    }

    # ── Atari Lynx (RetroArch mednafen_lynx) ──────────────────────────────────
    @{
        System   = "lynx"
        File     = "lynxboot.img"
        Required = $true
        MD5      = @("fcd403db69f54290b51035d82f835e7b")
        SHA1     = @("fed9f4f0e8a40c68f8eb5bbc93f18cb78b1ae0e7")
        Notes    = "Atari Lynx Bootstrap ROM"
    }

    # ── Sega Saturn (RetroArch Beetle Saturn) ─────────────────────────────────
    @{
        System   = "saturn"
        File     = "sega_101.bin"
        Required = $false
        MD5      = @("85ec9ca47d8f6807718151cbcca8b964")
        SHA1     = @()
        Notes    = "Sega Saturn BIOS v1.01 (Japan)"
    }
    @{
        System   = "saturn"
        File     = "mpr-17933.bin"
        Required = $false
        MD5      = @("3240872c70984b6cbfda1586cab68dbe")
        SHA1     = @()
        Notes    = "Sega Saturn BIOS v1.00 (USA/Europe)"
    }

    # ── MSX / MSX2 (RetroArch BlueMSX) ────────────────────────────────────────
    @{
        System   = "msx"
        File     = "MSX.ROM"
        Required = $true
        MD5      = @()
        SHA1     = @()
        Notes    = "MSX1 BIOS — place under bios\Machines\<MSX model>\"
    }
    @{
        System   = "msx2"
        File     = "MSX2.ROM"
        Required = $true
        MD5      = @()
        SHA1     = @()
        Notes    = "MSX2 BIOS — place under bios\Machines\<MSX2 model>\"
    }

    # ── Atari 7800 (RetroArch prosystem) ──────────────────────────────────────
    @{
        System   = "atari7800"
        File     = "7800 BIOS (U).rom"
        Required = $false
        MD5      = @("0763f1ffb006ddbe32e52d497ee848ae")
        SHA1     = @()
        Notes    = "Atari 7800 BIOS (USA) — optional, enables High Score Cartridge"
    }

    # ── PS Vita (Vita3K) ──────────────────────────────────────────────────────
    # PS Vita firmware is officially distributed by Sony. Download from:
    # https://www.playstation.com/en-us/support/hardware/psvita/system-software/
    @{
        System   = "psvita"
        File     = "PSP2UPDAT.PUP"
        Required = $true
        MD5      = @()
        SHA1     = @()
        Notes    = "PS Vita firmware — official download from Sony at https://www.playstation.com/en-us/support/hardware/psvita/system-software/"
    }

    # ── Xbox (xemu) ───────────────────────────────────────────────────────────
    @{
        System   = "xbox"
        File     = "xbox_hdd.qcow2"
        Required = $false
        MD5      = @()
        SHA1     = @()
        Notes    = "Xbox HDD image for xemu — generate with xemu's HDD image generator"
    }
    @{
        System   = "xbox"
        File     = "Complex_4627v1.03.bin"
        Required = $false
        MD5      = @()
        SHA1     = @()
        Notes    = "Xbox BIOS (Complex modchip) — dump from your own Xbox"
    }
    @{
        System   = "xbox"
        File     = "mcpx_1.0.bin"
        Required = $true
        MD5      = @("d49c52a4102f6df7bcf8d0617ac475ed")
        SHA1     = @()
        Notes    = "Xbox MCPX Boot ROM (1.0) — required by xemu"
    }
)

# ─────────────────────────────────────────────────────────────────────────────
#  Hash helpers
# ─────────────────────────────────────────────────────────────────────────────
function Get-MD5 {
    param([string]$Path)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $fs  = [System.IO.File]::OpenRead($Path)
    try { return [System.BitConverter]::ToString($md5.ComputeHash($fs)) -replace '-','' }
    finally { $fs.Close() }
}

function Get-SHA1 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $fs  = [System.IO.File]::OpenRead($Path)
    try { return [System.BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-','' }
    finally { $fs.Close() }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Filter by system if requested
# ─────────────────────────────────────────────────────────────────────────────
$checkList = $biosDatabase
if ($System -ne "") {
    $checkList = $biosDatabase | Where-Object { $_.System -eq $System.ToLower() }
    if ($checkList.Count -eq 0) {
        Write-Warn "No BIOS entries found for system '$System'."
        Write-Info "Known systems: $(($biosDatabase | Select-Object -ExpandProperty System -Unique | Sort-Object) -join ', ')"
        exit 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Run checks
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Checking BIOS files"

$statVerified = 0
$statUnknown  = 0
$statMissing  = 0
$lastSystem   = ""

foreach ($entry in $checkList | Sort-Object System, File) {

    # Print system header when it changes
    if ($entry.System -ne $lastSystem) {
        Write-Host ""
        Write-Host ("  ── {0} ──" -f $entry.System.ToUpper()) -ForegroundColor White
        $lastSystem = $entry.System
    }

    $fullPath = Join-Path $biosRoot $entry.File
    $label    = "  $($entry.File)"
    if (-not $entry.Required) { $label += " [optional]" }

    if (-not (Test-Path $fullPath)) {
        # File not found
        if ($entry.Required) {
            Write-Fail "$label"
            Write-Info "    $($entry.Notes)"
            $statMissing++
        } else {
            if ($ShowAll) {
                Write-Skip "$label"
                Write-Info "    $($entry.Notes)"
            }
            $statMissing++  # count optionals in missing too (shown in summary)
        }
        continue
    }

    # File exists — compute hashes
    $md5Actual  = Get-MD5  -Path $fullPath
    $sha1Actual = Get-SHA1 -Path $fullPath

    $md5Match  = ($entry.MD5.Count  -eq 0) -or ($entry.MD5  -contains $md5Actual.ToLower())
    $sha1Match = ($entry.SHA1.Count -eq 0) -or ($entry.SHA1 -contains $sha1Actual.ToLower())

    if ($md5Match -and $sha1Match) {
        $statVerified++
        if ($ShowAll) {
            Write-OK "$label"
            Write-Info "    MD5:  $md5Actual"
        }
    } else {
        # File present but hash doesn't match any known-good entry
        Write-Warn "$label — hash mismatch (different region or revision?)"
        Write-Info "    $($entry.Notes)"
        Write-Info "    Actual MD5 : $md5Actual"
        if ($entry.MD5.Count -gt 0) {
            Write-Info "    Expected   : $($entry.MD5 -join ' | ')"
        }
        $statUnknown++
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Summary
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Summary"

$total = $checkList.Count
Write-Host ("  {0,-40} {1}" -f "Total BIOS entries checked:", $total) -ForegroundColor White
Write-Host ("  {0,-40} {1}" -f "Verified (hash matches known-good):", $statVerified) -ForegroundColor Green
Write-Host ("  {0,-40} {1}" -f "Present but unknown hash:", $statUnknown) -ForegroundColor Yellow
Write-Host ("  {0,-40} {1}" -f "Missing:", $statMissing) -ForegroundColor $(if ($statMissing -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($statMissing -eq 0 -and $statUnknown -eq 0) {
    Write-OK "All BIOS files verified!"
} else {
    if ($statUnknown -gt 0) {
        Write-Warn "Some files have unknown hashes. They may still work — different region or revision."
        Write-Info "If a game fails to boot, try sourcing a BIOS that matches the expected hash."
    }
    if ($statMissing -gt 0) {
        Write-Warn "Some BIOS files are missing."
        Write-Info "You must dump them from hardware you legally own."
        Write-Info "See: https://retrodeck.readthedocs.io/en/latest/wiki_management/bios-firmware/"
    }
}

if (-not $ShowAll -and $statVerified -gt 0) {
    Write-Host ""
    Write-Info "($statVerified verified file(s) not shown — use -ShowAll to display them)"
}

Write-Host ""
