# Macaroon OS — SPEC (as-built v1.7.8)

A Windows-style desktop OS for ComputerCraft: Tweaked.

As-built behavior only. Milestones and release history live in `MILESTONES.md`.

- **Target:** Advanced Computer (colour + mouse), HTTP API enabled.
- **Layout:** repo root == computer root (`/`). `startup.lua` is the boot entry point.
- **Runtime:** CraftOS / CC:Tweaked, Lua 5.1 subset. No `goto`, no `//`, no
  bitwise operators.

## Boot sequence

`startup.lua` runs on every boot:

1. **Colour gate** — `term.isColor()` must be true; otherwise print a failure
   message and do not boot.
2. **Shell bootstrap** — `macaroon/shellboot.lua` best-effort; startup does not
   otherwise have a `shell` table.
3. **Splash** — `macaroon/boot.lua`, about 2 seconds. Hold `R` for recovery:
   `[1]` reinstall via updater (accounts/data kept), `[2]` reboot. Recovery
   deliberately offers no shell.
4. **Login gate** — `macaroon/login.lua` + `macaroon/users.lua`. Skipped only
   when zero accounts exist (fresh copy). Five misses lock the current sitting;
   twenty persistent failures (`macaroon/fails.dat`) force a 30-second wait.
   `Ctrl+T` at every layer falls through to login/shutdown, never a shell.
5. **Update check** — skipped when `macaroon/noautoupdate.txt` exists. Requires
   an explicit `y`; failure or offline never blocks boot.
6. **Desktop** — `macaroon/desktop.lua` + `macaroon/window.lua`: windows,
   taskbar, Start menu, clock. A desktop crash goes to `macaroon/crash.lua`
   (error log + reboot), never a bare shell dump.
7. **Fail-closed** — missing/corrupt `window.lua` or `desktop.lua`, a damaged
   accounts file, or a wiped `users.dat` on a provisioned machine
   (`macaroon/.provisioned`) prints a message and calls `os.shutdown()`. It
   never opens a desktop or shell.

## Accounts

`macaroon/users.lua` stores accounts in `macaroon/users.dat`:

```lua
{ ["name"] = { salt, hash, rounds } }
```

- Parsed with patterns; never `load()`/`dofile()` — a hostile file cannot
  execute.
- Passwords: salted SHA-256 × 100 (`macaroon/sha256.lua`, pure Lua), constant-
  time compare.
- Names: 1–16 chars, `[A-Za-z0-9_%-]`. Passwords: 8–64 chars.
- The last account cannot be removed (Users app enforces this).
- `macaroon/.provisioned` marks a machine that has had accounts; it is written
  on account creation and is never in the manifest.
- `macaroon/fails.dat` records persistent failed attempts for the 30-second
  lockout.

Login screen: user tiles (↑/↓ or click, first selected), masked password pill,
`[ Shutdown ]` button, per-user avatar, and a `Welcome,` spinner on success.

## Desktop and apps

`macaroon/desktop.lua` owns the event loop, window list, taskbar, and Start
menu. `macaroon/window.lua` handles drag, focus, and close. Each app is one file
in `macaroon/apps/` and returns:

```lua
return {
  title = "App",
  width = 30,
  height = 8,
  draw = function(win) ... end,
  onEvent = function(win, event, p1, cx, cy) ... end,
}
```

Apps use only `win.*` inside `draw`/`onEvent`, and must never throw. The window
manager `pcall`s app callbacks, so a bug shows `App error`, not a shell.

Bundled apps:

| App | Behavior |
| --- | --- |
| Files | Browse, open/view text, copy, rename, create, delete (two-step confirm) |
| Terminal | Real shell in a window; restores globals a command tampers with |
| Notepad | Edit/open/save/save-as user files; OS files blocked; unsaved-work close veto |
| Settings | Wallpaper, 12/24h clock, auto-update, channel; applied live |
| Users | Add/remove users, change passwords (last account protected) |
| Store | Download individual apps from the manifest |
| Update | Check for and install updates |
| Hello / About | Samples |

Controls: click focuses, drag the title bar moves, `X` closes, `F1` toggles
Start, `Delete` closes the focused window.

