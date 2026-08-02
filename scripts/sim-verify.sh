#!/usr/bin/env bash
# Cold-start verification for the iOS simulator: boots a device, makes sure Metro is up,
# opens the project in Expo Go, waits for the JS bundle, and captures a screenshot.
#
#   bash scripts/sim-verify.sh
#   bash scripts/sim-verify.sh --device "iPhone 15" --out /tmp/home.png
#
# Exists because the launch sequence has three non-obvious failure modes:
#   - `simctl openurl exp://…` times out (NSPOSIXErrorDomain 60) unless Expo Go is already
#     running, so the app is launched first and the URL is retried.
#   - `CI=1 expo start` never prints an exp:// URL, so it is built from the LAN address.
#   - On a fresh Expo Go install a dev-menu onboarding sheet covers the app and can only be
#     dismissed by tapping. EXDevMenuIsOnboardingFinished in the app's preferences plist is
#     what that tap sets, so it is seeded here instead.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="iPhone 16 Pro"
OUT="$ROOT/.claude/state/sim-verify.png"
PORT=8081
EXPO_GO=host.exp.Exponent
LOG="$ROOT/.claude/state/sim-verify-metro.log"

while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

step() { echo "==> $*"; }
die() { echo "sim-verify: $*" >&2; exit 1; }

# grep -c prints 0 and exits 1 when there is no match, so a `|| echo 0` fallback would
# print a second zero and break every numeric comparison downstream.
bundle_count() {
  local n
  n="$(grep -c "iOS Bundled" "$LOG" 2>/dev/null || true)"
  echo "${n:-0}"
}

mkdir -p "$(dirname "$OUT")"

step "booting $DEVICE"
booted="$(xcrun simctl list devices booted | grep -c "$DEVICE")"
if [ "$booted" -eq 0 ]; then
  xcrun simctl boot "$DEVICE" || die "could not boot $DEVICE"
fi
open -a Simulator
until xcrun simctl list devices booted | grep -q "$DEVICE"; do sleep 1; done

step "checking Metro on port $PORT"
OWNS_METRO=1
if [ -z "$(lsof -ti:"$PORT" 2>/dev/null)" ]; then
  step "starting Metro (log: $LOG)"
  : > "$LOG"
  (cd "$ROOT" && CI=1 npx expo start --port "$PORT" >> "$LOG" 2>&1 &)
  waited=0
  until curl -sf "http://localhost:$PORT/status" >/dev/null 2>&1; do
    sleep 2
    waited=$((waited + 2))
    [ "$waited" -gt 120 ] && die "Metro did not come up in 120s, see $LOG"
  done
else
  # Someone else's dev server owns the port, so its bundle output goes somewhere this
  # script cannot read. The screenshot still happens; the bundle assertion is skipped.
  OWNS_METRO=0
  step "Metro already running (not started here, so bundle output cannot be asserted)"
fi

ip="$(ipconfig getifaddr en0 2>/dev/null || echo 127.0.0.1)"
url="exp://$ip:$PORT"

if ! xcrun simctl get_app_container booted "$EXPO_GO" >/dev/null 2>&1; then
  step "Expo Go not installed, letting the Expo CLI install it (first run only)"
  (cd "$ROOT" && CI=1 npx expo start --ios --port "$PORT" >> "$LOG" 2>&1 &)
  waited=0
  until xcrun simctl get_app_container booted "$EXPO_GO" >/dev/null 2>&1; do
    sleep 5
    waited=$((waited + 5))
    [ "$waited" -gt 600 ] && die "Expo Go was not installed within 600s, see $LOG"
  done
fi

step "checking the dev-menu onboarding flag"
# The simulator's cfprefsd holds this plist in memory and flushes its copy back over any
# file written underneath it — and the runtime ships no killall to restart it. Shutting the
# device down makes cfprefsd exit and flush, so the write only sticks across a boot cycle.
# Only pay for that cycle when the flag is actually unset.
xcrun simctl terminate booted "$EXPO_GO" >/dev/null 2>&1
plist="$(xcrun simctl get_app_container booted "$EXPO_GO" data)/Library/Preferences/$EXPO_GO.plist"
if [ ! -f "$plist" ]; then
  echo "    (no preferences plist yet; a one-time Continue tap may be needed)"
elif plutil -p "$plist" | grep -q 'EXDevMenuIsOnboardingFinished" => true'; then
  echo "    already dismissed"
else
  step "seeding the flag (needs a shutdown/boot cycle so cfprefsd releases the plist)"
  xcrun simctl shutdown booted >/dev/null 2>&1
  until [ -z "$(xcrun simctl list devices booted | grep "$DEVICE")" ]; do sleep 1; done
  plutil -replace EXDevMenuIsOnboardingFinished -bool true "$plist" 2>/dev/null ||
    plutil -insert EXDevMenuIsOnboardingFinished -bool true "$plist" 2>/dev/null ||
    echo "    (could not write the flag; a one-time Continue tap may be needed)"
  xcrun simctl boot "$DEVICE" || die "could not reboot $DEVICE"
  until xcrun simctl list devices booted | grep -q "$DEVICE"; do sleep 1; done
  sleep 8
fi

step "opening $url"
before="$(bundle_count)"
xcrun simctl launch booted "$EXPO_GO" >/dev/null 2>&1
sleep 5
opened=0
for attempt in 1 2 3; do
  if xcrun simctl openurl booted "$url" >/dev/null 2>&1; then
    opened=1
    break
  fi
  echo "    openurl attempt $attempt timed out, retrying"
  sleep 3
done
[ "$opened" -eq 1 ] || die "simulator never accepted $url"

if [ "$OWNS_METRO" -eq 1 ]; then
  step "waiting for the JS bundle"
  waited=0
  until [ "$(bundle_count)" -gt "$before" ]; do
    sleep 2
    waited=$((waited + 2))
    [ "$waited" -gt 180 ] && die "no bundle within 180s, see $LOG"
  done
  sleep 3
else
  step "waiting 20s for the app to settle"
  sleep 20
fi

step "capturing $OUT"
xcrun simctl io booted screenshot "$OUT" >/dev/null 2>&1 || die "screenshot failed"

echo
if [ "$OWNS_METRO" -eq 1 ]; then
  grep "iOS Bundled" "$LOG" | tail -1
  grep -iE "error|failed|Unable to resolve" "$LOG" | tail -3
else
  echo "bundle not asserted: Metro was already running elsewhere"
fi
echo "screenshot: $OUT"
