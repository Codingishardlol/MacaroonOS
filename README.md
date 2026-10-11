# Macaroon OS — v1.2 (desktop + updater + accounts)

Target: **Advanced Computer** (colour + mouse) on CC: Tweaked.
Tested workflow: CraftOS-PC / CC emulator on Windows.

## Layout in this folder

```
Macaroon OS/
  installer.lua   <- hosted, run with `wget run <URL>`
  update.lua      <- on-computer updater (`update` in shell)
  startup.lua     <- auto-boots + boot-time update check
  macaroon/
    version.lua   <- bump this each release (now 1.2.0)
    manifest.lua  <- file list (installer + updater use it)
    updater.lua   <- check/perform API
    sha256.lua    <- pure-Lua SHA256 for password hashes
    settings.lua  <- wallpaper/clock/autoupdate store
    users.lua     <- salted-hash accounts (users.dat)
    login.lua     <- secure-boot login gate
    window.lua
    desktop.lua
    update_url.txt (created on install, not in repo)
    settings.dat, users.dat (created on device, never in repo)
    apps/
      files.lua     <- Start menu -> Files
      terminal.lua  <- Start menu -> Terminal
      settings.lua  <- Start menu -> Settings
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
   - `/macaroon/sha256.lua`
   - `/macaroon/settings.lua`
   - `/macaroon/users.lua`
   - `/macaroon/login.lua`
   - `/macaroon/window.lua`
   - `/macaroon/desktop.lua`
   - `/macaroon/apps/files.lua`
   - `/macaroon/apps/terminal.lua`
   - `/macaroon/apps/settings.lua`
   - `/macaroon/apps/hello.lua`
   - `/macaroon/apps/about.lua`
   - `/macaroon/apps/update.lua`
4. Easiest way in CraftOS-PC: drag-drop files into the computer window, or paste the folder contents into the CraftOS-PC data directory for that computer ID.
5. Reboot the computer (hold Ctrl+R in CraftOS-PC, or `reboot`). `startup.lua` auto-runs.

## Accounts + secure boot

The installer asks you to create an admin account (username + password, min 8 chars). Passwords are stored salted + SHA256-hashed x100 rounds in `macaroon/users.dat` — never plaintext, and `users.dat` is never overwritten by updates. Expect a few seconds of "working" at login on real hardware; tune `ROUNDS` in `users.lua` if needed.

Every boot with accounts present shows the login gate (pick user, masked password, 5 tries, `shutdown` to power off). No accounts = boots straight in, so manual copies still work. Ctrl+T cannot bypass it (terminate is trapped at login and in the desktop); file access still can — anyone who can open the computer's folder can delete `users.dat`, so this stops walk-ups, not owners.

Start menu -> `Lock` reboots back to login. Your name shows in the taskbar and wallpaper.

## Apps (v1.2)

- **Files:** click to select, second click / `[Open]` enters dirs or views text (8KB max), `[Del]` twice deletes, `+Dir` makes folders, `[..]` goes up, scroll works.
- **Terminal:** type + Enter runs via `shell` (try `help`, `list`, `lua`). `clear` wipes scrollback. Output is scraped back into the window.
- **Settings:** cycle wallpaper color, toggle 12/24h clock, toggle auto-update. Saves instantly, desktop applies live.
- **Update / Hello / About:** as before.

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
