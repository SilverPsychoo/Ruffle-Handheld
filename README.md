# Ruffle Handheld

[Leer en Español](README.es.md)

Ruffle Handheld integrates Flash games on ARM64 Linux handhelds without Internet access. Version 0.8.21 keeps the proven v0.7.7 ARM64 binaries, cursor shim and performance helper byte-for-byte. It adds six community profiles and a visual control-profile editor fully available in English and Spanish.

> **Status:** community preview. Tested hardware: **RK3326 / aarch64**. Tested CFW: **EmuELEC**. ArkOS, ROCKNIX, AmberELEC, muOS and Knulli are detected so setup can select a conservative adapter, but they are not yet claimed as verified support.

## Offline installation

Like a standard PortMaster port, the ZIP contains exactly one launcher and one folder:

```text
Ruffle Handheld.sh
rufflehandheld/
```

On **EmuELEC**, place that same launcher at `ROMS/ports_scripts/Ruffle Handheld.sh` and the folder at `ROMS/ports/rufflehandheld/`. On ArkOS and other CFWs, install the same two items with PortMaster or in that system's normal Ports location. There is no separate `.sh` edition for each CFW.

When executed, the single launcher detects the ROM root and validates the application under `ports/rufflehandheld/` using sentinel files. It does not assume the folder is beside the `.sh`, so EmuELEC can start it from `ports_scripts/`.

Nothing is downloaded. Native, Native Multifile, the cursor shim, profiles, scripts and theme artwork are bundled.

## Final layout

A clean installation looks like this:

```text
ROMS/
├── flash/                         Only .swf games
├── flash_data/                    Multi-file assets
├── ports_scripts/
│   └── Ruffle Handheld.sh
└── ports/
    └── rufflehandheld/
        ├── runtime/               Core and path adapters
        ├── profiles/
        │   └── custom/            User mappings preserved across updates
        ├── profile-maker.html     Visual offline profile maker
        ├── logs/                  One file per launched game
        ├── theme/                 Chef and Adobe Flash logo
        ├── licenses/
        ├── setup.sh
        └── core-install.sh
```

No `flash_runtime/`, `flash_profiles/` or `ports/ruffle_r36s/` directories are created at the ROM root. EmuELEC runs the adapter installed directly under `ports/rufflehandheld/runtime/`. To keep the v0.7.7 core unchanged, the entrypoint creates a compatibility view under `/tmp` for each game and removes it afterward.

## Games

Normal games go directly in `flash/`:

```text
flash/Fancy Pants.swf
flash/dadnme.swf
```

For multi-file games, the base names must match:

```text
flash/Garfield.swf
flash_data/Garfield.files/
```

EmulationStation scans only `flash/` and only `.swf .SWF`. `flash_data/` is outside the system path, so asset folders are not displayed as extra games.

During an update, an old `flash/Garfield.files/` folder is moved to `flash_data/Garfield.files/`. If the destination already exists, data is merged and the original is preserved under `rufflehandheld/migrated/` before it is removed from the visible game list.

## Controller profiles

All profiles live under:

```text
ports/rufflehandheld/profiles/
```

Profiles for Fancy Pants, Dad 'n Me, Papa's Pizzeria, Henry Stickmin, Super Mario 63, Bad Ice-Cream 3, Garfield, The World's Hardest Game, Bejeweled 2, We Dancing Online, Ultimate Flash Sonic, Final Fantasy Sonic X5, Minecraft Tower Defense and Super Smash Flash 2 are included. Mouse-only games use A as click through `gptokeyb2`; hybrid games reserve R1 for cursor clicks.

The new profiles use these main handheld controls:

| Game | Handheld controls |
| --- | --- |
| Bejeweled 2 | Right stick = cursor; A = click |
| We Dancing Online | D-pad = arrows; B = Space; X = X; Y = C; Start = Enter; Select = Escape; L1 = Shift; R1 = click |
| Ultimate Flash Sonic | D-pad = arrows; A = jump/Spin Dash; Start = pause; R1 = menu click |
| Final Fantasy Sonic X5 | Right stick = cursor; A = select |
| Minecraft Tower Defense | Right stick = cursor; A = dig, build and select |
| Super Smash Flash 2 | D-pad = WASD; A = attack; B = special; X = grab; Y = shield; Start = start; Select = pause; L1 = taunt; R1 = menu click |

### Visual remapping

The source tree also includes `tools/profile-maker.html`, a bilingual offline control editor for creating or editing `.profile` files from a normal PC or phone browser. The release keeps the same editor at `ports/rufflehandheld/profile-maker.html`, so users do not need Python or any online service to remap controls.

Users do not need to learn numeric keyboard codes or edit `config.ron`:

