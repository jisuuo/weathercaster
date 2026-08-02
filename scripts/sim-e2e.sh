#!/usr/bin/env bash
# Runs the Maestro flows against the app in the iOS simulator.
#
#   bash scripts/sim-e2e.sh                  # all flows in .maestro/
#   bash scripts/sim-e2e.sh .maestro/smoke.yaml
#
# sim-verify.sh does the setup (boot, Metro, dev-menu flag, first load); this only drives
# the UI. Maestro lives in ~/.maestro because Homebrew refuses to install it until the
# Command Line Tools are updated.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAESTRO="${MAESTRO_BIN:-$HOME/.maestro/bin/maestro}"
PORT=8081
FLOW="${1:-$ROOT/.maestro}"

[ -x "$MAESTRO" ] || { echo "maestro not found at $MAESTRO" >&2; exit 1; }

export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home)}"
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true

bash "$ROOT/scripts/sim-verify.sh" --port "$PORT" || exit 1

ip="$(ipconfig getifaddr en0 2>/dev/null || echo 127.0.0.1)"
echo
echo "==> maestro test $FLOW (EXPO_URL=exp://$ip:$PORT)"
"$MAESTRO" test -e "EXPO_URL=exp://$ip:$PORT" "$FLOW"
