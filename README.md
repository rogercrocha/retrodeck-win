# RetroDeck-Win

> ## 🚧 Work in progress — not ready for use
>
> This project is under active development. The installer and per-emulator
> configuration (starting with Dolphin) are being reworked in detail, and the
> code is **not** in a usable state right now. Please **do not run the scripts**
> until this notice is removed. Stars/issues welcome, but expect breaking
> changes and force-pushes while the implementation is being finalized.

**A Windows 11 adaptation of the [RetroDECK](https://github.com/retrodeck/retrodeck) concept.**

RetroDeck-Win installs a complete portable emulation stack on Windows 11, maps a unified data library (ROMs, BIOS, saves, texture packs) to any location — including a NAS — and integrates the entire collection with Steam: favorites marked in ES-DE automatically appear as Steam shortcuts with box art, controller hotkeys, and Steam Input templates.

> **Note:** This project is not affiliated with the official RetroDECK team. It is a community adaptation inspired by RetroDECK's architecture and philosophy, written from scratch for Windows.

> **About this project:** Conceived by [Rogério C. Rocha](https://github.com/rogercrocha) and coded with [Claude](https://claude.ai) (Anthropic) as AI development collaborator.

---

## Features

- **No administrator required** — installs entirely in your user profile; no UAC prompts
- **One-command install** — downloads and configures 14 portable emulators with no system-wide installation
- **Flexible data library** — ROMs, BIOS, saves, states, texture packs, and mods in a single folder that can live on a local drive, external drive, or NAS (mapped drive letter)
- **ES-DE frontend** — pre-configured to find your ROMs automatically on first launch
- **Steam sync** — mark games as ⭐ favorites in ES-DE; they appear in Steam when you exit, complete with box art from SteamGridDB
- **Steam Input hotkeys** — 9 controller templates (Xbox, PlayStation 3/4/5/5 Edge, Switch Pro, Steam Controller, Generic) with a consistent `Select + button` hotkey layout across all emulators
- **Start Menu integration** — organized shortcuts under `RetroDeck-Win › Emulators` and `RetroDeck-Win › Scripts`
- **BIOS validator** — `Check-Bios.ps1` validates your BIOS files by MD5/SHA1 against known-good hashes
- **NAS-friendly** — all paths are remappable; move your library at any time with `Configure-Paths.ps1`

### Included emulators

| Emulator | Systems |
|---|---|
| RetroArch | NES, SNES, GB/GBC/GBA, Genesis, Master System, N64, PS1, PC Engine, Sega CD, 32X, Atari, MSX, Virtual Boy, Lynx, NGP, WonderSwan |
| PCSX2 | PlayStation 2 |
| DuckStation | PlayStation 1 |
| Dolphin | GameCube, Wii |
| RPCS3 | PlayStation 3 |
| melonDS | Nintendo DS / DSi |
| PPSSPP | PSP |
| Cemu | Wii U |
| xemu | Xbox |
| Vita3K | PS Vita |
| MAME | Arcade |
| GZDoom | DOOM / GZDoom games |
| Azahar | Nintendo 3DS |
| Ruffle | Flash |

### Hotkey layout (Select as modifier)

| Combo | Action |
|---|---|
| Select + A | Save State (F1) |
| Select + B | Load State (F3) |
| Select + X | Reset (F5) |
| Select + Y | Screenshot (F8) |
| Select + Start | Quit (Escape) |
| Select + L1 | Pause (P) |
| Select + R1 | Fast Forward (Tab) |
| Select + D-Pad Left | Rewind (R) |
| Select + D-Pad Up/Down | Save Slot +1 / −1 |

---

## Data folder and Linux interoperability

RetroDeck-Win stores all user data (ROMs, BIOS, saves, states, texture packs) in a subfolder named **`retrodeck`** — the same name used by the original RetroDECK on Linux (`~/retrodeck`).

This means you can share the same library between Linux/Steam Deck and Windows by pointing both to the same NAS path:

| OS | Default path |
|---|---|
| Linux / Steam Deck | `~/retrodeck` |
| Windows (local) | `%USERPROFILE%\Documents\retrodeck` |
| Windows (NAS) | `Z:\ROMs\retrodeck` (any path on any drive letter) |

The emulator binary folder (`%LOCALAPPDATA%\RetroDeck-Win`) is Windows-only. Only the `retrodeck` data folder is shared.

> **Linux/Steam Deck tip:** To mount a NAS share as `~/retrodeck` on Linux, check out [smb-wizard-for-linux](https://github.com/rogercrocha/smb-wizard-for-linux) — a guided script by [Rogério C. Rocha](https://github.com/rogercrocha) that configures SMB/CIFS mounts with credentials, automount on boot, and the correct permissions for RetroDeck-Win.

---

## Requirements

- Windows 11 (Windows 10 may work but is untested)
- PowerShell 5.1 or later (included in Windows)
- Steam installed and logged in at least once
- ~15 GB free disk space for emulator binaries
- Your own ROM and BIOS files (see [BIOS note](#bios-note) below)

No administrator privileges required.

---

## Install

Open PowerShell and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
(New-Object Net.WebClient).DownloadString("https://raw.githubusercontent.com/rogercrocha/retrodeck-win/main/Install.ps1") | Out-File "$env:TEMP\rdw-install.ps1" -Encoding UTF8
& "$env:TEMP\rdw-install.ps1"
```

The installer will:
1. Ask where you want your data library (local drive, external drive, or NAS)
2. Ask for a [SteamGridDB](https://www.steamgriddb.com) API key for box art (optional — you can skip and add it later)
3. Download and extract all 14 emulators to `%LOCALAPPDATA%\RetroDeck-Win\`
4. Configure each emulator to use your chosen data library
5. Pre-configure keyboard hotkeys in every emulator
6. Create Start Menu shortcuts
7. Add ES-DE as a non-Steam shortcut (enables Steam overlay and controller templates)

To install to a custom location:

```powershell
& "$env:TEMP\rdw-install.ps1" -InstallRoot "D:\Games\RetroDeck-Win" -DataRoot "Z:\ROMs\retrodeck"
```

---

## Getting started

1. **Restart Steam** — the ES-DE entry will appear in your library
2. **Copy ROMs** to `<DataRoot>\roms\<system>\` (e.g. `roms\snes\`, `roms\ps2\`)
3. **Copy BIOS files** to `<DataRoot>\bios\` — run `Check-Bios.ps1` to validate them
4. **Launch ES-DE** from Steam (recommended) or Start Menu
5. In ES-DE, **mark games as favorites** with the north button (Y / Triangle / X)
6. **Exit ES-DE** — favorites sync to Steam automatically with artwork

Scripts are accessible from **Start Menu → RetroDeck-Win → Scripts** or directly from your Desktop shortcut.

---

## Scripts

| Script | Purpose |
|---|---|
| `Launch-RetroDeckWin.ps1` | Main launcher — starts ES-DE, syncs Steam on exit |
| `Sync-SteamFavorites.ps1` | Syncs ES-DE favorites to Steam shortcuts and artwork |
| `Configure-Paths.ps1` | Remaps all emulator configs to a new data library location |
| `Check-Bios.ps1` | Validates BIOS files by MD5/SHA1 against known-good hashes |

---

## BIOS note

BIOS files are copyrighted by their respective hardware manufacturers and **cannot be distributed with this project**. You must dump them from hardware you legally own.

Run `Check-Bios.ps1` after placing your files in `<DataRoot>\bios\` to verify them:

```powershell
.\Check-Bios.ps1 -ShowAll
```

The PS Vita firmware (`PSP2UPDAT.PUP`) is an exception — Sony officially distributes it at [playstation.com](https://www.playstation.com/en-us/support/hardware/psvita/system-software/).

---

## Moving your library

To move your data to a new location (different drive, NAS, etc.):

```powershell
.\Configure-Paths.ps1 -DataRoot "Z:\ROMs\retrodeck"
```

All emulator configs, Junction Points, and `retrodeck-win.json` are updated automatically.

---

## Artwork (SteamGridDB)

Box art, hero images, and logos are downloaded from [SteamGridDB](https://www.steamgriddb.com) during Steam sync. A free personal API key is required. The installer will prompt you for it during setup — you can also skip it and add it later:

1. Go to [steamgriddb.com](https://www.steamgriddb.com) and log in with your Steam account
2. Avatar → Preferences → API → Generate API Key
3. Run the installer again or `Sync-SteamFavorites.ps1` — it will prompt you to enter the key

---

## Inspired by

This project is directly inspired by **[RetroDECK](https://github.com/retrodeck/retrodeck)** — the all-in-one retro gaming platform for Linux and Steam Deck, built by the RetroDECK Team.

RetroDeck-Win adapts the following concepts from RetroDECK:
- Separation of emulator binaries from user data
- Unified folder structure for ROMs, BIOS, saves, and texture packs
- Steam sync via `shortcuts.vdf` and Steam ROM Manager
- Steam Input controller templates with `Select` as a hotkey modifier
- ES-DE as the frontend

RetroDeck-Win is **not** a fork of the RetroDECK codebase. It is written from scratch in PowerShell and licensed under GPL-3.0 in alignment with the original project's license.

---

## License

[GPL-3.0](LICENSE) — same as the original RetroDECK project.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
