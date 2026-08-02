#!/usr/bin/env bash
# Records the RED half of a TDD cycle: runs a test command, and only if it FAILS writes
# .claude/state/tdd/<task>.red.json — the evidence scripts/tdd-gate.sh looks for.
#
# Usage: bash scripts/tdd-red.sh <task-id> -- <test command...>
#   bash scripts/tdd-red.sh T5 -- supabase test db
#   bash scripts/tdd-red.sh T10 -- npm test -- Home

set -uo pipefail

ROOT="${TDD_GATE_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"

usage() {
  echo "usage: bash scripts/tdd-red.sh <task-id> -- <test command...>" >&2
  exit 2
}

[ $# -ge 2 ] || usage
task="$1"
shift
[ "$1" = "--" ] || usage
shift
[ $# -ge 1 ] || usage

echo "RED check for $task: $*"
output="$("$@" 2>&1)"
code=$?
printf '%s\n' "$output"

if [ "$code" -eq 0 ]; then
  echo >&2
  echo "REFUSED: the test command passed (exit 0). A RED log needs a failing test — write the failing test first." >&2
  exit 1
fi

mkdir -p "$ROOT/.claude/state/tdd"
jq -n \
  --arg task "$task" \
  --arg command "$*" \
  --arg recorded_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg output "$(printf '%s' "$output" | tail -20)" \
  --argjson exit_code "$code" \
  '{task:$task,status:"red",command:$command,exit_code:$exit_code,recorded_at:$recorded_at,output_tail:$output}' \
  > "$ROOT/.claude/state/tdd/$task.red.json"

echo
echo "RED recorded (exit $code): .claude/state/tdd/$task.red.json — implementation files for $task are now editable."