### Notepad

- Plain-text editor for user files. Single `isProtected` gate in front of both
  open and save.
- Paths are canonicalized before the check: `./`, duplicate `/`, and `..`
  segments are resolved; absolute paths and backslashes are rejected.
- Blocked: `startup.lua`, `macaroon` and everything under `macaroon/`.
  Everything else is allowed.
- Header shows the file name and a `*` while dirty.
- `F2` save, `F3` open, `F4` new, `F5` save as; the status bar is also
  clickable.
- Closing with unsaved changes vetoes once and explains; a second attempt
  discards. The same pattern applies to New.

## Install and update

### Installer

`wget run <installer.lua URL>`:

1. Downloads the files listed in `installer.lua`'s `FILES` array.
2. Backs up `startup.lua` to `startup.bak`.
3. Creates the first admin account (or allows skipping).
4. Reboots.

`installer.lua` hardcodes the same list as `macaroon/manifest.lua` because it
cannot fetch the manifest before knowing what to fetch. **The two lists must
stay identical.**

As of v1.7.8 the manifest contains **24 code paths**. Data files
(`users.dat`, `settings.dat`, `update_url.txt`, `.provisioned`, `fails.dat`)
are never in either list, so installs and updates keep accounts and settings.

### Updater

`macaroon/updater.lua` reads `macaroon/manifest.lua` and compares
`macaroon/version.lua` against the remote version.

Triggers:

- reboot prompt (explicit `y` required)
- Update app: `[ Check ]` → `[ Install ]`
- `update` shell command

Guarantees:

- HTTPS only
- manifest path allowlist (no traversal, no data-file overwrite)
- 256KB per-file cap
- staged install
- accounts/settings/source untouched
- offline never blocks boot
- failure is surfaced, never silent

### Release channels

`macaroon/channel.lua` stores the selected channel:

- **stable** → `main`
- **beta** → `beta`

Set from the installer, Update app, or Settings. `Updater.switchChannel()`
reinstalls the selected branch even when its version is lower, and keeps the
Notepad registration in sync with the deployed branch.

## Screen

- 51×19 characters (CraftOS terminal).
- Colour names from `colours.*` only.
- UI changes require a real screenshot under CraftOS-PC before declaring them
  done.

## Security invariants

Full detail: `THREAT_MODEL.md`.

- Boot never falls through to a shell on a tamper/failure path.
- Login caps attempts, swallows `Ctrl+T`, and never calls `os.shutdown()` itself
  (the caller decides).
- `users.dat` is pattern-parsed, never executed.
- Notepad canonicalizes paths before the single open/save gate.
- Terminal restores globals a command tampers with.
- Updater/installer `FILES` == `manifest.lua`; data files are never listed.

## Test coverage

The behavioral suite is `tests/test.sh` (see `tests/AGENTS.md`).

| Test | Covers |
| --- | --- |
| T0a / T0b | `luac -p` syntax / Lua 5.1 subset gate |
| T1a / T1b | Boot to desktop with no accounts / boot to login with accounts |
| T2a / T2b / T2c | Correct login / wrong password stays locked / failure recorded |
| T3 | Recovery menu has no shell; reboot preserves `users.dat` |
| T4a–d | Deleting `desktop.lua`, `window.lua`, `login.lua`, or `users.dat` fails closed |
| T5 | Fresh-install first account |
| T6 | Upgrade from 1.7.3 boots and adopts the marker |
| T7 | Marker deleted but `users.dat` present boots normally |
| T8 | Channel get/set/branch logic |
| T9 | Installer picks beta |
| T10 | Updater pulls the chosen branch |
| T11 | Switching back to stable reinstalls even at a lower version |
| T12 | No channel file means stable |
| T13 | Notepad registered locally; manifest == installer `FILES` |
| T14 | Notepad edits/saves user files, refuses OS files through canonicalized paths, multi-line open, F-keys, close veto |
| T15 | Channel switch restores Notepad registration; current stable keeps it (post-push beta) |
| T16 | Switch with no channel lib (≤1.7.4 update path) succeeds and heals it |
