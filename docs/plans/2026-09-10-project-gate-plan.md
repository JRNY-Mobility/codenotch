# Project Gate — WIP Cap of 5 (2026-09-10)

## Problem

Pete starts AI projects faster than they finish. Each new project given to any
AI (Claude Code, Codex, Grok, Hermes, Cursor, Copilot…) opens a new context with
no bound on how many stay half-done. Aim: productivity — cap open work, force
completion, allow a date-based defer.

## Feature

The notch gains a **Project Gate** cell: a ring/cell showing active project count
out of a cap of **5** (e.g. `3/5`). Hovering the card lists each active project
with status and age. Actions: **Complete** (frees a slot) and **Defer** (set a
target date — frees a slot immediately, project is listed as deferred with its
date). Adding a project at the cap **fails with a non-zero exit** and a clear
message naming what must be completed first.

## Design

### 1. Model (`Sources/Model/`)

`Project`: Codable, Identifiable
- `id: UUID`
- `title: String`
- `createdAt: Date`
- `status: ProjectStatus` (`.active`, `.completed`, `.deferred`)
- `completedAt: Date?`
- `deferUntil: Date?`

`ProjectStatus: String, Codable` with display copy (localized via L10n).

`ProjectStore` (mirrors `UsageArchive` conventions):
- Persists to UserDefaults under key `projectGate` (Codable array), or a JSON
  file in Application Support if size grows — UserDefaults is fine at this scale.
- `MAX_ACTIVE = 5`
- `add(title:) -> Result<Void, ProjectGateError>` — rejects with `.capReached`
  when active+deferred count ≥ 5 (deferred projects hold a slot until their date
  passes; see below).
- `complete(id:)` — marks completed, records `completedAt`.
- `defer(id:until:)` — sets `.deferred` + `deferUntil`; slot frees immediately.
- `expireDeferred()` — a deferred project whose date has passed becomes `.active`
  again (it still needs doing) — or, better: **deferred projects do NOT hold a
  slot once their date passes** (the point is "I'll be free by then"), but before
  the date they do. Decision: `defer` frees the slot immediately AND the project
  re-activates when the date passes, re-claiming a slot — so the cap still holds.
  Simpler and defensible: a deferred project **does not count against the cap**,
  and re-activating it when the date passes may push the count over — the gate
  then blocks *new* adds until the overage clears. Both are implementable; the
  plan picks: **defer frees the slot; on date pass the project returns to active
  and counts again (cap may be exceeded; new adds blocked until under).**

### 2. Notch cell (`Sources/Notch/`, `Sources/Features/`)

New cell in the notch fleet (follows `ProviderRing`/snapshot patterns):
- Ring or pill showing `activeCount/5`.
- Full project list in the tooltip card (`TooltipCard`), each row: title, status
  glyph, age/due date, Complete + Defer buttons.
- Reorders with the other cells (Settings order respected).

### 3. CLI (`Sources/App/` or new `Sources/CLI/`)

A `codenotch` CLI subcommand so ANY agent or the user can interact from a shell:
- `codenotch project add "Title"` → adds; **exit 1 with message** if at cap.
- `codenotch project done <id-or-title>` → completes.
- `codenotch project defer <id-or-title> --until YYYY-MM-DD` → defers.
- `codenotch project list` → table of projects + counts.
- `codenotch project gate` → prints cap state (for agent scripting).

Implementation: a small Foundation CLI target (no SwiftPM needed — the app is
XcodeGen; add a target or use `ProcessInfo` argv handling in the app binary
under a `--project` mode). Prefer: **new CLI target** in project.yml (XcodeGen)
so `codenotch` on PATH is a separate thin binary sharing `ProjectStore` source.

### 4. Agent integration

Docs (`docs/`) + a `Scripts/project-gate.sh` wrapper agents can call:
- Hermes: `codenotch project add` before starting a tracked build.
- Claude Code hooks / Codex / Grok: shell-out wrapper.
- The gate returning non-zero is what "forces" completion — agents that respect
  exit codes will stop and ask.

## Tests (`Tests/`)

- `ProjectStoreTests`: cap enforcement (6th add rejected), complete frees slot,
  defer frees slot + re-activation on date pass, persistence round-trip.
- `ProjectGateCLITests`: add/done/defer/list exit codes incl. cap rejection.
- Notch cell: snapshot/render test if the suite has one for cells (check
  existing patterns first — e.g. `AccessibilityTransparencyTests`).

## File map

- New: `Sources/Model/Project.swift`, `Sources/Model/ProjectStore.swift`,
  `Sources/Model/ProjectGateError.swift`
- New: `Sources/CLI/` (main + commands) + `project.yml` target entry
- New: `Sources/Features/ProjectGateRing.swift` (or reuse ProviderRing),
  tooltip rows
- New: `Sources/Notch/ProjectGateModel.swift` (ObservableObject feeding
  NotchViewModel, or extend NotchViewModel with a `projectGate` snapshot)
- New: `Tests/ProjectStoreTests.swift`, `Tests/ProjectGateCLITests.swift`
- New: `Scripts/project-gate.sh`, `docs/project-gate.md`
- Edit: `.github/workflows/*.yml` — remove `github.repository == 'vinzdg/codenotch'`
  guard so fork CI runs (this fork's own CI minutes).

## Out of scope (v1)

- Automatic detection of "a project started" from sessions (agent monitors see
  sessions, not intents — the explicit CLI call is the trigger).
- Syncing gate state across machines (single Mac for now).
