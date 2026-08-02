#!/usr/bin/env bash
# PreToolUse hook: refuse edits to implementation files until a RED test run is on record.
#
# Reads the hook payload on stdin. Stays silent (exit 0) when the edit may proceed, so the
# normal permission flow is untouched; prints a deny decision only when it blocks.
#
# Scope comes from Plans.md: the row for the active task decides.
#   [tdd:skip:...]  -> pass
#   [tdd:required]  -> needs .claude/state/tdd/<task>.red.json
#   no tdd marker   -> treated as required (fail closed)
#
# Escape hatches: HARNESS_TDD_BYPASS=1, or mark the task [tdd:skip:<reason>] in Plans.md.

set -uo pipefail

ROOT="${TDD_GATE_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"

deny() {
  jq -nc --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

[ "${HARNESS_TDD_BYPASS:-}" = "1" ] && exit 0

payload="$(cat)"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -z "$file_path" ] && exit 0

rel="${file_path#"$ROOT"/}"

# Only source files the app actually ships are gated. Tests, docs, tooling and harness
# state are how you get to green, so they must stay editable.
case "$rel" in
  node_modules/*|.claude/*|.claude-plugin/*|.harness/*|docs/*|scripts/*|out/*|supabase/tests/*) exit 0 ;;
  tests/*|*/tests/*|__tests__/*|*/__tests__/*) exit 0 ;;
  *.test.*|*.spec.*) exit 0 ;;
  *.config.js|*.config.ts|*.config.mjs) exit 0 ;;
  *.ts|*.tsx|*.js|*.jsx|*.sql) ;;
  *) exit 0 ;;
esac

active="$ROOT/.claude/state/active-task.json"
task=""
if [ -f "$active" ]; then
  task="$(jq -r '.task // empty' "$active" 2>/dev/null || true)"
fi
[ -z "$task" ] && task="${HARNESS_ACTIVE_TASK:-}"

if [ -z "$task" ]; then
  deny "TDD gate: no active task. Write {\"phase\":\"<phase>\",\"task\":\"<id>\"} to .claude/state/active-task.json before editing $rel, or set HARNESS_TDD_BYPASS=1."
fi

plans="$ROOT/Plans.md"
[ -f "$plans" ] || deny "TDD gate: Plans.md not found at $plans, so the tdd marker for $task cannot be read."

row="$(grep -m1 -E "^\| *${task} *\|" "$plans" || true)"
[ -z "$row" ] && deny "TDD gate: task $task has no row in Plans.md, so its tdd marker is unknown."

case "$row" in
  *"[tdd:skip:"*) exit 0 ;;
esac

red="$ROOT/.claude/state/tdd/$task.red.json"
if [ ! -f "$red" ]; then
  deny "TDD gate: $task requires a failing test first, and no RED log exists. Write the test, then run: bash scripts/tdd-red.sh $task -- <test command>. Blocked file: $rel"
fi

status="$(jq -r '.status // empty' "$red" 2>/dev/null || true)"
if [ "$status" != "red" ]; then
  deny "TDD gate: $red exists but is not a RED record (status=${status:-none}). Re-run: bash scripts/tdd-red.sh $task -- <test command>"
fi

exit 0
