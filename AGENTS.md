# ComputerCraft OS project

## How to work
- Work one milestone at a time from SPEC.md. Don't start the next 
  milestone until the current one passes its tests.
- After every change, run the tests. Never say you're done until they 
  pass. If you can't run them, say so instead of guessing.
- Commit to git after each passing milestone. If a change breaks 
  things you can't fix, revert it.
- Keep going on your own until the milestone is done or you're 
  genuinely blocked. Don't ask me to test things for you.

## Running and testing (verified 2026-10-15, CraftOS-PC v2.8.3)
- Run command (GUI — boots this OS in the emulator; run from this folder):
  ```bash
  DATA_DIR=$(mktemp -d); mkdir -p "$DATA_DIR/computer/0"
  cp startup.lua "$DATA_DIR/computer/0/"
  cp -r macaroon "$DATA_DIR/computer/0/"
  craftos --directory "$DATA_DIR"   # interactive GUI, close window to quit
  rm -rf "$DATA_DIR"
  ```
  Headless smoke (same boot, no GUI; the desktop loop never exits on its
  own, so the timeout kill with exit 137 is expected):
  ```bash
  DATA_DIR=$(mktemp -d); mkdir -p "$DATA_DIR/computer/0"
  cp startup.lua "$DATA_DIR/computer/0/"
  cp -r macaroon "$DATA_DIR/computer/0/"
  timeout -s KILL 10 craftos --directory "$DATA_DIR" --headless \
    --exec 'print("BOOT-OK:" .. tostring(fs.exists("startup.lua")))' \
    2>/dev/null | strings | grep BOOT-OK   # expect BOOT-OK:true
  rm -rf "$DATA_DIR"
  ```
- Test command (one command, ~3 min, exit 0 = all pass):
  ```bash
  bash test.sh
  ```
  `test.sh` boots the real OS in CraftOS-PC and checks behavior: T0
  `luac -p` syntax; T1 boot reaches desktop (no accounts) / login
  (accounts); T2 correct password logs in, wrong password stays locked
  and records the failure; T3 `R` during splash gives the recovery menu
  (no shell), reboot preserves `users.dat`; T4 deleting each of
  `desktop.lua`, `window.lua`, `login.lua`, `users.dat` shuts down with
  no shell and no open desktop. GUI steps use `xdotool` under `xvfb-run`
  and save proofs to `screenshots/`.
- Setup steps so this can be redone if the Codespace is rebuilt:
  ```bash
  sudo add-apt-repository -y ppa:jackmacwindows/ppa   # CraftOS-PC source (idempotent)
  sudo apt-get update -qq
  sudo apt-get install -y craftos-pc xvfb scrot
  craftos --version   # CraftOS-PC v2.8.3
  scrot --version     # scrot version 1.10
  ```
  Installed here: `craftos-pc 1:2.8.3-noble2` + `craftos-pc-data`,
  `xvfb 2:21.1.12-1ubuntu1.8`, `scrot 1.10-1build2` (`imagemagick` is
  present as a fallback screenshot tool).

## UI work
- After any change to how the screen looks, run CraftOS-PC under 
  xvfb-run, take a screenshot, and look at it before saying you're done.
- Check: text isn't cut off or overlapping, colors are readable, 
  elements line up, nothing draws outside its box.
- Screen size is 51x19 characters. Use the palette in SPEC.md.
- Save screenshots in screenshots/. Fix what you see and re-screenshot.
- Verified screenshot recipe (run from this folder; produces
  `screenshots/macaroon-boot.png`, proof the OS boots visibly):
  ```bash
  DATA_DIR=$(mktemp -d); mkdir -p "$DATA_DIR/computer/0"
  cp startup.lua "$DATA_DIR/computer/0/"
  cp -r macaroon "$DATA_DIR/computer/0/"
  export DATA_DIR
  xvfb-run -a -s "-screen 0 1280x800x24" bash -c '
  craftos --directory "$DATA_DIR" &
  CPID=$!
  sleep 15   # splash (~2s) + update check + login skip + desktop
  scrot screenshots/macaroon-boot.png
  kill $CPID; sleep 1; kill -9 $CPID 2>/dev/null || true
  '
  rm -rf "$DATA_DIR"
  ```
  Notes: `scrot` syntax is `scrot <file>` (`-d` takes a delay in
  seconds, so `scrot -d <file>` fails). ALSA `cannot find card '0'`
  warnings on stderr are harmless (no sound card); hide with
  `2>/dev/null`. Reference shots in this folder: `craftos-screenshot.png`
  (emulator sanity: `HELLO-FROM-CODESPACE` / `GUI-PROOF-12345` on a
  CraftOS prompt) and `screenshots/macaroon-boot.png` (this OS booted:
  splash + `Macaroon` taskbar with clock).

