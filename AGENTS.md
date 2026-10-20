# Macaroon OS — agent guide

A Windows-style desktop OS for ComputerCraft: Tweaked. Repo root == computer
root (`/`), so paths in the repo are paths on the computer.

Read this file first. Then open only the scoped doc you need.

## Read next

| File | Use it for |
| --- | --- |
| `SPEC.md` | As-built behavior: boot, login, apps, updates |
| `THREAT_MODEL.md` | Assets, attackers, security invariants. Read before auth/boot/update/Notepad work |
| `macaroon/AGENTS.md` | OS code: app contract, Lua 5.1 limits, manifest/installer coupling |
| `tests/AGENTS.md` | Test harness, adding tests, toolchain setup |
| `STATE.md` | Current version, branch, working tree, next step. Update it when state changes |
| `MILESTONES.md` | Milestone history and status |

## Execution contract

Your job is to finish the task, not to start it. A plan, a diagnosis, or one
edited file is not completion.

### Loop

1. Inspect the relevant files and `STATE.md`.
2. Write a short plan (3–6 bullets) and the files you expect to touch.
3. Execute the plan. Keep going through implementation and verification.
4. Verify with the cheapest relevant test, then the broader suite this file
   requires.
5. Commit when the milestone passes.
6. Update `STATE.md` and report outcome, verification, commit, and remaining
   risk.

### Definition of done

A task is done only when:

- the behavior is implemented
- relevant tests pass, or the report says exactly which could not run and why
- docs/`STATE.md` are updated when behavior or state changed
- the change is committed (unless the user said not to commit)
- the final message states what changed and how it was verified

### Keep going

Continue until the definition of done is met or a hard blocker stops you.
Do not stop because:

- you finished analysis
- you finished one file
- the next step is large — break it down and continue
- you want to ask whether to proceed
- you want to offer "next steps"

Do all unblocked work before stopping.

### Hard blockers

Stop only for:

- an irreversible or destructive action that needs approval
- a missing credential, access, or file only the user can provide
- a requirement ambiguity where two implementations would produce materially
  different results
- an explicit approval gate in this file

When blocked, state:

1. the exact blocker
2. what you tried
3. the smallest action needed from the user
4. what remains unblocked and can still be done

Otherwise: decide, state your assumption, and proceed.

### Never

- ask the user to run a test you can run
- claim done without verification
- silently narrow the scope
- end with "I can…", "let me know", or "say the word"
- rewrite unrelated code just to make a test pass
- commit a failing state

## Project rules

- Work one milestone at a time from `SPEC.md` and `STATE.md`. Don't start the
  next milestone until the current one passes its tests.
- Before editing, say which files you expect to touch.
- If a change breaks things and you can't fix it, revert it rather than leaving
  the tree broken.
- The user is not the test runner. Run the tests yourself.

## Task tracking and context

- `STATE.md` is the handoff file: current goal, done, next, blockers. Read it
  at session start and update it before the final report.
- Keep a short checklist for multi-step work. Cross items off as they complete.
- Don't paste large files into the prompt. Use `grep`/`read` ranges and let
  tools fetch the details.
- Use subagents for exploration and bulk reading; ask for a short summary, not
  a full report.
- Keep decisions in files (`SPEC.md`, `STATE.md`, tests), not only in chat.
- When context gets heavy, write a handoff summary and start a fresh session.

## Commands

Run from the repo root.

```bash
bash tests/test.sh          # full suite (~10 min)
bash tests/test.sh quick    # syntax + login smoke + changed-file tests
bash tests/test.sh T14      # one test
```

Boot in the emulator (GUI):

```bash
DATA_DIR=$(mktemp -d); mkdir -p "$DATA_DIR/computer/0"
cp startup.lua "$DATA_DIR/computer/0/"
cp -r macaroon "$DATA_DIR/computer/0/"
craftos --directory "$DATA_DIR"
rm -rf "$DATA_DIR"
```

Headless boot smoke (the desktop loop never exits, so the kill is expected):

