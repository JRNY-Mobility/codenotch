# Project Gate — WIP cap of 5

The notch app now carries a **project gate**: at most **5** projects may be open
at once. Give any AI a new project and the gate records it; when the gate is
full, the next project is refused until one is completed (or deferred).

This is a *productivity* feature: it bounds the number of half-finished builds,
so completion is forced rather than assumed.

## Usage (CLI)

The gate ships as a thin `codenotch` CLI binary alongside the app, plus a
wrapper script for agents (`Scripts/project-gate.sh`). Both share the app's
preferences domain, so the notch ring and the CLI read one list.

```sh
# open a project — prints "added <id> \"<title>\" (N/5 active)"
codenotch project add "Whale Watching site v2"

# at the cap (5 active): exit code 1, names what must be completed first
codenotch project add "Sixth thing"        # -> "project gate is full (5/5 active)…"

# complete a project — frees a slot (exit 0)
codenotch project done "Whale Watching site v2"     # by title, case-insensitive
codenotch project done 3F2A…                      # or by id

# park a project until a date — frees a slot immediately (exit 0)
codenotch project defer "Big refactor" --until 2026-09-20

# inspect
codenotch project list      # grouped Active / Deferred / Completed
codenotch project gate      # "cap=5 active=3/5 deferred=1 completed=2 slots_left=2"
```

Exit codes are the contract agents rely on:

| code | meaning |
|---|---|
| 0 | the command did what it was asked |
| 1 | an expected refusal: cap reached, nothing matched, bad defer date |
| 2 | a usage error: unknown command or missing arguments |
| 127 | the `codenotch` binary is not installed (wrapper only) |

## How agents use it

Point any harness at `Scripts/project-gate.sh` (or the binary directly) and
**respect the exit code**: on `1` (gate full), stop and complete or defer
something before starting the new project. The notch ring (`N/5`) shows the
same state at a glance.

## Semantics

- **Cap:** 5 active projects. Deferred projects do **not** hold a slot — the
  point of deferring is "I'll be free by then".
- **Expiry:** when a deferred project's date passes it returns to `.active`
  and counts again. That can push the count over 5; new adds stay blocked
  until the overage clears.
- **Resolution:** commands accept a UUID or a title (case- and accent-
  insensitive, trimmed).
- **Persistence:** one `Codable` array in `UserDefaults` (key `projectGate`),
  shared by the app, the CLI and the tests.

## Files

- `Sources/Model/Project.swift` — `Project`, `ProjectStatus`, `ProjectGateState`
- `Sources/Model/ProjectStore.swift` — the store (`cap = 5`)
- `Sources/Model/ProjectGateError.swift` — `.capReached`, `.notFound`, `.invalidDate`
- `Sources/CLI/main.swift`, `Sources/CLI/ProjectGateCLI.swift` — the CLI
- `Scripts/project-gate.sh` — agent wrapper
- `Tests/ProjectStoreTests.swift`, `Tests/ProjectGateCLITests.swift`
- `docs/plans/2026-09-10-project-gate-plan.md` — the plan

## Future

- Auto-detection of "a project started" from session monitors (v2).
- Multi-machine sync of the gate.
