# Ruffle Handheld

[Español](README.es.md)

Play Flash games on ARM64 Linux handhelds. Ruffle Handheld adds them to the games menu, supports single-file and multi-file SWF games, and runs without an Internet connection. Games are not included.

**Current version:** 0.8.35. EmuELEC on RK3326 hardware is the most thoroughly tested setup. Other firmware support is still being checked with community reports; see [Compatibility](#compatibility).

## Installation

On firmware supported by PortMaster, download `rufflehandheld.zip`, copy it **without extracting it** to PortMaster's `autoinstall` folder, and open PortMaster. See [PortMaster's folder locations](https://portmaster.games/faq.html) for your firmware. Then run **Ruffle Handheld** from Ports once to set up the Flash library. This local ZIP does not require an online catalogue listing.

For manual installation, download `Ruffle-Handheld-v0.8.35-OFFLINE.zip` and extract it. The ZIP contains `Ruffle Handheld.sh` and the `rufflehandheld` folder.

| System | Where to copy the files |
| --- | --- |
| EmuELEC | `Ruffle Handheld.sh` → `ROMS/ports_scripts/`; `rufflehandheld/` → `ROMS/ports/` |
| ArkOS, dArkOS and other PortMaster systems | Copy both items to the usual Ports location; keep the folder named `rufflehandheld`. |
| muOS | Copy both items to `ROMS/Ports/` on the SD card. |
| Stock Mod OS | Copy both items to `Roms/PORTS/` on the SD card. |
| NextUI | Copy both items to the Ports games folder (usually `Roms/2) Ports (PORTS)/`). Install `PORTS.pak` first. |

Run **Ruffle Handheld** once from the Ports menu. The installer creates the Flash games folder and adds the available games to the menu. It does not download anything. If new entries do not appear immediately, return to the menu or restart the device.

On muOS, Flash games appear as `Flash - Game Name` scripts in Ports because muOS does not use EmulationStation. Add your SWF files and run the installer again to create entries for new games.
Stock Mod OS also adds game entries directly to its Ports menu. Run the installer again after adding SWF files.

To update manually, copy the new files over the existing ones and run **Ruffle Handheld** again. If you installed through PortMaster, put the new `rufflehandheld.zip` in `autoinstall` and open PortMaster again. Your games and profiles in `profiles/custom/` stay in place.

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

On muOS, `flash/` and `flash_data/` are created at the root of the SD card, beside `ROMS/`.

Games that save progress keep it in `flash_data/storage/` on the ROM card. Saves remain there when you close a game or update Ruffle Handheld.

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
| muOS on H700 | Community testing confirms games launch. Some buttons reported in older builds still need investigation. |
| Stock Mod OS on H700 | Creates game scripts in Ports and selects the `mali` video driver. Console testing of this update is pending. |
| ROCKNIX | Reported to reach the game player on Flip; controls and individual games need further testing. |
| NextUI / TrimUI Brick | Installer and game player have run on the device. Cursor movement and games appearing in a quarter of the screen remain under investigation. |
| AmberELEC / Knulli / other ARM64 Linux systems | Installation adapters included; results vary by device and firmware. |

A game may fail because of an unsupported Flash feature or limited memory, even when installation and controls work. Ruffle Handheld includes an ARM64 build of the game player; it does not include Adobe Flash Player.

## Logs and bug reports

If installation fails, check `ports/rufflehandheld/logs/LAST-INSTALL.log`. After launching a game, its log appears in the same folder under a filename based on the SWF, for example `Fancy_Pants.swf.log`. The latest attempt replaces that game's previous log.

When reporting a problem, include the firmware, device model, Ruffle Handheld version, game name, what happened, and the matching log. A photo or short video helps with display and controller issues.

## Licenses

Ruffle Handheld does not include Flash games. Add SWF files that you have the right to use. License notices for the bundled software are in `rufflehandheld/licenses/`; the project license is in `LICENSE`.