1. Open `ports/rufflehandheld/profile-maker.html` in any PC or phone browser. It works offline and its entire interface can switch between English and Español.
2. Enter the exact `.swf` filename and choose an action for each button.
3. Download the `.profile` and copy it into `ports/rufflehandheld/profiles/custom/`.
4. Launch the game normally; setup does not need to be run again.

The editor can also load an existing `.profile` for changes. Files under `profiles/custom/` take priority over bundled profiles and setup never deletes that folder. A button selected for mouse click is prevented from sending a keyboard key at the same time, avoiding duplicate actions.

Updates automatically migrate `flash_profiles/*.profile` into the new directory. A user-modified legacy profile wins, while the bundled profile it replaces is backed up under `rufflehandheld/migrated/`.

## CFW and frontend adapters

| Detected CFW | Flash registration | Automatic reload | Status |
| --- | --- | --- | --- |
| EmuELEC | Main configs and `es_systems_flash.cfg` in `.config` and `.emulationstation` | Verified `emustation.service` restart | Verified |
| ArkOS | Existing writable `es_systems.cfg` only | Manual | Unverified |
| ROCKNIX / AmberELEC | Existing config under `/storage` only | Manual | Unverified |
| Knulli / Batocera | `es_systems_rufflehandheld.cfg` overlay | Manual | Unverified |
| muOS | Detected without pretending it uses EmulationStation | Unavailable | Adapter pending |
| Other ARM64 Linux | Existing writable config discovery | Manual | Unverified |

When PortMaster exists, its `control.txt` stays authoritative. Without PortMaster, the bundled offline adapter is used. An unknown CFW without a safe adapter gets a clear error instead of a blind write or false success.

On EmuELEC, the registered system is equivalent to this (ArkOS/Knulli adapters use their frontends' `%ROM%` token):

```xml
<system>
  <name>flash</name>
  <fullname>Adobe Flash Player</fullname>
  <path>DETECTED_ROM_ROOT/flash</path>
  <extension>.swf .SWF</extension>
  <command>/bin/bash DETECTED_ROM_ROOT/ports/rufflehandheld/runtime/es-launch.sh "%ROM_RAW%"</command>
  <platform>flash</platform>
  <theme>flash</theme>
</system>
```

On EmuELEC, setup synchronizes both main configurations and both `es_systems_flash.cfg` drop-ins because the frontend may prioritize the latter. Re-running setup replaces only the previous Flash entry. Other systems are preserved and Flash is not duplicated.

## EmulationStation theme

Bundled artwork:

- `theme/system.png`: full Adobe Flash Player logo.
- `theme/background_icon.png`: transparent chef background.

If the active theme already has `flash/theme.xml`, it is kept completely unchanged. Otherwise, if a writable `arcade/theme.xml` layout is available, setup creates only the missing `flash/` section and copies its layout, logo and chef. Existing Flash files are never overwritten. If the theme cannot be extended safely, the Arcade theme tag is used as a fallback.

## Frozen known-good runtime

Release building checks SHA-256 and stops if any frozen v0.7.7 component changes accidentally:

- ARM64 Native and Native Multifile binaries;
- cursor shim and `LD_PRELOAD` behavior;
- performance helper;
- logo and chef artwork.

The binaries were not updated. Launchers, profiles and profile resolution are intentionally versioned in v0.8.21; bundled profiles contain no `native_a_mode`, old configurations are converted compatibly, and `profiles/custom/` keeps priority. Their hashes are pinned by the release build.

## Logs

Each game creates only its own file:

```text
ports/rufflehandheld/logs/Fancy_Pants.swf.log
ports/rufflehandheld/logs/Garfield.swf.log
```

The file is overwritten when the same game is launched again, so repeated attempts do not create a growing log collection. It contains the received path, profile, backend, Native or Multifile output, memory data and any exit-137 diagnostics. Auxiliary logs from previous releases are removed automatically during an update.

## Compatibility and contributions

`Compatibility.xlsx` is the project's maintained compatibility table. `.github/ISSUE_TEMPLATE/` contains forms for:

- Game compatibility report
- Control profile submission
- Runtime bug report

## Building a Release

Normal users do not need Python. Maintainers and GitHub Actions can run:

```bash
python3 tools/build_release.py
```

The result is `releases/Ruffle-Handheld-vX.X.X-OFFLINE.zip` and contains only `Ruffle Handheld.sh` and `rufflehandheld/`, following the standard port format.

## Automated-test boundary

Tests on a non-ARM host validate clean install, update, XML, duplicates, spaces, permissions, LF, hashes, profiles, theme integration and Simple/Multi-file flow up to binary execution. The ARM64 binary is not claimed as executed on x86_64; rendering, audio, cursor, physical controls and the real frontend reload still require an EmuELEC/RK3326 console test.

## Legal

Ruffle Handheld does not include Flash games or the Adobe Flash Player executable. Users provide legally obtained SWFs. Runtime and integration licenses are under `rufflehandheld/licenses/` and in `LICENSE`.
