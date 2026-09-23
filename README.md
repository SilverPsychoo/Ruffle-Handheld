# Ruffle Handheld

[Español](README.es.md)

Play Flash games on ARM64 Linux handhelds. Ruffle Handheld adds a Flash section to the games menu, supports single-file and multi-file SWF games, and runs without an Internet connection. Games are not included.

**Current version:** 0.8.33. EmuELEC on RK3326 hardware is the most thoroughly tested setup. Other firmware support is still being checked with community reports; see [Compatibility](#compatibility).

## Installation

Download `Ruffle-Handheld-v0.8.33-OFFLINE.zip` and extract it. The ZIP contains `Ruffle Handheld.sh` and the `rufflehandheld` folder.

| System | Where to copy the files |
| --- | --- |
| EmuELEC | `Ruffle Handheld.sh` → `ROMS/ports_scripts/`; `rufflehandheld/` → `ROMS/ports/` |
| ArkOS, dArkOS and other PortMaster systems | Copy both items to the usual Ports location; keep the folder named `rufflehandheld`. |
| NextUI | Copy both items to the Ports games folder (usually `Roms/2) Ports (PORTS)/`). Install `PORTS.pak` first. |

Run **Ruffle Handheld** once from the Ports menu. The installer creates the Flash games folder and registers it in the menu. It does not download anything. If Flash does not appear immediately, return to the menu or restart the device.

To update, copy the new files over the existing ones and run **Ruffle Handheld** again. Your games and profiles in `profiles/custom/` stay in place.

## Adding games

Copy `.swf` files into the `flash` folder on your ROM card:

```text
ROMS/flash/Fancy Pants.swf
```

For a game with extra files, put them in `flash_data` using the same base name as the SWF:

```text
ROMS/flash/Garfield.swf
ROMS/flash_data/Garfield.files/
```

The extra files go inside `Garfield.files/`. Keep that folder outside `flash/` so the menu shows only the game. Ruffle Handheld accepts `.swf` and `.SWF`; game compatibility varies because not every Flash feature is supported.

## Controls

The default mapping is for games that mix keyboard and mouse controls:

| Button | Default action |
| --- | --- |
| D-pad | Arrow keys |
| A | Space |
| B | Z |
| X | X |
| Y | C |
| R1 | Mouse click |
| Right stick | Mouse cursor, if available |
| Start / Select | Enter / Escape |

Some games have included profiles that change these controls. For mouse-only games such as Bejeweled 2, A is the click button. Ruffle Handheld reads the controller mapping supplied by the firmware, so a game should not need its own profile merely to make R1 click. Start+Select is intended as the exit shortcut where PortMaster provides it; it still needs confirmation on some systems, including dArkOSRE.

To change controls for a game, open `ports/rufflehandheld/profile-maker.html` in a browser on your phone or computer. Enter the SWF filename, assign the buttons, download the `.profile` file and copy it to `ports/rufflehandheld/profiles/custom/`. It works offline. Custom profiles take priority over the included ones and are kept during updates.

## Compatibility

| Firmware | Current status |
| --- | --- |
| EmuELEC | Tested on RK3326 ARM64 hardware. |
| ArkOS / dArkOS | Installation and control support included; reports of launch, click and exit issues still need device testing. |
| ROCKNIX | Reported to reach the game player on Flip; controls and individual games need further testing. |
| NextUI / TrimUI Brick | Installer and game player have run on the device. Cursor movement and games appearing in a quarter of the screen remain under investigation. |
| AmberELEC / Knulli / other ARM64 Linux systems | Installation adapters included; results vary by device and firmware. |

A game may fail because of an unsupported Flash feature or limited memory, even when installation and controls work. Ruffle Handheld includes an ARM64 build of the game player; it does not include Adobe Flash Player.

## Logs and bug reports

If installation fails, check `ports/rufflehandheld/logs/LAST-INSTALL.log`. After launching a game, its log appears in the same folder under a filename based on the SWF, for example `Fancy_Pants.swf.log`. The latest attempt replaces that game's previous log.

When reporting a problem, include the firmware, device model, Ruffle Handheld version, game name, what happened, and the matching log. A photo or short video helps with display and controller issues.

## Licenses

Ruffle Handheld does not include Flash games. Add SWF files that you have the right to use. License notices for the bundled software are in `rufflehandheld/licenses/`; the project license is in `LICENSE`.
