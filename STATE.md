# Current state

Updated: 2026-10-20

## Release

| Item | Value |
| --- | --- |
| Version | `1.7.8` |
| Stable channel | `main` |
| Beta channel | `beta` |
| Release status | `1.7.8` live on both channels |
| Last full suite | 24 passed, 0 failed on `beta` (parallel groups, 50s) |

## Working tree

- Clean after the test-harness and docs commits.
- Full suite runs in parallel by default; use `SERIAL=1` for one at a time.
- The latest commits are test/docs only; installed code is unchanged, so the
  version did not change.

## Next

- Keep `version.lua` and the README badge in sync for every code-shipping
  release.
- Use `beta` for the next feature; promote to `main` only after a full suite
  and boot-critical approval.
