# Macaroon OS — SPEC (as-built, v1.7.3)

Windows-style desktop OS for ComputerCraft: Tweaked (Advanced Computer:
colour + mouse, HTTP API enabled). Repo root == computer root (`/`).

## Boot sequence (`startup.lua`, auto-run on boot)

1. Require colour (`term.isColor`) — otherwise fail message, no boot.
2. `shellboot.lua` best-effort (startup has no `shell` table otherwise).
3. Splash (`boot.lua`): ~2s animation. `R` during splash → recovery menu
   (`[1]` reinstall via updater, accounts/data kept; `[2]` reboot).
   Deliberately no shell in recovery.
4. Login gate (`login.lua` + `users.lua`) — skipped only when zero
   accounts exist (fresh copy boots straight in). 5 misses in one sitting
   locks that sitting; 20 persistent fails (`fails.dat`) earn a 30s wait.
   `Ctrl+T` (terminate) at every layer falls through to login/shutdown,
   never to a shell.
5. Update check (skipped if `macaroon/noautoupdate.txt`): explicit `y`
   required, never blocks boot on failure/offline.
6. Desktop (`desktop.lua` + `window.lua`): windows, taskbar, Start menu,
   clock. Any desktop crash → `crash.lua` screen (error log + reboot),
   never a bare shell dump.
7. Fail-closed: missing/corrupt `window.lua`/`desktop.lua`, a damaged
   accounts file, or a wiped `users.dat` on a provisioned machine
   (`macaroon/.provisioned`, written by `Users.create`) all print a
   message and `os.shutdown()` — never a shell, never an open desktop.

## Accounts (`macaroon/users.lua`)

- `users.dat`: `{ ["name"] = { salt, hash, rounds } }`, parsed with
  patterns, never `load()`/`dofile` (hostile file can't execute).
- Passwords: salted SHA-256 × 100 (`sha256.lua`, pure Lua, no bit ops),
  constant-time compare, names `1-16` chars `[A-Za-z0-9_%-]`, passwords
  8–64 chars. Last account cannot be removed (Users app enforces).
- Login screen: user tiles (↑/↓ or click, first pre-selected), masked
  password pill, `[ Shutdown ]` button, per-user avatar, `Welcome,`
  spinner on success.

## Apps (`macaroon/apps/`, one file per Start-menu app)

Contract: return `{ title, width, height, draw(win), onEvent }`, use only
`win.*`, never throw out of `draw`/`onEvent`. Bundled: Files, Terminal
(real shell in a window; restores globals a command tampers with),
Settings (wallpaper, 12/24h clock, auto-update; live), Users, Store
(manifest downloads), Update, Hello, About. Controls: click focuses,
drag title bar moves, `X` closes, `F1` Start, `Delete` closes focused.

## Install / update

- Install: `wget run <installer.lua URL>` → downloads `FILES` (22 code
  files, identical to `manifest.lua`), backs up `startup.lua` to
  `startup.bak`, creates admin account, reboots. Data files (`users.dat`,
  `settings.dat`, `update_url.txt`, `.provisioned`, `fails.dat`) are
  never in the manifest.
- Update: reboot prompt, Update app, or `update` command. HTTPS-only,
  path-allowlisted, 256KB/file cap, staged; accounts/settings/source
  untouched; never fails silently, never blocks boot offline.

## Screen

51×19 chars (CraftOS terminal). Palette: named `colours.*` only.

## Milestones (all implemented in v1.7.3; test.sh guards them)

- M1 boot + splash + recovery (no-shell) — `test.sh` T3.
- M2 accounts + login gate (incl. wrong-password lockout) — T1b, T2a/b/c.
- M3 desktop + window manager + taskbar — T1a, T2b.
- M4 core apps + Terminal + Users + Store — manual (no automated coverage yet).
- M5 installer + manifest updater — manual.
- M6 fail-closed boot (missing/damaged files → shutdown) — T4a/b/c/d.
- M7 release channels (installer S/b prompt, `Updater.switchChannel`,
  Update/Settings channel options; stable=main, beta=beta) — T8–T12.
- M8 Notepad app (beta): New/Open/Save/Save-As, filename + `*` header,
  close-veto on unsaved work, arrow/scroll editing, OS files blocked —
  T13–T15.
