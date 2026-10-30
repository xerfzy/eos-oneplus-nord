#!/usr/bin/env bash
# Checks the phone's stock firmware against the /e/OS 4.4.1 (A16) requirements for avicii. Read-only.
#   Official guide: "install the latest stock OS version 12 build" before the first /e/OS install.
#   The factory ZIP then flashes its own firmware (AC2003_11_F.23, per /e/OS's security-updates page)
#   to both slots, so the phone must be on Android 12 stock, AC2001 F.23 or newer.
# On success writes logs/gates/firmware.ok, which 06-flash-eos.sh requires (at most 24 h old).
set -u
source "$(dirname "$0")/lib.sh"
FAILS=0
gate_fresh identity || die "run 01-identify-device.sh first (no identity gate from the last 24 h)"
require_adb_target
PROPS=$(mktemp); trap 'rm -f "$PROPS"' EXIT
adb -s "$SERIAL" shell getprop | tr -d '\r' >"$PROPS"
p() { prop "$PROPS" "$1"; }

echo "== Firmware checks"
[[ $(p ro.boot.serialno) == "$SERIAL" ]] && ok "same phone ($SERIAL)" || bad "serial changed"
[[ $(p ro.build.version.release) == 12 && $(p ro.build.version.sdk) == 31 ]] &&
  ok "Android 12 (SDK 31) stock, as the guide requires" ||
  bad "Android $(p ro.build.version.release): the guide requires the latest stock Android 12 build"
build=$(p ro.build.display.id)
if [[ $build =~ ^${EXPECT_MODEL}_11_F\.([0-9]+)$ ]]; then
  f=${BASH_REMATCH[1]}
  if (( f >= MIN_STOCK_F_BUILD )); then ok "stock build $build (F.$f >= F.$MIN_STOCK_F_BUILD bundled in the /e/OS ZIP)"
  else bad "stock build $build is older than F.$MIN_STOCK_F_BUILD: update OxygenOS (Settings > System updates) first"; fi
else
  bad "unrecognised build '$build' (expected ${EXPECT_MODEL}_11_F.<n>)"
fi
[[ $(p ro.build.tags) == release-keys && $(p ro.build.type) == user ]] && ok "official user/release-keys build" ||
  bad "not an official stock build ($(p ro.build.type)/$(p ro.build.tags))"
[[ $(p ro.vendor.oplus.regionmark) == IN ]] &&
  warn "India build; the /e/OS ZIP flashes EU (AC2003) F.23 firmware to both slots. /e/OS lists AC2001 as supported; no official source covers rollback protection across regions."
warn "'latest' cannot be checked offline: confirm Settings > System updates says the phone is up to date"

if (( FAILS == 0 )); then
  write_gate firmware "build=$build android=$(p ro.build.version.release)"
  echo "FIRMWARE: PASS (gate written, valid 24 h)"
else
  rm -f "$GATES/firmware.ok"; echo "FIRMWARE: FAIL"; exit 1
fi
