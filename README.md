# Macaroon OS

A Windows-style desktop OS for [ComputerCraft: Tweaked](https://www.tweaked.cc/) — draggable windows, a Start menu, user accounts, and one-command installs and updates.

![version](https://img.shields.io/badge/version-1.5.2-blue)

## Features

- 🖥️ Desktop with draggable, focusable windows and a taskbar clock
- 🚀 One-command install (`wget run ...`) with auto-boot on every reboot
- 🔄 Self-updater: boot-time check, Update app, or `update` command — never a reinstall
- 🔐 User accounts with salted, stretched password hashes + login gate
- 💀 Graceful crash screen with error log and auto-reboot
- 📁 Built-in apps: Files, Terminal, Settings, Users, Store

## Requirements

- An **Advanced Computer** (colour + mouse support)
- ComputerCraft: Tweaked with the HTTP API enabled

## Install

On the computer, run:

```
wget run https://raw.githubusercontent.com/Codingishardlol/MacaroonOS/main/installer.lua
```

The installer downloads everything to `/`, backs up your old `startup.lua` to `startup.bak`, asks you to create an admin account, then reboots into Macaroon OS. Because CraftOS runs `/startup.lua` on every boot, the OS opens automatically from then on.

> Prefer pastebin? Upload `installer.lua` there and use `pastebin run <code>` instead.

## Updating

Bump-free updates — pick any one:

1. **Reboot** and answer `Update 1.3.0 -> 1.4.0? [Y/n]` when prompted.
2. **Start → Update** → `[ Check ]` → `[ Install ]`, then reboot.
3. Open a shell (`Ctrl+T` exits the desktop) and run `update`.

The updater only replaces code files. Your accounts (`users.dat`), settings, and update source are never touched. Updates never fail silently or block boot when offline.

## Apps

| App | What it does |
| --- | ------------ |
| Files | Browse, open/view text, copy, rename, create, delete (two-step confirm) |
| Terminal | Real shell inside a window (`help`, `list`, `lua`…) |
| Settings | Wallpaper colour, 12/24h clock, auto-update toggle — applied live |
| Users | Add/remove users, change passwords (last account is protected) |
| Store | Download individual apps from the repo manifest |
| Update | Check for and install OS updates |
| Hello / About | Samples |

Controls: left-click focuses, drag the title bar to move, `X` closes, `F1` toggles Start, `Delete` closes the focused window.

## Accounts & security

Passwords are stored salted and hashed (SHA-256 × 100 rounds) in `macaroon/users.dat` — never plaintext. With accounts present, every boot stops at a Windows-style login screen: click a user tile (or ↑/↓), type the masked password, Enter. Five misses shuts the machine down, `Shutdown` sits bottom-right, and a Welcome spinner hands off to the desktop. No accounts = boots straight in. `Ctrl+T` is swallowed at every layer (splash, login, desktop), and Start → Lock returns to login.

Honest limits: anyone who can open the computer's files (world save, CraftOS-PC data folder) can delete the gate — like every ComputerCraft OS, this stops walk-ups, not owners.

## Uninstall

Terminate to shell (`Ctrl+T`) and delete the OS files:

```
rm startup.lua
rm macaroon
```

Reboot to land back in plain CraftOS. Your pre-install backup is in `startup.bak`.

## Development

Repo layout (this is also the on-computer layout — repo root == computer root):

```
startup.lua          auto-boot: splash → update check → login → desktop
installer.lua        one-command installer + admin account creation
update.lua           `update` shell command
macaroon/
  boot.lua           splash screen + spinner
  desktop.lua        event loop, windows, taskbar, Start menu
  window.lua         window manager (drag, focus, close)
  login.lua          login gate
  users.lua          accounts (salted SHA-256 x100)
  sha256.lua         pure-Lua SHA-256 (no bit ops needed)
  settings.lua       wallpaper / clock / auto-update store
  updater.lua        version check + manifest-driven downloads
  manifest.lua       the file list installers and updaters use
  version.lua        bump per release (releases are detected from this)
  apps/              one file per Start-menu app
```

**Adding an app:** create `macaroon/apps/myapp.lua` returning `{ title, width, height, draw(win), onEvent }`, register `{ name = "My App", path = "macaroon/apps/myapp.lua" }` in `startup.lua`, and add the path to `manifest.lua` + `installer.lua`'s `FILES` (keep the two lists identical).

App contract:

```lua
return {
  title = "My App", width = 30, height = 8,
  draw = function(win)        -- use ONLY win.*, title bar excluded
    win.setCursorPos(2, 2)
    win.write("Hi!")
  end,
  onEvent = function(win, event, p1, cx, cy)
    -- mouse coords are window-content-local; key/char for focused window
    return true               -- true = request redraw
  end
}
```

Rules that keep it working on real hardware: Lua 5.1 subset (no `goto`, `//`, or bitwise ops), colours only via `colours.*` names, wrap every `http.get` in `pcall`, and never throw out of `draw`/`onEvent`.

**Releasing:** bump `version.lua`, push to `main` — computers pick it up on next check. Test with `luac -p` on every Lua file before pushing.
