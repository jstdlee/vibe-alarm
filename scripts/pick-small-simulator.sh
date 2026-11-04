#!/usr/bin/env bash
# Print the UDID of a 375 x 667 iPhone simulator (SE class) for the small-phone layout pass.
# Reuses an existing device when the runtime ships one, otherwise creates it.
set -euo pipefail

UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys, re
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
for runtime in sorted(devices, key=version, reverse=True):
    if "iOS" not in runtime:
        continue
    phones = [d for d in devices[runtime] if re.search(r"iPhone (SE|8|7|6s)\\b", d["name"])]
    if phones:
        phones.sort(key=lambda d: d["name"])
        print(phones[0]["udid"])
        break
' || true)"

if [ -n "${UDID:-}" ]; then
  echo "$UDID"
  exit 0
fi

# No SE-class device exists yet: create one on the newest runtime that provides the device type.
RUNTIME_ID="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and "iOS" in r.get("identifier", "")]
runtimes.sort(key=lambda r: r.get("version", "0"), reverse=True)
print(runtimes[0]["identifier"])
')"
DEVICE_TYPE="$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
types = [t for t in json.load(sys.stdin)["devicetypes"] if t["identifier"] == "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"]
print(types[0]["identifier"] if types else "com.apple.CoreSimulator.SimDeviceType.iPhone-8")
')"
xcrun simctl create "iPhone SE (small pass)" "$DEVICE_TYPE" "$RUNTIME_ID"
