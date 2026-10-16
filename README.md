# Median XL on macOS (no Windows, no Parallels)

Play [Median XL](https://www.median-xl.com/) — including online on the TSW realm — natively on a Mac
through [CrossOver](https://www.codeweavers.com/crossover). This repository contains an installer, a
launcher and an updater that work around the macOS-specific problems that otherwise make the game crash
or misbehave.

Tested on a MacBook Pro M4 Max, macOS 26.6, CrossOver 26.3, Median XL 2.14.6 (October 2026): a fresh
install with both the official graphics driver and D2GL-MXL reaches the TSW realm. Intel Macs are untested.

## What you need

1. **CrossOver 26 or newer** from <https://www.codeweavers.com/crossover> (paid; the 14-day trial works
   for testing). Install it to `/Applications` and open it once.
2. **The ten original Diablo II + Lord of Destruction data files.** Copy them from any Diablo II: LoD
   installation (an old Windows PC, a CD install, the Blizzard classic download):

   `d2data.mpq` `d2exp.mpq` `d2char.mpq` `d2music.mpq` `d2sfx.mpq` `d2speech.mpq` `d2video.mpq`
   `d2xmusic.mpq` `d2xtalk.mpq` `d2xvideo.mpq` (about 1.6 GB)

   Everything else — the 1.13c game files, Median XL itself and the graphics driver — is downloaded
   from the official Median XL servers by the installer (about 600 MB).
3. About 3 GB of free disk space.

## Install

```sh
git clone https://github.com/davidnum/median-xl-macos.git
cd median-xl-macos
./install.sh "/path/to/your/Diablo II folder"
```

(Or download the repository as a ZIP from GitHub, unpack it, and run `./install.sh` from Terminal in
that folder.)

The installer:

- creates a CrossOver bottle named `MedianXL`;
- copies the ten Diablo II files into it;
- downloads Median XL from the official release manifest (the same one the official launcher uses)
  and verifies every file's SHA-1;
- writes the registry settings the game needs;
- creates **`~/Applications/Median XL.app`**.

Start the game with **Median XL** (Spotlight or `~/Applications`). Your online characters live on the
realm server, so they show up as soon as you log in.

### Optional: D2GL-MXL graphics driver

By default you get the graphics driver that ships with Median XL. If you prefer
[GavinK88's D2GL-MXL 1.0.5](https://github.com/GavinK88/d2gl-mxl-1.0) (a D2GL fork for Median XL; it is
what the author of this guide plays with), add `--d2gl-mxl`:

```sh
./install.sh "/path/to/your/Diablo II folder" --d2gl-mxl   # first install
./install.sh --d2gl-mxl                                     # switch an existing install
```

This downloads the 1.0.5 release from the D2GL-MXL GitHub page, checks its SHA-256 and copies
`glide3x.dll`, `ddraw.dll` and `d2gl.mpq` into the game folder. The updater then leaves these three
files alone. To go back to the official driver, run `./install.sh` again without `--d2gl-mxl`.

You can re-run `./install.sh` at any time (without the Diablo II folder argument once the files are
installed); it only adds or repairs what is missing.

## Updates

Every time you start **Median XL.app**, it compares your files with the official Median XL release
manifest. If a new version is out, you get a macOS notification, the changed files are downloaded and
verified, and then the game starts. Replaced files are kept in `median-xl/.mxl-update-backup` until the
next update. The log is in `~/Library/Application Support/MedianXL-macOS/MedianXL.update.log`.

If the server cannot be reached, the game simply starts with the files you have. If a download breaks
halfway, the game does not start (to avoid a mixed version); start it again to resume.

## Things to know

| Symptom | Cause | What to do |
|---|---|---|
| The game sometimes closes right at start | A race in D2GL's OpenGL setup under CrossOver: about 1 start in 5, `glGenVertexArrays` is not loaded yet | Nothing — the launcher detects this crash and restarts the game automatically |
| The upscale shader resets to `bilinear` | D2GL rewrites `d2gl.ini` on every start and writes `shader_preset=%d` (a number) until the preset loads; a crash in between loses your choice | Nothing — the launcher remembers your last valid preset and puts it back |
| `fsr\...` shader presets don't work | They need GLSL 4.20 (`packHalf2x16`); macOS OpenGL stops at 4.1 | Use any other preset. Presets with fewer passes are faster |
| Changing a shader in the menu does nothing | The dropdown only selects; the preset is compiled when you press **Apply** | Press **Apply** next to the dropdown (D2GL menu: `Ctrl+O`) |
| The game opens in a small window after you plug in / unplug a monitor | Wine keeps the old display layout while the bottle is running | Quit the game and start it again; the launcher restarts the bottle before each start |
| The macOS arrow cursor appears over the game | Wine shows the system cursor whenever the mouse is over anything that is not a game window (menu bar, Dock, a notification); D2GL also releases the mouse on focus loss, `Ctrl+Tab` and in its `Ctrl+O` menu | Nothing for the first part — the bottle captures the display in fullscreen, so nothing else is drawn over the game. If D2GL released the mouse, click in the game once |
| Lower FPS with heavy shaders | Shaders run through Apple's OpenGL → Metal layer | Pick a lighter preset or turn off V-Sync in the D2GL menu |

Keyboard: `Alt+Enter` toggles fullscreen (D2GL-MXL starts windowed by default), `Ctrl+O` opens the D2GL
options.

### Why CrossOver and not free Wine / Whisky / Game Porting Toolkit

- Free upstream Wine 11 builds reach the main menu but crash on *Connect to Battle.net* (a 32↔64-bit
  callback bug in Wine's new WoW64 mode on macOS).
- Game Porting Toolkit's Wine 7.7 asserts on macOS 26 before the menu.
- Whisky is discontinued.

## How it works

The fixes, for anyone who wants to reproduce or improve them:

- **Windows 7 for `Game.exe`.** Diablo II's `Fog.dll` validates every critical section
  (`FogValidateCriticalSection`) and expects `DebugInfo` to be allocated. Wine ≥ 9 only does that when
  the reported Windows version is older than 8, otherwise the game dies with *Unrecoverable internal
  error* and a stack overflow. The bottle is Windows 10, with a per-application override
  (`HKCU\Software\Wine\AppDefaults\Game.exe\Version = win7`).
- **MSync** is enabled in the bottle for lower synchronisation overhead.
- **Display capture for fullscreen.** `HKCU\Software\Wine\AppDefaults\Game.exe\Mac Driver\CaptureDisplaysForFullscreen = y`: while the game is fullscreen, Wine captures the display, so the menu bar, Dock and notifications can't appear over it and the hidden cursor stays hidden. Notifications and the Dock are not shown while you play fullscreen.
- **Launcher** (`launcher.sh`): restarts the bottle's wineserver before each start, runs the updater,
  restores the shader preset, starts `Game.exe -3dfx -skiptobnet` and retries up to six times when the
  known D2GL startup crash (`Fault address: 00000000` in `logs/D2Debug-*.txt`) appears in the first
  seconds.
- **Updater** (`mxl-update.py`): reads `https://launcher.median-xl.com/mxl/release/public/manifest`,
  re-hashes only files whose size or date changed, downloads changed files to a temporary folder,
  checks size and SHA-1, then swaps them in atomically. Run it by hand:
  `/usr/bin/python3 mxl-update.py --game "<game folder>" [--check] [--keep glide3x.dll,ddraw.dll]`.

Files installed:

- `~/Library/Application Support/CrossOver/Bottles/MedianXL/` — the bottle; the game is in
  `drive_c/Games/median-xl`.
- `~/Library/Application Support/MedianXL-macOS/` — `launcher.sh`, `mxl-update.py` and small state
  files.
- `~/Applications/Median XL.app`.

## Uninstall

```sh
./uninstall.sh
```

Deletes the bottle (game files and offline characters), the app and the launcher's state files.
Realm characters are on the server and are not affected.

## Credits

- The [Median XL](https://www.median-xl.com/) team.
- [D2GL](https://github.com/bayaraa/d2gl) by bayaraa and [D2GL-MXL](https://github.com/GavinK88/d2gl-mxl-1.0)
  by GavinK88.
- [CodeWeavers](https://www.codeweavers.com/) for CrossOver and the Wine project.

This project is unofficial and not affiliated with the Median XL team, Blizzard or CodeWeavers. It does
not contain any game files; you need your own copy of Diablo II: Lord of Destruction.

The scripts in this repository are released under the MIT License (see `LICENSE`).
