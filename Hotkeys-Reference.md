# RetroDeck-Win — Hotkey Reference

This document maps the standard RetroDECK hotkey actions to the configuration
keys used by each emulator on Windows. Use this as a guide when building config
templates for `Install.ps1`.

---

## Standard Hotkey Layout (gamepad)

The modifier button is **Select** (held). Combined with other buttons:

| Combo | Action |
|---|---|
| Select + Start | **Quit** emulator |
| Select + A (South) | **Save State** |
| Select + B (East) | **Load State** |
| Select + Y (North) | **Screenshot** |
| Select + X (West) | **Open emulator menu** |
| Select + D-Pad Up | **State slot +1** |
| Select + D-Pad Down | **State slot −1** |
| Select + D-Pad Right | **Fast Forward** |
| Select + D-Pad Left | **Rewind** |
| Select + L1 | **Pause / Resume** |
| Select + R1 | **Reset game** |

> On keyboard the equivalent modifier is typically **F1** or a configurable
> hotkey enable key, followed by the mapped key for each action.

---

## RetroArch (`retroarch.cfg`)

RetroArch implements all hotkeys natively. The key names below go directly
into `retroarch.cfg`. For gamepad buttons use `_btn` suffix; for keyboard
use key names (`f1`, `escape`, etc.).

```ini
# Hotkey enable (modifier — hold this, then press the action key)
input_enable_hotkey_btn = 8          ; Select button (XInput index 6)

# Core actions
input_save_state_btn    = 0          ; A button
input_load_state_btn    = 1          ; B button
input_screenshot_btn    = 3          ; Y button
input_menu_toggle_btn   = 2          ; X button
input_exit_emulator_btn = 9          ; Start button (XInput index 7)
input_pause_toggle_btn  = 4          ; L1 button
input_reset_btn         = 5          ; R1 button
input_state_slot_increase_btn = 11   ; D-Pad Right
input_state_slot_decrease_btn = 10   ; D-Pad Left
input_hold_fast_forward_btn   = 13   ; D-Pad Right (axis)
input_rewind_btn              = 12   ; D-Pad Left  (axis)

# Keyboard equivalents (used when no controller is connected)
input_enable_hotkey   = scroll_lock
input_save_state      = f2
input_load_state      = f4
input_screenshot      = f8
input_menu_toggle     = f1
input_exit_emulator   = escape
input_pause_toggle    = p
input_reset           = h
input_state_slot_increase = right
input_state_slot_decrease = left
input_hold_fast_forward   = space
input_rewind              = r
```

> **Notes:**
> - XInput button indices: A=0 B=1 X=2 Y=3 L1=4 R1=5 Select=6 Start=7 L3=8 R3=9 DPad-Up=10 DPad-Down=11 DPad-Left=12 DPad-Right=13
> - Rewind requires `rewind_enable = true` in `retroarch.cfg`
> - `input_enable_hotkey_btn` acts as the modifier — other hotkeys only fire while it is held

---

## PCSX2 (`PCSX2.ini` → `[Hotkeys]` section + `PCSX2_keys.ini`)

PCSX2 Qt stores controller hotkeys in `PCSX2.ini` under `[Hotkeys]`.
Keyboard hotkeys can be overridden via `PCSX2_keys.ini`.

### `PCSX2.ini` — `[Hotkeys]` section (controller buttons)

```ini
[Hotkeys]
OpenPauseMenu           = Keyboard/Escape
TogglePause             = Keyboard/P
ResetVM                 = Keyboard/F5
Screenshot              = Keyboard/F8
SaveStateToSlot         = Keyboard/F1
LoadStateFromSlot       = Keyboard/F3
NextSaveStateSlot       = Keyboard/F2
PreviousSaveStateSlot   = Keyboard/Shift & Keyboard/F2
ToggleFullscreen        = Keyboard/Alt & Keyboard/Return
IncreaseSpeed           = Keyboard/Tab
ToggleFrameLimiter      = Keyboard/F4
```

### `PCSX2_keys.ini` — keyboard override format

