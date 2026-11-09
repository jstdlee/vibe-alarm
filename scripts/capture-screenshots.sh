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
# `simctl bootstatus -b` can block forever on a freshly created device, so poll with a hard cap.
python3 - "$UDID" <<'PY'
import json, subprocess, sys, time

udid = sys.argv[1]
deadline = time.time() + 240
while time.time() < deadline:
    listed = subprocess.run(["xcrun", "simctl", "list", "devices", "-j"],
                            capture_output=True, text=True).stdout
    for devices in json.loads(listed)["devices"].values():
        for device in devices:
            if device["udid"] == udid and device["state"] == "Booted":
                sys.exit(0)
    time.sleep(5)
print("simulator did not reach Booted within 4 minutes", file=sys.stderr)
sys.exit(1)
PY
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

# Print CONTENT or BLANK. A frame is blank when the area below the status bar
# is essentially one color, which is what the empty launch screen looks like.
screenshot_verdict() {
  python3 - "$1" <<'PY'
import struct, sys, zlib

path = sys.argv[1]
data = open(path, "rb").read()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    print("BLANK")
    sys.exit(0)

def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c

pos = 8
width = height = color = None
idat = b""
while pos + 8 <= len(data):
    length = struct.unpack(">I", data[pos:pos + 4])[0]
    kind = data[pos + 4:pos + 8]
    chunk = data[pos + 8:pos + 8 + length]
    pos += 12 + length
    if kind == b"IHDR":
        width, height, bit, color = struct.unpack(">IIBB", chunk[:10])
        if bit != 8 or color not in (2, 6) or chunk[10] != 0:
            print("BLANK")
            sys.exit(0)
    elif kind == b"IDAT":
        idat += chunk
    elif kind == b"IEND":
        break

raw = zlib.decompress(idat)
channels = 3 if color == 2 else 4
stride = width * channels
rows = []
index = 0
prev = bytearray(stride)
for _ in range(height):
    filt = raw[index]
    index += 1
    row = bytearray(raw[index:index + stride])
    index += stride
    if filt == 1:
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            row[x] = (row[x] + left) & 255
    elif filt == 2:
        for x in range(stride):
            row[x] = (row[x] + prev[x]) & 255
    elif filt == 3:
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
    elif filt == 4:
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            up = prev[x]
            up_left = prev[x - channels] if x >= channels else 0
            row[x] = (row[x] + paeth(left, up, up_left)) & 255
    elif filt != 0:
        print("BLANK")
        sys.exit(0)
    prev = row
    rows.append(row)

top = max(80, int(height * 0.08))
step = max(1, min(width, height) // 80)
buckets = {}
samples = 0
for y in range(top, height, step):
    row = rows[y]
    for x in range(0, width, step):
        pixel = row[x * channels:x * channels + 3]
        key = (pixel[0] // 8, pixel[1] // 8, pixel[2] // 8)
        buckets[key] = buckets.get(key, 0) + 1
        samples += 1
dominant = max(buckets.values()) if buckets else samples
print("BLANK" if samples == 0 or dominant / samples >= 0.98 else "CONTENT")
PY
}

capture_screen() {
  local mode="$1"
  local out="$2${SUFFIX:+$SUFFIX}.png"
  local attempt size
  for attempt in 1 2 3 4; do
    xcrun simctl terminate "$UDID" com.jstdlee.vibealarm 2>/dev/null || true
    sleep 2
    xcrun simctl launch "$UDID" com.jstdlee.vibealarm \
      -ui-preview-screen "$mode" -ui-preview-theme "${THEME:-standard}" >/dev/null 2>&1 || true
    sleep 8
    if app_running; then
      # Let the first frame settle; the Intel simulator can hold the launch screen for seconds.
      sleep 10
      # The Intel simulator can keep the launch screen up after the process is
      # running. Poll until the frame has real content. A near-uniform image is
      # the empty window: file size alone accepted a 76 KB white screen.
      local deadline verdict size
      deadline=$((SECONDS + 36))
      while true; do
        xcrun simctl io "$UDID" screenshot "$OUT_DIR/$out"
        size=$(stat -f%z "$OUT_DIR/$out")
        if ! app_running; then
          echo "::warning::VibeAlarm exited while rendering $mode (attempt $attempt)"
          rm -f "$OUT_DIR/$out"
          break
        fi
        verdict="$(screenshot_verdict "$OUT_DIR/$out")"
        if [ "$size" -gt 60000 ] && [ "$verdict" = "CONTENT" ]; then
          echo "Captured $out (attempt $attempt, $size bytes)"
          return 0
        fi
        echo "::warning::Screenshot for $mode is blank ($size bytes, $verdict)"
        if [ "$SECONDS" -ge "$deadline" ]; then
          rm -f "$OUT_DIR/$out"
          break
        fi
        sleep 4
      done
      continue
    fi
    echo "::warning::VibeAlarm not running for mode $mode (attempt $attempt)"
  done
  echo "::error::Could not capture $mode (blank frame or the app was not running)"
  mkdir -p "$OUT_DIR/crashes"
  xcrun simctl spawn "$UDID" log show --last 2m --style compact \
    --predicate 'process == "VibeAlarm"' > "$OUT_DIR/crashes/log-$mode.txt" 2>&1 || true
  tail -n 60 "$OUT_DIR/crashes/log-$mode.txt" || true
  FAILED=1
}

BASE_OUT="$OUT_DIR"
xcrun simctl ui "$UDID" appearance light 2>/dev/null || true
for theme in standard bedside; do
  THEME="$theme"
  OUT_DIR="$BASE_OUT/$theme"
  mkdir -p "$OUT_DIR"
  echo "Capturing theme $theme"
  capture_screen "home"     "01-alarms"
  capture_screen "editor"   "02-wake-time-editor"
  capture_screen "editor-repeat" "02b-repeat-sheet"
  capture_screen "calendar" "03-calendar"
  capture_screen "sources"  "04-sources"
  capture_screen "widgets"  "05-widgets"
  capture_screen "search"   "06-holiday-catalog"
  capture_screen "byok"     "07-parse-notice"
done

# The editor is the screen whose materials change between light and dark.
# One extra frame per appearance is enough to check the discs; the light set above stays light.
xcrun simctl ui "$UDID" appearance dark 2>/dev/null || true
for theme in standard bedside; do
  THEME="$theme"
  OUT_DIR="$BASE_OUT/$theme"
  echo "Capturing dark editor for $theme"
  capture_screen "editor" "02-wake-time-editor-dark"
done
xcrun simctl ui "$UDID" appearance light 2>/dev/null || true

ls -lh "$OUT_DIR"
exit "$FAILED"
