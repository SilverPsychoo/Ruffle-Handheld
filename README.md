# Ruffle Handheld

[Español](README.es.md)

Ruffle Handheld is an offline Flash game launcher for ARM64 Linux handhelds. It bundles a Ruffle-derived console runtime, integrates Flash games into EmulationStation, supports per-game controller profiles, and handles both single-file and multi-file Flash games.

**No Flash games are included. No Adobe Flash Player files are included.**

## Current support

- Architecture: **aarch64 / ARM64**.
- First real-device testing: RK3326 handheld + EmuELEC.
- Community test targets include ArkOS, ROCKNIX, muOS, Knulli, AmberELEC and other Linux handheld environments.
- PortMaster helpers are used when available, but the release itself is fully offline and includes its runtime.
- The project is not tied to one console model.

## Installation

### Manual / offline installation

Download the latest offline ZIP from **Releases**. It contains only:

```text
Ruffle Handheld.sh
rufflehandheld/
```

Copy both items into the handheld's **Ports** folder, then launch **Ruffle Handheld** once from the Ports menu.

The first run:

1. Detects the ROM root when possible.
2. Creates the Flash game folders.
3. Registers a **Flash Games** system in EmulationStation.
4. Uses the current EmulationStation theme without overwriting it.
5. Keeps the complete runtime inside the port folder.

If Flash Games does not appear immediately, restart EmulationStation.

**Internet is not required.** The ARM64 runtime and required project files are already included in the release.

### PortMaster

The repository uses a PortMaster-style port layout so it can be tested across supported handheld environments and prepared for a future PortMaster submission. Until an official catalog entry exists, use the manual/offline release.

## Folder layout after setup

The player only needs to care about the game folders created under the ROM root:

```text
ROMs/
├── flash/
└── flash_data/
```

The installed runtime stays inside Ports:

```text
Ports/
├── Ruffle Handheld.sh
└── rufflehandheld/
    ├── bin/
    ├── runtime/
    ├── profiles/
    ├── assets/
    ├── licenses/
    └── logs/
```

Users do not need to create or move runtime folders manually.

## Adding games

### Single-file games

Put the `.swf` directly in `flash/`:

```text
ROMs/
└── flash/
    └── Fancy Pants.swf
```

EmulationStation will list the SWF as a Flash game.

### Multi-file games

Some Flash games need XML files, extra SWFs, images, sounds or other resources beside the main movie.

Keep the main SWF in `flash/` and place its companion data in `flash_data/<game name>.files/`:

```text
ROMs/
├── flash/
│   └── Garfield.swf
└── flash_data/
    └── Garfield.files/
        ├── data.xml
        ├── images/
        ├── sounds/
        └── other game files
```

The base name must match:

```text
Garfield.swf
Garfield.files/
```

Keeping the companion folder under `flash_data/` prevents EmulationStation from showing asset folders as separate games.

For compatibility with older setups, the launcher can also detect a `<game>.files` directory next to the SWF.

Do not submit copyrighted SWFs or game assets to this repository.

## Controller profiles

Profiles are installed with Ruffle Handheld and live here on the handheld:

```text
Ports/rufflehandheld/profiles/
```

In the repository, the same files are stored at:

```text
port/rufflehandheld/rufflehandheld/profiles/
```

There is only one source copy of each profile.

When a game launches, Ruffle Handheld normalizes the SWF filename, searches for a matching `.profile`, checks its aliases, and falls back to `default.profile` if no dedicated profile exists.

Included profiles currently cover games such as Fancy Pants, Dad 'n Me, Papa's Pizzeria, Henry Stickmin, Super Mario 63, Bad Ice-Cream 3, Garfield and The World's Hardest Game.

### Creating a profile

Copy:

```text
port/rufflehandheld/rufflehandheld/profiles/template.profile
```

Rename the copy to a normalized game name, for example:

```text
alien-hominid.profile
```

A profile uses plain `key=value` entries:

```text
name=Alien Hominid
aliases=alien-hominid|alienhominid
mouse_click=r1
native_a_mode=keyboard

dpad_up=38
dpad_down=40
dpad_left=37
dpad_right=39
south=32
east=90
west=88
north=67
start=13
select=27
left_trigger=16
right_trigger=none
```

Keyboard values use Flash/Windows virtual key codes. Use `none` to disable a mapping.

Physical controller mapping in the bundled frontend:

| Physical control | Profile field |
| --- | --- |
| D-pad | `dpad_up`, `dpad_down`, `dpad_left`, `dpad_right` |
| A | `south` |
| B | `east` |
| X | `west` |
| Y | `north` |
| Start | `start` |
| Select/Back | `select` |
| L1 | `left_trigger` |
| Extra/internal trigger route | `right_trigger` |

`mouse_click` selects the handheld button used as an additional left mouse click when `gptokeyb2` or a compatible helper is available. `r1` is the normal project default.

`native_a_mode` controls how physical A is handled by the frozen console frontend:

- `keyboard` — use A as the profile's keyboard action for keyboard/hybrid games.
- `native` — keep the frontend's native A behavior, useful for mouse-only games.
- `disabled` — do not give A a Ruffle action.

When `native_a_mode=keyboard`, part of the A routing is handled internally by the launcher. Contributors should normally set the intended action with `south=` and leave `right_trigger=none` unless they understand the internal routing.

## Mouse controls

The bundled console frontend provides the mouse cursor behavior used by the project. Additional click mapping can use PortMaster's `gptokeyb2` when it exists on the target system.

A mouse-only game may intentionally keep physical A as the native click. A hybrid game can instead use A as a keyboard action and R1 as click through its profile.

If a device/CFW has different controller behavior, report the exact device and firmware so the profile or platform handling can be adjusted without breaking other handhelds.

