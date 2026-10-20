# macaroon/ — OS code guide

Read the root `AGENTS.md` first. This file applies when editing anything under
`macaroon/`.

## Layout

| Path | Responsibility |
| --- | --- |
| `boot.lua` | Splash, spinner, recovery entry |
| `login.lua` | Login gate and attempt handling |
| `users.lua` | Account store, hashing, lockout counters |
| `sha256.lua` | Pure-Lua SHA-256 (Lua 5.1 subset) |
| `shellboot.lua` | Bootstraps a shell table before startup needs it |
| `desktop.lua` | Event loop, windows, taskbar, Start menu |
| `window.lua` | Window manager: drag, focus, close, event forwarding |
| `crash.lua` | Crash screen + reboot |
| `settings.lua` | `settings.dat` (wallpaper, clock, auto-update, channel) |
| `updater.lua` | Version check, manifest downloads, staged install, channel switch |
| `manifest.lua` | Updater's file list (source of truth) |
| `version.lua` | Release version |
| `channel.lua` | stable/beta channel state |
| `apps/*.lua` | One file per Start-menu app |

Repo root == computer root. A path like `macaroon/users.dat` is the same path
the OS sees at runtime.

## App contract

Every app returns a table:

```lua
return {
  title = "My App",
  width = 30,
  height = 8,
  draw = function(win)
    win.setCursorPos(2, 2)
    win.write("Hi!")
  end,
  onEvent = function(win, event, p1, cx, cy)
    -- return true to request a redraw
    return false
  end,
  canClose = function()
    -- optional: return false to veto a close, with an explanation in the UI
    return true
  end,
}
```

Rules:

- `draw` and `onEvent` receive the content window; use only `win.*`.
- Never throw. The window manager `pcall`s callbacks, but an error shows
  `App error` and loses the app state.
- Mouse coordinates are window-content-local. `onEvent` receives
  `(win, event, p1, cx, cy)` for mouse events.
- `canClose` is optional. If it returns false, the desktop keeps the window
  open and the app should explain why on its next draw.
- Apps are loaded with `dofile`, so file-scope upvalues are per window.

## Adding an app

1. Create `macaroon/apps/myapp.lua` following the contract above.
2. Register it in `startup.lua`.
3. Add its path to `macaroon/manifest.lua` and `installer.lua`'s `FILES`.
   The two lists must stay identical.
4. Bump `macaroon/version.lua` and the README badge together.
5. Run the syntax gates and the relevant behavioral test.

## Lua / ComputerCraft constraints

- Lua 5.1 subset only: no `goto`, no `//`, no bitwise operators
  (`& | ~ << >>`).
- Colours use `colours.*` names only.
- Wrap every `http.get` in `pcall`.
- Prefer `pcall` around filesystem operations that can fail.
- No `load()`/`dofile()` on data files. Parse data with patterns.
- Keep the UI within 51×19 characters.
- `term.isColor()` is a boot requirement.

## Code vs data

The manifest has **24 code paths** as of v1.7.8. `installer.lua` duplicates the
same list as bootstrap. Never add data files to either list; the canonical list
of protected data files is in `THREAT_MODEL.md` § Updates.

`macaroon/manifest.lua` is the updater's source of truth. Any change to the
code list must be made in both files in the same commit.

## Security-sensitive code

Do not keep a second copy of the invariants here. Before editing one of these
files, read the matching section of `THREAT_MODEL.md`:

| File(s) | Read first |
| --- | --- |
| `login.lua`, `users.lua` | Login, Accounts, Brute-forcer |
| `apps/notepad.lua`, `apps/terminal.lua` | Notepad, Terminal |
| `updater.lua`, `manifest.lua`, `channel.lua`, `installer.lua` | Updates |
| `startup.lua`, `shellboot.lua`, `boot.lua`, `crash.lua` | Boot |
| `desktop.lua`, `window.lua` | Boot, Review checklist |

If this file and `THREAT_MODEL.md` disagree, `THREAT_MODEL.md` wins.

## UI conventions

- Screen: 51×19 characters.
- Palette: named `colours.*` values from `SPEC.md`.
- After any visual change, run CraftOS-PC under `xvfb-run`, take a screenshot,
  and inspect it for clipped text, overlaps, unreadable colours, and elements
  outside their box.
- Save proof screenshots in `screenshots/`.
