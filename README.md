# Macaroon OS — v1.1 (LevelOS-style desktop + updater)

Target: **Advanced Computer** (colour + mouse) on CC: Tweaked.
Tested workflow: CraftOS-PC / CC emulator on Windows.

## Layout in this folder

```
Macaroon OS/
  installer.lua   <- hosted, run with `wget run <URL>`
  update.lua      <- on-computer updater (`update` in shell)
  startup.lua     <- auto-boots + boot-time update check
  macaroon/
    version.lua   <- bump this each release (now 1.1.0)
    manifest.lua  <- file list (installer + updater use it)
    updater.lua   <- check/perform API
    window.lua
    desktop.lua
    update_url.txt (created on install, not in repo)
    apps/
      hello.lua
      about.lua
      update.lua  <- Start menu -> Update GUI
```

## Install like LevelOS (auto-boot)

1. Push the **contents** of this folder to `https://github.com/Codingishardlol/MacaroonOS` repo root (not the `Macaroon OS` folder itself, to avoid `%20` in URLs).
2. `installer.lua` and `macaroon/updater.lua` already point to `https://raw.githubusercontent.com/Codingishardlol/MacaroonOS/main`.
3. Copy `installer.lua` to a pastebin, gist, or just use the raw GitHub URL directly.
4. On an **Advanced Computer** in Minecraft / CraftOS-PC, run:
   ```
   wget run https://raw.githubusercontent.com/Codingishardlol/MacaroonOS/main/installer.lua
   ```
   Or if you used pastebin:
   ```
   pastebin run XXXXXXXX
   ```
5. The installer downloads everything to `/`, backs up old `/startup.lua` to `/startup.bak` (once), and reboots.
6. Auto-boot: CraftOS always runs `/startup.lua` on boot/reboot. Since our installer places Macaroon `startup.lua` there, Macaroon OS opens automatically every time. To go back to plain CraftOS, delete/rename `/startup.lua` (`startup.bak` is your backup).

To update later, just re-run the same `wget run ...` command.

## Updating (no reinstall)

You never need to delete everything. Bump `macaroon/version.lua` in the repo for each release, then on the computer use any of:

1. **Boot check (easiest for testing):** reboot — if remote version > local, you see:
   ```
   Update available: 1.1.0 -> 1.2.0
   Update now? [Y/n]
   ```
   Say yes, it downloads via `macaroon/manifest.lua` and reboots. Offline/check-fail never blocks boot.
   Disable with an empty file at `macaroon/noautoupdate.txt`.
2. **Desktop:** Start menu -> `Update` -> `[ Check ]` -> `[ Install ]` -> reboot.
3. **Shell:** press `Ctrl+T` to exit desktop, then run `update`.

The installer saves the repo URL to `macaroon/update_url.txt`, so later checks know where to fetch. Remote manifest is preferred, so newly added files update automatically.

## Install to CraftOS-PC (Windows, manual)

1. Open CraftOS-PC.
2. Create / open an **Advanced Computer**.
3. Copy the **contents** of this folder (except `README.md`) to the computer root, so the computer has:
   - `/installer.lua` (optional, for re-installs)
   - `/update.lua` (`update` command)
   - `/startup.lua`
   - `/macaroon/version.lua`
   - `/macaroon/manifest.lua`
   - `/macaroon/updater.lua`
   - `/macaroon/window.lua`
   - `/macaroon/desktop.lua`
   - `/macaroon/apps/hello.lua`
   - `/macaroon/apps/about.lua`
   - `/macaroon/apps/update.lua`
4. Easiest way in CraftOS-PC: drag-drop files into the computer window, or paste the folder contents into the CraftOS-PC data directory for that computer ID.
5. Reboot the computer (hold Ctrl+R in CraftOS-PC, or `reboot`). `startup.lua` auto-runs.

## Controls (v1)

- Left-click: focus window, click buttons
- Drag title bar: move window
- `X` (top-right of window): close window
- Bottom-left `Macaroon` button: open Start menu
- Start menu: launch apps, `Shutdown`
- Clock updates every second (bottom-right)

## Writing a new app

Create `macaroon/apps/myapp.lua` returning a table:

```lua
return {
  title = "My App",
  width = 30,
  height = 8,
  draw = function(win)
    win.setCursorPos(2, 2)
    win.write("Hi!")
  end,
  onEvent = function(win, event, ...)
    -- optional, coords are already window-content-local
    -- return true if you handled a click and want a redraw
  end
}
```

Then register it in `startup.lua` in the `apps` list:

```lua
{ name = "My App", path = "macaroon/apps/myapp.lua" }
```

App contract:
- `draw(win)` — `win` is a `window` object sized `width x (height-1)` (title bar excluded). Only use `win.*`, not global `term`.
- `onEvent(win, event, p1, p2, p3)` — `event` is e.g. `mouse_click` with local content coords. Return `true` to request redraw.
