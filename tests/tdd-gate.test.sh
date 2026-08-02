#!/usr/bin/env bash
# Tests for scripts/tdd-gate.sh (PreToolUse hook) and scripts/tdd-red.sh (RED recorder).
#
# Run: bash tests/tdd-gate.test.sh
#
# Each case builds a throwaway project root (fake Plans.md + .claude/state) and pipes a
# PreToolUse payload into the gate. The gate is silent when it lets an edit through and
# prints a deny decision when it blocks one.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$REPO_ROOT/scripts/tdd-gate.sh"
RED="$REPO_ROOT/scripts/tdd-red.sh"

PASS=0
FAIL=0

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
  [ -n "${2:-}" ] && echo "        expected: $2"
  [ -n "${3:-}" ] && echo "        actual:   $3"
}

ok() {
  PASS=$((PASS + 1))
  echo "  ok: $1"
}

# Builds a fixture project root. $1 = active task id ("" for none).
make_root() {
  local task="$1"
  local root
  root="$(mktemp -d)"
  mkdir -p "$root/.claude/state" "$root/supabase/migrations" "$root/src" "$root/tests" "$root/docs"
  cat > "$root/Plans.md" <<'PLANS'
| Task | 내용 | DoD | Depends | Status |
|---|---|---|---|---|
| T1 | 앱 스캐폴드 `[lane:fast][tdd:skip:scaffold]` — Expo blank-typescript | 앱이 뜬다 | - | `cc:todo` |
| T5 | `0002_functions.sql` `[tdd:required]` — snap_to_cell | pgTAP 5건 pass | T4 | `cc:todo` |
| T14 | 수집 cron + 홈 상단 블록 — 갱신 스케줄 등록 | 시각 노출 | T13 | `cc:todo` |
PLANS
  if [ -n "$task" ]; then
    printf '{"phase":"test","task":"%s"}\n' "$task" > "$root/.claude/state/active-task.json"
  fi
  echo "$root"
}

record_red() {
  local root="$1" task="$2"
  mkdir -p "$root/.claude/state/tdd"
  printf '{"task":"%s","status":"red"}\n' "$task" > "$root/.claude/state/tdd/$task.red.json"
}

# Runs the gate against a file path. Echoes stdout, sets GATE_EXIT.
run_gate() {
  local root="$1" path="$2"
  local payload
  payload="$(jq -nc --arg p "$root/$path" '{tool_name:"Edit",tool_input:{file_path:$p}}')"
  GATE_OUT="$(printf '%s' "$payload" | TDD_GATE_ROOT="$root" bash "$GATE" 2>&1)"
  GATE_EXIT=$?
}

assert_allows() {
  local label="$1"
  if [ -z "$GATE_OUT" ] && [ "$GATE_EXIT" -eq 0 ]; then
    ok "$label"
  else
    fail "$label" "silent, exit 0" "exit $GATE_EXIT, out: $GATE_OUT"
  fi
}

assert_denies() {
  local label="$1"
  local decision
  decision="$(printf '%s' "$GATE_OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null || true)"
  if [ "$decision" = "deny" ]; then
    ok "$label"
  else
    fail "$label" "permissionDecision=deny" "${GATE_OUT:-<empty>}"
  fi
}

echo "gate: paths that are not implementation code"

root="$(make_root T5)"
run_gate "$root" "tests/functions.test.sql"
assert_allows "test file passes through"

run_gate "$root" "docs/data-model.md"
assert_allows "docs pass through"

run_gate "$root" "jest.config.js"
assert_allows "tooling config passes through"

echo "gate: Plans.md tdd markers"

root="$(make_root T1)"
run_gate "$root" "App.tsx"
assert_allows "[tdd:skip:scaffold] task can touch implementation"

root="$(make_root T5)"
run_gate "$root" "supabase/migrations/0002_functions.sql"
assert_denies "[tdd:required] task without RED log is blocked"

record_red "$root" T5
run_gate "$root" "supabase/migrations/0002_functions.sql"
assert_allows "[tdd:required] task with RED log proceeds"

root="$(make_root T14)"
run_gate "$root" "src/screens/Home.tsx"
assert_denies "task with no tdd marker fails closed"

echo "gate: escape hatches and missing state"

root="$(make_root "")"
run_gate "$root" "src/lib/supabase.ts"
assert_denies "no active task is blocked"

root="$(make_root T5)"
payload="$(jq -nc --arg p "$root/src/lib/supabase.ts" '{tool_name:"Edit",tool_input:{file_path:$p}}')"
GATE_OUT="$(printf '%s' "$payload" | TDD_GATE_ROOT="$root" HARNESS_TDD_BYPASS=1 bash "$GATE" 2>&1)"
GATE_EXIT=$?
assert_allows "HARNESS_TDD_BYPASS=1 opens the gate"

echo "red recorder"

root="$(make_root T5)"
RED_OUT="$(TDD_GATE_ROOT="$root" bash "$RED" T5 -- false 2>&1)"
RED_EXIT=$?
if [ "$RED_EXIT" -eq 0 ] && [ -f "$root/.claude/state/tdd/T5.red.json" ]; then
  ok "failing command records a RED log"
else
  fail "failing command records a RED log" "exit 0 + T5.red.json" "exit $RED_EXIT, out: $RED_OUT"
fi

root="$(make_root T5)"
RED_OUT="$(TDD_GATE_ROOT="$root" bash "$RED" T5 -- true 2>&1)"
RED_EXIT=$?
if [ "$RED_EXIT" -ne 0 ] && [ ! -f "$root/.claude/state/tdd/T5.red.json" ]; then
  ok "passing command is refused as RED"
else
  fail "passing command is refused as RED" "non-zero exit + no red log" "exit $RED_EXIT, out: $RED_OUT"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