```ini
; Format: FunctionName = [modifier-]key
States_FreezeCurrentSlot  = F1
States_DefrostCurrentSlot = F3
States_CycleSlotForward   = F2
States_CycleSlotBackward  = shift-F2
Sys_TakeSnapshot          = F8
Sys_Suspend               = ESC
Framelimiter_TurboToggle  = TAB
Framelimiter_SlomoToggle  = shift-TAB
FullscreenToggle          = alt-BACK  ; Alt+Enter
```

> **Notes:**
> - Controller hotkeys in PCSX2 Qt require mapping through the GUI or `PCSX2.ini`
>   `[Hotkeys]` section using `SDL-<device>/Button<N>` syntax
> - Example: `SaveStateToSlot = SDL-0/Button0` maps save state to button A of
>   the first controller

---

## DuckStation (`settings.ini` → `[Hotkeys]` section)

DuckStation stores all hotkeys in `settings.ini` under `[Hotkeys]`.
Values use the same binding format as controller inputs.

```ini
[Hotkeys]
; Keyboard defaults
Screenshot              = Keyboard/F10
TogglePause             = Keyboard/Pause
ToggleFullscreen        = Keyboard/Alt & Keyboard/Return
ExitGame                = Keyboard/Escape
SaveSelectedSaveState   = Keyboard/F1
LoadSelectedSaveState   = Keyboard/F2
SelectPreviousSaveStateSlot = Keyboard/F3
SelectNextSaveStateSlot     = Keyboard/F4
ToggleCheats            = Keyboard/F9
ResetSystem             = Keyboard/F5
IncreaseResolutionScale = Keyboard/PageUp
DecreaseResolutionScale = Keyboard/PageDown

; Controller hotkeys — bound to Guide/PS button as modifier
; Example: Xbox Guide + A = Save State
; These are set via GUI; the ini keys look like:
; SaveSelectedSaveState = XInputController0/Button12
```

> **Notes:**
> - DuckStation does not have a dedicated "hotkey modifier" key like RetroArch.
>   Each function gets its own full binding (key or button).
> - For controller use, assign the hotkeys via Settings → Controllers → Hotkeys
>   in the GUI, then copy the generated `[Hotkeys]` section into the template.

---

## Dolphin (`Hotkeys.ini`)

Dolphin stores hotkeys in `<UserDir>\Config\Hotkeys.ini`, separate from
controller configs. The section is `[Hotkeys]`.

```ini
[Hotkeys]
# Keys use Dolphin's expression syntax: KEY(name) or XInput2/Shoulder_L etc.

# Keyboard bindings
Load_State_Slot_1       = KEY(F1)
Save_State_Slot_1       = KEY(LSHIFT) & KEY(F1)
Load_State_Slot_2       = KEY(F2)
Save_State_Slot_2       = KEY(LSHIFT) & KEY(F2)
# … slots 3–8 follow the same pattern

Take_Screenshot         = KEY(F9)
Toggle_Pause            = KEY(F10) | KEY(PAUSE)
Stop                    = KEY(ESCAPE)
Reset                   = KEY(LSHIFT) & KEY(F9)
Toggle_Fullscreen       = KEY(LMENU) & KEY(RETURN)
Increase_Frame_Limit    = KEY(TAB)
Toggle_Frame_Limit      = KEY(LSHIFT) & KEY(TAB)

# Load/Save State (any slot) — for controller binding
# Use XInput2/Button_A, XInput2/Shoulder_L, etc.
# There is no global modifier concept; each action gets its own binding
Load_State_Slot_Selected = XInput2/Back & XInput2/Button_B
Save_State_Slot_Selected = XInput2/Back & XInput2/Button_A
Take_Screenshot          = XInput2/Back & XInput2/Button_Y
Toggle_Pause             = XInput2/Back & XInput2/Shoulder_L
Stop                     = XInput2/Back & XInput2/Start
```

