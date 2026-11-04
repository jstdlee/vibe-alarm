#!/usr/bin/env bash
#
# Boot a simulator, install the app and capture one screenshot per preview screen.
#
#   scripts/capture-screenshots.sh <device-udid> <app-path> <output-dir> [size-suffix]
#
# Every screen is driven by the same `-ui-preview-screen` launch argument the app reads at
# startup, so a screenshot is the real view with real data, not a rendered mock.
set -euo pipefail

UDID="${1:?device udid required}"
APP_PATH="${2:?app path required}"
OUT_DIR="${3:?output dir required}"
SUFFIX="${4:-}"

mkdir -p "$OUT_DIR"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance light 2>/dev/null || true
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiMode active \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100 2>/dev/null || true

xcrun simctl install "$UDID" "$APP_PATH"

app_running() {
  local services
  services="$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null || true)"
  case "$services" in
    *"UIKitApplication:com.jstdlee.vibealarm"*) return 0 ;;
    *) return 1 ;;
  esac
}

FAILED=0

capture_screen() {
  local mode="$1"
  local out="$2${SUFFIX:+$SUFFIX}.png"
  local attempt size
  for attempt in 1 2 3 4; do
    xcrun simctl terminate "$UDID" com.jstdlee.vibealarm 2>/dev/null || true
    sleep 2
    xcrun simctl launch "$UDID" com.jstdlee.vibealarm -ui-preview-screen "$mode" >/dev/null 2>&1 || true
    sleep 8
    if app_running; then
      # Let the first frame settle; the Intel simulator can hold the launch screen for seconds.
      sleep 10
      xcrun simctl io "$UDID" screenshot "$OUT_DIR/$out"
      size=$(stat -f%z "$OUT_DIR/$out")
      if ! app_running; then
        echo "::warning::VibeAlarm exited while rendering $mode (attempt $attempt)"
        rm -f "$OUT_DIR/$out"
        continue
      fi
      if [ "$size" -gt 100000 ]; then
        echo "Captured $out (attempt $attempt, $size bytes)"
        return 0
      fi
      echo "::warning::Screenshot for $mode looks blank ($size bytes), retrying (attempt $attempt)"
      continue
    fi
    echo "::warning::VibeAlarm not running for mode $mode (attempt $attempt)"
  done
  echo "::error::Could not capture $mode: app is not running (crash?)"
  mkdir -p "$OUT_DIR/crashes"
  xcrun simctl spawn "$UDID" log show --last 2m --style compact \
    --predicate 'process == "VibeAlarm"' > "$OUT_DIR/crashes/log-$mode.txt" 2>&1 || true
  tail -n 60 "$OUT_DIR/crashes/log-$mode.txt" || true
  FAILED=1
}

capture_screen "home"     "01-alarms"
capture_screen "editor"   "02-wake-time-editor"
capture_screen "calendar" "03-calendar"
capture_screen "sources"  "04-sources"
capture_screen "widgets"  "05-widgets"
capture_screen "search"   "06-holiday-catalog"
capture_screen "byok"     "07-parse-notice"

ls -lh "$OUT_DIR"
exit "$FAILED"