## Performance mode

Ruffle Handheld includes conservative runtime optimizations used during gameplay:

- Requests `performance` governors for supported CPU/GPU/memory nodes when the system exposes them.
- Restores the previous governor values when the game exits.
- Uses a symlink for the temporary main SWF when possible instead of copying the whole file.
- Falls back safely when a specific optimization is unavailable.

This is **not overclocking**. No new clocks or voltages are added by the project.

## EmulationStation themes

Ruffle Handheld does not replace or edit the user's theme files.

During setup it checks the active theme:

- If the theme already contains a `flash` system entry, it uses `flash`.
- Otherwise the Flash system uses the theme's `arcade` entry as a fallback.

This keeps Flash visually consistent with the selected EmulationStation theme without shipping a replacement theme.

## Compatibility tracker

The official community compatibility database is **`Compatibility.xlsx`** in the repository root. It tracks game status, performance, controls, input type, device, CFW/OS, architecture, audio, profile information and test notes.

Compatibility and performance are kept separate because a game can open correctly and still run slowly.

Compatibility status:

- `Perfect` — no meaningful issue found during the reported test.
- `Playable` — game can be played with minor issues.
- `Partial` — important functionality is missing or broken.
- `Boots` — reaches some game content but is not considered playable.
- `Doesn't open` — launcher/runtime does not reach the game.
- `Black screen` — runtime opens but game output remains black.
- `Crash` — runtime or game exits unexpectedly.
- `Needs assets` — main SWF opens but required companion files are missing.
- `Untested` — no confirmed community result yet.

Performance is tracked separately as `High`, `Medium`, `Low`, `Unknown` or `N/A`.

Different devices and CFWs can have different results for the same game, so multiple test rows can coexist. Community members normally **do not edit the spreadsheet directly**: submit a **Game compatibility report** from GitHub Issues and a maintainer will review the result and add it to the tracker.

## Contributing

You do not need Git knowledge to help.

Open **Issues → New issue** and choose one of the built-in forms:

### Game compatibility report

Use this after testing a game. The form asks for:

- Game and SWF filename.
- Ruffle Handheld version.
- Device.
- CFW / OS.
- SoC / architecture.
- Compatibility status.
- Performance.
- Controls.
- Audio.
- Notes and logs when relevant.

Submit separate reports when the same game behaves differently on different devices or CFWs.

### Control profile submission

Use this to propose or improve controls. Include:

- Game and SWF filename.
- Device / CFW used for testing.
- Original keyboard/mouse controls.
- Proposed handheld mapping.
- Actions actually verified in-game.

### Runtime bug report

Use this for project-level problems such as setup, launching, cursor behavior, controls, performance regressions, multi-file loading or theme integration.

### Pull Requests

Contributors who prefer Git can edit the same files directly:

```text
Profiles: port/rufflehandheld/rufflehandheld/profiles/
Runtime:  port/rufflehandheld/rufflehandheld/runtime/
```

Keep changes focused. A new game control contribution normally needs only its `.profile`. Compatibility results should normally be submitted through the GitHub compatibility form so the tracker stays consistent. Do not add game SWFs or copyrighted assets.

## Repository layout

```text
Ruffle-Handheld/
├── .github/
│   ├── ISSUE_TEMPLATE/        Community contribution forms
│   └── workflows/             Release automation
├── port/
│   └── rufflehandheld/        Complete installable port source
├── tools/
│   └── build_release.py       Maintainer release packager
├── Compatibility.xlsx        Community compatibility tracker
├── README.md
├── README.es.md
├── LICENSE
├── VERSION
├── .gitattributes
└── .gitignore
```

The installable release contains only:

```text
Ruffle Handheld.sh
rufflehandheld/
```

`.github`, `Compatibility.xlsx`, `tools` and repository metadata are not copied to the handheld.

## Building the offline ZIP

Normal players and contributors do **not** run the build script.

GitHub Actions can build the offline package automatically. Maintainers who want to build it locally can run:

```text
Windows:  py tools\build_release.py
Linux:    python3 tools/build_release.py
macOS:    python3 tools/build_release.py
```

It uses only the Python standard library and generates `releases/rufflehandheld.zip`.

## Troubleshooting

**Flash Games does not appear in EmulationStation**  
Restart EmulationStation after running Ruffle Handheld setup once. If it still does not appear, report the CFW and location of its `es_systems.cfg`.

**A game does not appear**  
Confirm the main game file ends in `.swf` and is inside the created `flash/` folder.

**A multi-file game opens but assets are missing**  
Check that the sidecar folder uses the exact main SWF base name: `Game.swf` + `flash_data/Game.files/`.

**R1 click does not work on a specific CFW**  
Report whether that system provides PortMaster/gptokeyb2 and include the device/CFW. Native A click behavior may still work in mouse-only profiles.

**Black screen or crash**  
Open a Runtime bug report or Game compatibility report and attach the logs from `Ports/rufflehandheld/logs/` when available.

**A controller profile is wrong on one handheld**  
Do not assume the profile is globally wrong. Report the device and CFW because controller mappings can differ between environments.

## Third-party components and legal

Ruffle Handheld is a launcher/integration project. Flash emulation is provided by Ruffle-derived components bundled for the target architecture.

- Ruffle: https://ruffle.rs/
- ruffle4consoles: https://github.com/Hexadecinull/ruffle4consoles
- PortMaster / gptokeyb2: https://github.com/PortsMaster/gptokeyb2

Third-party notices required by the distributed runtime are included inside:

```text
port/rufflehandheld/rufflehandheld/licenses/
```

Ruffle Handheld does not distribute Flash games. Users and contributors are responsible for ensuring they have the right to use any SWFs or external assets they add.