> **Notes:**
> - `XInput2/Back` = Select button (the modifier)
> - `XInput2/Start` = Start button
> - `XInput2/Button_A/B/X/Y` = face buttons
> - `XInput2/Shoulder_L/R` = L1/R1
> - Dolphin does **not** support per-game hotkey overrides — Hotkeys.ini is global
> - Save/Load slot cycling isn't natively bound to D-Pad in Dolphin;
>   individual slots (F1–F8) are the standard approach

---

## RPCS3 (`config.yml`)

RPCS3 has limited hotkey customization via config. Most keyboard shortcuts
are hardcoded; a hotkey manager is a long-requested feature (#5681).

```yaml
# config.yml — relevant keyboard shortcuts (hardcoded, not configurable)
# These are the defaults, documented here for reference:
#
# Ctrl+S        Save state (where supported)
# Ctrl+E        Resume/Pause
# Ctrl+R        Restart game
# Escape        Stop emulation / return to main window
# F12           Screenshot (via SDL or emulator)
#
# Controller hotkeys:
# RPCS3 does not support controller button combos as hotkeys natively.
# The only workaround is Steam Input: map button chords to keyboard keys
# that match the keyboard shortcuts above.
```

> **Notes:**
> - RPCS3 hotkey customization is minimal — this is a known limitation
> - For a uniform controller experience, use Steam Input to map
>   Select+A → Ctrl+S, Select+Start → Escape, etc.
> - Save states in RPCS3 are PS3-system-level saves, not savestates like
>   RetroArch — not all games support them

---

## PPSSPP (`ppsspp.ini` → `[Control]` section)

PPSSPP stores system hotkeys in `ppsspp.ini`. Controller hotkey mapping
is in `controls.ini` in the same folder.

```ini
; ppsspp.ini — system hotkeys (keyboard)
[Control]
; These map to the "System" actions, separate from PSP button mapping

; controls.ini — controller mapping
; Format: ActionName = deviceN.buttonN
; System actions for hotkeys:
[ControlMapping]
Fast-forward             = 1-999         ; Right trigger axis held
Save State               = 1-102         ; F6 key
Load State               = 1-104         ; F8 key
Pause                    = 1-110         ; F14
Screenshot               = 1-116         ; F12 (default)
Change Save State Slot   = 1-103         ; F7
```

> **Notes:**
> - PPSSPP controller hotkeys use a numeric device/button mapping internally
> - For Xbox controller: device 1, buttons follow XInput index
> - The cleanest approach for controller hotkeys in PPSSPP is via Steam Input,
>   mapping Select+button chords to the keyboard shortcuts
> - Default keyboard hotkeys: F1=Save, F2=Next Slot, F3=Load, F12=Screenshot,
>   Escape=Pause/Menu, Tab=Fast Forward

---

## melonDS (`melonDS.ini`)

melonDS has limited configurable hotkeys. Save/load state remapping via
config is not yet supported in standalone melonDS (tracked in issue #2213).

```ini
; melonDS.ini — configurable hotkeys
[Hotkeys]
; Key values are Qt key codes (integers)
; Common Qt key codes:
;   Qt::Key_F1 = 16777264, F2 = 16777265, F3 = 16777266 ...
;   Qt::Key_Escape = 16777216, Qt::Key_P = 80, Qt::Key_Tab = 16777217

; Currently configurable:
Pause                    = 16777265   ; F2 (default)
Reset                    = 16777266   ; F3
FrameLimitEnable         = 16777217   ; Tab
FastForward              = 96         ; ` (backtick)
FastForwardToggle        = 16777217   ; Tab (toggle mode)
FullscreenToggle         = 16777264   ; F1
Screenshot               = 70        ; F (default, not configurable in GUI)
QuitEmu                  = 16777216   ; Escape

; Save/Load state hotkeys are NOT configurable in melonDS standalone.
; Workaround: use Steam Input to map controller chords to F5/F6/F7/F8
; which are the default save state keys.
```

> **Notes:**
> - melonDS save state defaults: F5=Save, F6=Load, F7=Prev Slot, F8=Next Slot
> - These are hardcoded and cannot be remapped in the config file
> - For controller hotkeys, Steam Input is the only reliable solution

---

## Cemu (`settings.xml`)

Cemu stores hotkeys in `settings.xml`. Hotkeys use SDL/XInput identifiers.

```xml
<!-- settings.xml — relevant hotkey entries -->
<content>
  <Screenshot>     <key>F9</key>   </Screenshot>
  <TogglePause>    <key>F5</key>   </TogglePause>
  <ExitGame>       <key>Escape</key> </ExitGame>
  <SaveStateSlot1> <key>Shift+F1</key> </SaveStateSlot1>
  <LoadStateSlot1> <key>F1</key>   </LoadStateSlot1>
  <FastForward>    <key>Tab</key>  </FastForward>
</content>
```

> **Notes:**
> - Cemu hotkey configuration via XML is mostly for keyboard
> - Controller hotkeys are configured via the Input Settings GUI
> - Cemu does support controller button combos natively via its input system

---

## Summary Table

| Action | RetroArch | PCSX2 | DuckStation | Dolphin | RPCS3 | PPSSPP | melonDS | Cemu |
|---|---|---|---|---|---|---|---|---|
| **Save State** | `F2` / Select+A | `F1` | `F1` | Shift+F1 | Ctrl+S | F1 | F5 ⚠ | Shift+F1 |
| **Load State** | `F4` / Select+B | `F3` | `F2` | F1 | — | F3 | F6 ⚠ | F1 |
| **Screenshot** | `F8` / Select+Y | `F8` | `F10` | F9 | F12 | F12 | F (⚠) | F9 |
| **Pause** | `P` / Select+L1 | `Escape` | Pause key | F10 | Ctrl+E | Escape | F2 | F5 |
| **Quit** | `Escape` / Select+Start | `Escape` | `Escape` | Escape | Escape | Escape | Escape | Escape |
| **Fast Forward** | `Space` / DPad-Right | `Tab` | — | Tab | — | Tab | Tab | Tab |
| **Reset** | `H` / Select+R1 | `F5` | `F5` | Shift+F9 | Ctrl+R | — | F3 | — |
| **State Slot +1** | `Right` / DPad-Up | `F2` | `F4` | — | — | F2 | — | — |
| **Controller modifier** | Select (btn 6) | Via GUI | Via GUI | XInput Back | Steam Input | Steam Input | Steam Input | Via GUI |

⚠ = Hardcoded, not remappable in config file

---

## Recommended approach for `Install.ps1` templates

1. **RetroArch**: fully configurable via `retroarch.cfg` — ship with complete
   hotkey section pre-configured using Select as modifier.

2. **PCSX2, DuckStation, Dolphin, Cemu**: configurable via their INI/XML files.
   Set keyboard hotkeys to a consistent set (F1/F3/F8/Escape/Tab) in the
   templates, and document that controller hotkeys need one-time setup in the GUI.

3. **RPCS3, PPSSPP, melonDS**: limited config-file hotkey support. Ship keyboard
   defaults; recommend Steam Input for controller modifier combos.

---

Sources:
- [RetroArch Input documentation](https://docs.libretro.com/guides/input-and-controls/)
- [PCSX2 Hotkeys Wiki](https://wiki.pcsx2.net/Hotkeys)
- [DuckStation hotkeys.cpp](https://github.com/stenzek/duckstation/blob/master/src/core/hotkeys.cpp)
- [Dolphin HotkeyManager.cpp](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/HotkeyManager.cpp)
- [RPCS3 Keyboard Shortcuts](https://wiki.rpcs3.net/index.php?title=Help:Keyboard_Shortcuts)
- [PPSSPP Controls documentation](https://www.ppsspp.org/docs/settings/controls/)
- [melonDS hotkey issues #2213](https://github.com/melonDS-emu/melonDS/issues/2213)
- [RetroDECK Controller Hotkeys](https://retrodeck.readthedocs.io/en/latest/wiki_rd_controls/hotkeys-retrodeck/)
