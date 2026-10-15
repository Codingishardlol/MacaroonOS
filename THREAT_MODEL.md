# Macaroon OS — THREAT MODEL

Read before touching login, user files, the kernel, or boot code.

## Assets

- `macaroon/users.dat` — salted/stretched password hashes (not plaintext,
  but offline-crackable: protect the file).
- The logged-in session (desktop after login) — full computer access.
- `macaroon/settings.dat`, update source — integrity (malicious source =
  code execution on update).

## Attackers

1. **Walk-up attacker** (keyboard only, no file access). Primary adversary.
   Must never reach a shell or desktop without a password.
2. **File tamperer** (can delete/corrupt files, e.g. via another OS or
   world edit, but wants the machine to boot open). Covered by fail-closed
   boot: missing `window.lua`/`desktop.lua`, damaged `users.dat`, or wiped
   `users.dat` on a provisioned machine (`.provisioned` marker) all shut
   down (`test.sh` T4a–d).
3. **Network attacker** (update path). Mitigated: HTTPS-only, manifest
   path allowlist (no traversal, no data-file overwrite), 256KB/file cap,
   staged install, explicit user consent, offline never blocks boot.
4. **Brute-forcer**. Mitigated: 5 misses per sitting lock it; 20 persistent
   fails (`fails.dat`, survives reboot) force a 30s wait; passwords are
   salted + stretched (100× SHA-256) with constant-time compare.
5. **Computer owner with file access** — OUT OF SCOPE. Anyone who can open
   the computer's files can delete the gate (same as every ComputerCraft
   OS). This stops walk-ups, not owners. Deleting `.provisioned` +
   `users.dat` together reverts to fresh-copy behavior; document, don't
   chase.

## Sensitive spots (verify against this list on every security change)

- `startup.lua` bootLogin + fail-closed paths: every `fail()`/tamper
  branch must end in `os.shutdown()`, never `return`-to-shell. `R`
  recovery must offer reinstall-only (no shell — deleting `users.dat`
  from recovery would defeat the gate).
- `macaroon/login.lua`: `Ctrl+T` (terminate) must not escape to shell;
  attempts capped; password buffer capped at 64; no `os.shutdown` inside
  (caller decides via `"shutdown"`/`"locked"` reasons).
- `macaroon/users.lua`: never `load()`/`dofile` the dat file (pattern
  parse only); clamp rounds (1–1000) and file size (16KB); marker
  `.provisioned` written on create, never in manifest.
- Terminal app: restore globals a command tampers with.
- Updater/installer `FILES` ≡ `manifest.lua` list; data files never listed.

## Regression rule (from AGENTS.md)

Every fixed security bug gets a regression test that stays in `test.sh`
and runs every time. Current: T2c (wrong password locked + recorded),
T3 (recovery has no shell, reboot preserves `users.dat`), T4a–d
(deletions fail closed). Red-team subagents must produce a working
exploit script that runs in the emulator — no demonstrated exploit, no
finding — and after any security change, rerun ALL old exploit tests.
