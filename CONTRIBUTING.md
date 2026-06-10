# Contributing to RetroDeck-Win

Thank you for your interest in contributing. This document explains how to get involved and the conventions used in this project.

---

## About this project

RetroDeck-Win was designed and developed by **Rogério C. Rocha** ([@rogercrocha](https://github.com/rogercrocha)) with **[Claude](https://claude.ai)** (Anthropic's AI assistant) as a development collaborator.

Claude was used throughout the project for architecture decisions, writing and reviewing all PowerShell scripts, researching emulator config formats, binary VDF parsing, Steam Input template structure, and SteamGridDB API integration. The full development conversation informed the design of every script in this repository.

This is an experiment in AI-assisted open source development. Contributions from humans are very welcome.

---

## Ways to contribute

- **Bug reports** — open an issue with your Windows version, PowerShell version, and the full error output
- **Emulator support** — add a new system to `$systemMap` in `Sync-SteamFavorites.ps1` or a new emulator component to `$Components` in `Install.ps1`
- **BIOS hashes** — add verified MD5/SHA1 entries to the `$biosDatabase` in `Check-Bios.ps1`
- **Hotkey configs** — improve or add hotkey mappings in `Set-EmulatorHotkeys` inside `Install.ps1`
- **Steam Input templates** — add or improve `.vdf` controller templates in `steam-input/`
- **Documentation** — fix typos, improve explanations, add examples

---

## Code conventions

- **Language:** PowerShell 5.1 (no PowerShell 7+ features — must run on the inbox Windows version)
- **Comments:** English only
- **Output helpers:** use `Write-Step`, `Write-OK`, `Write-Warn`, `Write-Fail`, `Write-Skip`, `Write-Info` — no raw `Write-Host` with inline colors
- **Error handling:** use `try/catch` for anything that touches the filesystem, network, or registry; never let an emulator failure abort the whole install
- **Dry run:** any function that writes files must respect `$DryRun` and print what it would do instead
- **Backups:** always `Copy-Item $path ($path+".bak")` before overwriting any user file (shortcuts.vdf, localconfig.vdf, emulator configs)
- **Paths:** use `Join-Path` — never string concatenation with `\`
- **Encoding:** always specify `-Encoding UTF8` on `Get-Content` / `Set-Content`

---

## Testing

Before opening a pull request:

1. Run `Install.ps1 -DryRun` and confirm the output looks correct
2. Run `Sync-SteamFavorites.ps1 -DryRun` and confirm no files are modified
3. Run `Check-Bios.ps1` against a real BIOS folder if you changed the hash database
4. Test with Steam closed, then restart Steam and confirm shortcuts appear

There is no automated test suite yet. A `Test-Install.ps1` harness is a welcome contribution.

---

## Pull request checklist

- [ ] Comments in English
- [ ] `$DryRun` respected where files are written
- [ ] Backups created before overwriting user files
- [ ] `Write-*` helpers used for output (not raw `Write-Host`)
- [ ] Tested on Windows 11 with PowerShell 5.1
- [ ] `README.md` updated if you added a new feature or changed behavior

---

## Opening issues

Please include:
- Windows version (`winver`)
- PowerShell version (`$PSVersionTable.PSVersion`)
- Which script failed and the full terminal output
- Whether you ran as Administrator

---

## License

By contributing, you agree that your contributions will be licensed under the [GPL-3.0 License](LICENSE).