## Security
- Rules are in THREAT_MODEL.md. Read it before touching login, 
  user files, the kernel, or boot code.
- Every security bug that gets fixed gets a regression test that 
  stays in the test suite and runs every time.
- Red-team subagents must produce a working exploit script that runs 
  in the emulator. No demonstrated exploit, no finding.
- After any security-related change, rerun ALL old exploit tests to 
  make sure nothing was reopened.

## CraftOS-PC setup notes (moved from base AGENTS.md, verified 2026-10-15)

Headless text mode (`--headless`) prints the terminal as plain text to
stdout. It stays in the interactive shell afterwards, so every test
invocation **must** end with `os.shutdown([code])` — the code becomes
the process exit code. Without it the command hangs until killed
(exit 137).

```bash
# inline test, exit 0
timeout 15 craftos --headless --exec 'print("EXEC-HELLO-67890"); os.shutdown(0)' 2>/dev/null | strings | tail -n 5
echo "exit:$?"   # 0

# script-file test
cat > /tmp/headless_test_script.lua <<'EOF'
print("SCRIPT-MODE-OK")
assert(2+2 == 4, "math broke")
print("ALL-TESTS-PASSED")
os.shutdown(0)
EOF
timeout 15 craftos --headless --script /tmp/headless_test_script.lua 2>/dev/null | strings | tail -n 5
echo "exit:$?"   # 0

# exit-code propagation
timeout 15 craftos --headless --exec 'os.shutdown(42)' >/dev/null 2>&1; echo "exit:$?"   # 42

# isolated data dir (recommended so tests never touch ~/.local/share/craftos-pc)
DATA_DIR=$(mktemp -d)
mkdir -p "$DATA_DIR/computer/0"
timeout 15 craftos --directory "$DATA_DIR" --headless --exec 'print("ISOLATED-TEST-OK"); os.shutdown(0)' 2>/dev/null | strings | grep ISOLATED
rm -rf "$DATA_DIR"
```

Tips:

- Always wrap in `timeout 15 ...`; a missing `os.shutdown()` hangs forever.
- Pipe through `strings`: headless output has terminal control bytes and
  a typing animation of the MOTD; grep for your marker.
- `2>/dev/null` hides the harmless ALSA warnings.
- `--cli` (ncurses) and `--raw` exist but are not needed; `--headless`
  is the documented CI mode. Pattern for real suites (per CraftOS-PC
  docs): `craftos --directory "$DATA_DIR" --headless --exec
  'shell.run("test/mcfly.lua test"); os.shutdown()'`.


## Subagents
- Before starting any milestone, list its subtasks and mark which are 
  independent. If two or more are independent, launch them as parallel 
  subagents in a single step instead of one at a time.
- Each subagent owns specific files and never edits files outside them 
  (for example: one on macaroon/apps/files.lua, another on 
  macaroon/apps/settings.lua). Shared files (startup.lua, boot.lua, 
  login.lua, users.lua, desktop.lua) are edited only by the main agent.
- Good subagent jobs: running the test suite and summarizing failures, 
  red-team exploit attempts against the OS in the emulator, taking and 
  reviewing screenshots, building separate apps, researching CC:Tweaked 
  APIs.
- Give each subagent a self-contained task and ask for a short summary 
  back, not a full report.
- After subagents finish, the main agent runs the full test suite before 
  committing.