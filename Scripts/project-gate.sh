#!/bin/bash
# project-gate.sh — the WIP gate for agents (and humans).
#
# Wraps the `codenotch` CLI so any agent harness (Claude Code, Codex, Grok,
# Hermes, Cursor, Copilot…) can respect the gate by exit code:
#
#   add "Title"           -> exit 0 added, exit 1 gate full (names what to do)
#   done <id-or-title>    -> complete a project, frees a slot
#   defer <id-or-title> --until YYYY-MM-DD  -> park it, frees a slot
#   list | gate           -> inspect
#
# If the real `codenotch` binary is not installed this prints a clear
# message and exits 127 (command not found) so agents fail loudly rather
# than silently skipping the gate.
set -u

if command -v codenotch >/dev/null 2>&1; then
  exec codenotch project "$@"
fi

echo "project gate: \`codenotch\` binary not found — install the Codenotch app" >&2
echo "  (https://github.com/JRNY-Mobility/codenotch) so agents can check the WIP cap" >&2
exit 127
