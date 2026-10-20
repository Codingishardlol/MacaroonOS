# Macaroon OS — THREAT MODEL

Read this before touching login, user files, boot code, updates, or Notepad.

## Scope

This model covers a walk-up attacker at the keyboard of a ComputerCraft
computer running Macaroon OS. It does not defend against someone with access
to the world save or the CraftOS-PC data directory — that person can delete the
gate, like on every ComputerCraft OS.

## Assets

| Asset | Why it matters |
| --- | --- |
| `macaroon/users.dat` | Salted/stretched password hashes. Not plaintext, but offline-crackable if copied. |
| The logged-in session | Full computer access once past login. |
| `macaroon/settings.dat` | Wallpaper/clock/update settings; integrity only. |
| Update source + manifest | A malicious source or manifest means code execution on update. |
| `macaroon/.provisioned` | Marks a machine that has had accounts; deleting it alongside `users.dat` is the known fail-open limit. |

## Attackers

### 1. Walk-up attacker (keyboard only)

Primary adversary. Must never reach a shell or desktop without a password.

Mitigations:

- fail-closed boot paths
- login gate with attempt caps
- `Ctrl+T` swallowed at every layer
- recovery menu offers reinstall only, no shell
- Terminal restores globals a command tampers with

### 2. File tamperer

Can delete or corrupt files (another OS, world edit) but wants the machine to
boot open.

Mitigations:

- missing `window.lua`/`desktop.lua` shuts down
- damaged `users.dat` shuts down
- wiped `users.dat` on a provisioned machine shuts down
- `.provisioned` and `users.dat` are never in the updater manifest
- updater path allowlist blocks data-file overwrites

Known accepted limit: deleting `.provisioned` **and** `users.dat` together makes
the machine indistinguishable from a fresh copy and boots open. Each deletion
alone shuts down. This is documented, not fixed.

### 3. Network attacker

Controls or tampers with the update source.

Mitigations:

- HTTPS only
- manifest path allowlist (no `..`, no data-file overwrites)
- 256KB per-file cap
- staged install
- explicit user consent
- offline never blocks boot

### 4. Brute-forcer

Mitigations:

- five misses per sitting locks that sitting
- twenty persistent failures (`fails.dat`, survives reboot) force a 30s wait
- passwords salted + stretched (100× SHA-256), constant-time compare
- password buffer capped at 64 characters

## Invariants

These are the rules a security change must preserve.

### Boot

- Every `fail()`/tamper branch ends in `os.shutdown()`. It never returns to a
  shell or opens a desktop.
- `R` recovery is reinstall-only. It must never expose a shell; deleting
  `users.dat` from recovery would defeat the gate.
- A desktop crash goes to `crash.lua`, not a bare shell.

### Login

- `Ctrl+T` (terminate) must not escape to a shell.
- Login attempts are capped; no `os.shutdown()` inside `login.lua` — the caller
  decides via `"shutdown"`/`"locked"` reasons.
- Password buffer is capped at 64; failed attempts are recorded.
- A present-but-unreadable `users.dat` shuts down instead of booting open.

### Accounts

- `users.dat` is pattern-parsed. Never `load()` or `dofile()` it.
- Clamp stored rounds (1–1000) and file size (16KB).
- `.provisioned` is written on account creation and never appears in the
  manifest.

### Notepad

- There is one `isProtected` gate in front of **both** open and save.
- Paths are canonicalized before the check:
  - resolve `.` and `..`
  - collapse duplicate `/`
  - reject absolute paths
  - reject backslashes
  - compare case-insensitively
- Blocked: `startup.lua`, `macaroon`, and everything under `macaroon/`.
- Everything else is a user file. File access uses `fs` only, inside `pcall`.
- Notepad edits text; it never loads or executes a file.
- Required T14 cases: `./startup.lua`, `./macaroon/evil.lua`,
  `MACAROON/...`, and `a/../macaroon/...` must all be refused.

### Terminal

- Restore any globals a command tampers with.
- Do not add an exit-to-shell shortcut that bypasses the login gate.

### Updates

- Updater and installer file lists must match `manifest.lua`.
- Data files (`users.dat`, `settings.dat`, `update_url.txt`, `.provisioned`,
  `fails.dat`) are never listed.
- HTTPS only; allowlist paths; enforce the 256KB cap; stage installs.

## Regression tests

Every fixed security bug gets a test that stays in `tests/test.sh` and runs in
the full suite.

| Test | Regression |
| --- | --- |
| T2c | Wrong password stays locked and records the failure |
| T3 | Recovery has no shell; reboot preserves `users.dat` |
| T4a–d | Missing `desktop.lua`, `window.lua`, `login.lua`, or `users.dat` fails closed |
| T14 | Notepad edits/saves user files, refuses OS files through canonicalized paths, multi-line open, F-keys, close veto |
| T15/T16 | Channel switching restores Notepad and heals a missing channel lib |

## Review checklist

Before committing a security change:

- [ ] Does this add a path from keyboard-only input to a shell or desktop?
- [ ] Does every failure/tamper path end in `os.shutdown()`?
- [ ] Is any executable file loaded from data? It must not be.
- [ ] Does Notepad still canonicalize before its single open/save gate?
- [ ] Do `manifest.lua` and `installer.lua` still list the same files?
- [ ] Is there a regression test for the bug, and do the old exploit tests pass?
