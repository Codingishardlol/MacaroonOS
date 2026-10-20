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
- every behavior the harness can exercise has a passing test
- the report separates **Verified by** from **Not verified**, and explains why
  anything could not be exercised
- docs/`STATE.md` are updated when behavior or state changed
- the change is committed (unless the user said not to commit)
- the final message states what changed and how it was verified

If a required behavior cannot be exercised by the harness, the task can still
be complete, but the report must say `implemented; verified by X` and
`not verified: Y`, and must not claim full verification.

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

- ask the user to run a test the harness can run (for behavior it genuinely
  cannot exercise, report **Not verified** and name the smallest manual check)
- claim a behavior is verified when the harness did not verify it
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
- The user is not the test runner for anything the harness can run. Run those
  tests yourself. For behavior the harness genuinely cannot exercise, report
  it as **Not verified** rather than pretending it passed.

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

Run from the repo root:

```bash
bash tests/test.sh          # full suite
SERIAL=1 bash tests/test.sh # same tests, one at a time
bash tests/test.sh quick    # syntax + login smoke + changed-file tests
bash tests/test.sh T14      # one test
```

Toolchain setup, manual boot, and harness helpers are in `tests/AGENTS.md`.

## Verification

- Run the cheapest test that covers the change, then the full suite for
  boot-critical changes.
- **UI:** screenshot under `xvfb-run` and inspect it. Conventions and proof
  location are in `macaroon/AGENTS.md`.
- **Security:** read `THREAT_MODEL.md`, add a regression test, and rerun the
  old exploit tests.
- **Boot-critical files:** `startup.lua`, `macaroon/shellboot.lua`,
  `macaroon/login.lua`, `macaroon/users.lua`, `macaroon/updater.lua`,
  `macaroon/desktop.lua`, `macaroon/window.lua`, `macaroon/manifest.lua`,
  `installer.lua`. Full suite + user approval before `main`.
- **Untestable behavior:** if the harness cannot exercise it, report
  **Verified by** and **Not verified** separately, with the smallest manual
  check. Don't ask the user to run what the harness can run.
  (`Verified by X; not verified: Y` is a good report.)

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

## Subagents

- Split a milestone into independent subtasks. Each subagent owns specific
  files and never edits outside them.
- Shared boot files (`startup.lua`, `boot.lua`, `login.lua`, `users.lua`,
  `desktop.lua`) are edited only by the main agent.
- Good jobs: exploration, test runs/failure summaries, red-team exploits,
  screenshots, separate apps, CC:Tweaked API research.
- Give each a self-contained task and ask for a short summary. The main agent
  runs the suite and commits.