```bash
DATA_DIR=$(mktemp -d); mkdir -p "$DATA_DIR/computer/0"
cp startup.lua "$DATA_DIR/computer/0/"
cp -r macaroon "$DATA_DIR/computer/0/"
timeout -s KILL 10 craftos --directory "$DATA_DIR" --headless \
  --exec 'print("BOOT-OK:" .. tostring(fs.exists("startup.lua")))' \
  2>/dev/null | strings | grep BOOT-OK   # expect BOOT-OK:true
rm -rf "$DATA_DIR"
```

Toolchain setup is in `tests/AGENTS.md`.

## Verification

- **UI changes:** run CraftOS-PC under `xvfb-run`, take a screenshot, and look
  at it before saying you're done. Screen is 51x19; use the palette in
  `SPEC.md`. Save proofs in `screenshots/`.
- **Security changes:** read `THREAT_MODEL.md`, add a regression test, and
  rerun the old exploit tests.
- **Boot-critical files:** `startup.lua`, `macaroon/shellboot.lua`,
  `macaroon/login.lua`, `macaroon/users.lua`, `macaroon/updater.lua`,
  `macaroon/desktop.lua`, `macaroon/window.lua`, `macaroon/manifest.lua`,
  `installer.lua`. Before pushing these to `main`: full suite + user approval.

## Git and release

- `origin` is `https://github.com/Codingishardlol/MacaroonOS`.
- Local `main` tracks `origin/main` and stays equal to it. All work happens on
  branches; use the branch named in `STATE.md`.
- Push `beta` after quick mode plus changed-file tests pass. Push `main` only
  after the full suite passes and boot-critical changes have user approval.
- Never force-push. Before pushing, show `git status --short` and the push
  diff stat; don't ship unknown diffs.
- Version rule: any push that changes code installed on computers must bump
  `macaroon/version.lua` **and** the README badge in the same commit.
  Non-boot changes: patch bump chosen by the agent. Boot-critical changes:
  the user chooses the number.
- A broken released update is undone with `git revert` (never rewrite
  history); the fix ships as a new, bumped version.
- Pushes must use the saved `gh` token, not the read-only `GITHUB_TOKEN` env
  var. Unset `GITHUB_TOKEN` for push commands. Never print the token or write
  it into URLs/configs/files.

## Architecture map

- **Boot:** `startup.lua` → colour check → `shellboot.lua` → splash/recovery
  (`boot.lua`) → login (`login.lua` + `users.lua`) → update check →
  desktop (`desktop.lua` + `window.lua`). Fail-closed paths shut down; they
  never fall through to a shell.
- **Accounts:** `macaroon/users.lua` stores salted/stretched hashes in
  `macaroon/users.dat`; `macaroon/.provisioned` marks a machine that has had
  accounts; `macaroon/fails.dat` records persistent failures.
- **Desktop:** `macaroon/desktop.lua` owns the event loop, windows, taskbar,
  and Start menu; `macaroon/window.lua` handles drag/focus/close; each app is
  `macaroon/apps/*.lua`.
- **Updates:** `macaroon/updater.lua` reads `macaroon/manifest.lua` and
  compares `macaroon/version.lua`. `installer.lua` duplicates the `FILES`
  list as bootstrap; the two lists must stay identical.
- **Channels:** `macaroon/channel.lua` stores stable/beta; stable = `main`,
  beta = `beta`.
- **Data files** (`users.dat`, `settings.dat`, `update_url.txt`,
  `.provisioned`, `fails.dat`) are never in either file list, so installs and
  updates keep accounts and settings.

## Subagents

- Split a milestone into subtasks first. Independent tasks can run as parallel
  subagents in one step.
- Each subagent owns specific files and never edits outside them. Shared boot
  files (`startup.lua`, `boot.lua`, `login.lua`, `users.lua`, `desktop.lua`)
  are edited only by the main agent.
- Good subagent jobs: exploration, running the suite and summarizing failures,
  red-team exploits in the emulator, screenshots, separate apps, CC:Tweaked
  API research.
- Give each subagent a self-contained task and ask for a short summary, not a
  full report. The main agent runs the suite and commits after they finish.
