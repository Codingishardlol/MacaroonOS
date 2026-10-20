# tests/ — behavioral test guide

Read the root `AGENTS.md` first. The suite boots the real OS in CraftOS-PC; it
does not just lint Lua.

## Run

From the repo root:

```bash
bash tests/test.sh          # full suite, T0 + T1-T16 (~10 min)
bash tests/test.sh quick    # syntax + login smoke + changed-file tests (~20s clean)
bash tests/test.sh T14      # one test (case-insensitive)
```

Exit code 0 means every test passed. The full suite is required before
promoting `beta` to `main` and for any boot-critical file change.

## Toolchain setup

If the Codespace is rebuilt:

```bash
sudo add-apt-repository -y ppa:jackmacwindows/ppa
sudo apt-get update -qq
sudo apt-get install -y craftos-pc xvfb scrot xdotool python3-pil
craftos --version   # CraftOS-PC v2.8.3
```

Also required: `python3` with Pillow (`python3 -c "import PIL"`), `luac`, and
`luac5.1`.

## Coverage

The authoritative test map is in `SPEC.md` under **Test coverage**. This file
covers how to run and extend the suite, not what each test proves.

## Harness helpers

Defined in `tests/test.sh`:

| Helper | Use |
| --- | --- |
| `mkdata` | Fresh emulator disk with the OS files |
| `mkaccount` | Create `testuser` / `testpass123` through the real Users API |
| `boot_poll` | Boot and poll the screen for a pattern |
| `poll_screen` | Poll a screenshot for a condition |
| `pxcount` / `pxfast` | Count palette pixels in screenshots |
| `hit` | Record a pass/fail |
| `run_name` | Map `T14` → `t14` |
| `files_for_test` | Files that trigger a test in quick mode |

## Adding a test

1. Add `tNN()` to `tests/test.sh`.
2. Add `tNN` to `ALL_TESTS`.
3. Add it to the `run_name` case.
4. Add the files it covers to `files_for_test` so quick mode runs it after a
   change.
5. Use `mkdata` / `mkaccount` for isolation, clean up with `rm -rf "$D"`, and
   call `hit` exactly once at the end.

Security fixes always get a regression test that stays in the suite.

## Conventions and gotchas

- Always use `timeout -s KILL`; CraftOS ignores SIGTERM.
- Headless `--exec` scripts must end in `os.shutdown(code)` or the process
  hangs until killed.
- Headless output contains terminal control bytes: pipe through `strings`
  before grep.
- The terminal is 51 columns wide; long prints wrap, so keep grep markers
  short.
- Headless CraftOS ignores piped stdin. Keyboard input in GUI tests goes
  through `xdotool` under `xvfb-run`.
- Do not use fixed sleeps for boot or UI readiness; poll the screen or
  screenshot instead.
- GUI tests save proof screenshots in `screenshots/`.
- T15 and T16 depend on deployed channel behavior; note that in the failure
  message if the network or beta branch is unavailable.
- Every test gets a fresh `mkdata` disk; never share state between tests.
