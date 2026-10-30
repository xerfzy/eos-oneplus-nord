#!/usr/bin/env bash
# Identifies the connected phone and proves it is a stock OnePlus Nord AC2001 (avicii), the phone named in config.env.
# Read-only: getprop, uname, pm list, dumpsys battery. Never reboots, roots, installs or writes to the phone.
# On success writes logs/gates/identity.ok, which 06-flash-eos.sh requires (at most 24 h old).
set -u
source "$(dirname "$0")/lib.sh"
FAILS=0
TS=$(date +%Y%m%d-%H%M%S)
OUT="$ROOT/device-info/identity-$TS.txt"
PROPS="$ROOT/device-info/getprop-$TS.txt"

echo "== Connected devices"
require_adb_target
A() { adb -s "$SERIAL" shell "$@" 2>&1 | tr -d '\r'; }
A getprop >"$PROPS"
p() { prop "$PROPS" "$1"; }

echo "== Identity checks (serial $SERIAL)"
check() {  # check <label> <actual> <expected>
  if [[ $2 == "$3" ]]; then ok "$1 = $2"; else bad "$1 = '$2', expected '$3'"; fi
}
check "ro.boot.serialno" "$(p ro.boot.serialno)" "$SERIAL"
check "ro.product.manufacturer" "$(p ro.product.manufacturer)" "$EXPECT_MANUFACTURER"
check "ro.product.model" "$(p ro.product.model)" "$EXPECT_MODEL"
check "ro.product.vendor.model" "$(p ro.product.vendor.model)" "$EXPECT_MODEL"
check "ro.boot.project_codename" "$(p ro.boot.project_codename)" "$EXPECT_CODENAME"
check "ro.product.device" "$(p ro.product.device)" "$EXPECT_STOCK_DEVICE"
check "ro.board.platform" "$(p ro.board.platform)" "$EXPECT_PLATFORM"
check "ro.product.cpu.abi" "$(p ro.product.cpu.abi)" "arm64-v8a"

su_found=$(A 'for f in /system/bin/su /system/xbin/su /sbin/su /debug_ramdisk/su; do [ -e $f ] && echo $f; done')
root_pkgs=$(A pm list packages | grep -iE 'magisk|kernelsu|apatch|supersu' | tr '\n' ' ')
{
  echo "# Device identity, $(date -Is) (read-only)"
  echo "Manufacturer / model : $(p ro.product.manufacturer) $(p ro.product.model) ($(p ro.vendor.oplus.market.name), region $(p ro.vendor.oplus.regionmark))"
  echo "Codename             : $(p ro.boot.project_codename) (stock device name $(p ro.product.device), product $(p ro.product.name))"
  echo "OxygenOS             : $(p ro.build.version.oplusrom), build $(p ro.build.display.id) (OTA $(p ro.build.version.ota))"
  echo "Android              : $(p ro.build.version.release) (SDK $(p ro.build.version.sdk))"
  echo "Build fingerprint    : $(p ro.build.fingerprint)"
  echo "Security patch       : $(p ro.build.version.security_patch) (vendor $(p ro.vendor.build.security_patch))"
  echo "Kernel               : $(A uname -r)"
  echo "CPU                  : $(p ro.product.cpu.abilist) on $(p ro.board.platform)"
  echo "Bootloader           : flash.locked=$(p ro.boot.flash.locked) vbmeta.device_state=$(p ro.boot.vbmeta.device_state) OEM-unlock toggle sys.oem_unlock_allowed=$(p sys.oem_unlock_allowed)"
  echo "Verified Boot        : $(p ro.boot.verifiedbootstate) (verity $(p ro.boot.veritymode))"
  echo "A/B                  : ab_update=$(p ro.build.ab_update) active slot=$(p ro.boot.slot_suffix) virtual_ab=$(p ro.virtual_ab.enabled) dynamic=$(p ro.boot.dynamic_partitions)"
  echo "Root                 : su binaries: ${su_found:-none}; root manager packages: ${root_pkgs:-none}; ro.debuggable=$(p ro.debuggable)"
  echo "Battery              : $(A dumpsys battery | sed -n 's/^ *level: //p')%"
} | tee "$OUT"
echo "Saved $OUT and $PROPS"

if (( FAILS == 0 )); then
  write_gate identity "model=$EXPECT_MODEL codename=$EXPECT_CODENAME build=$(p ro.build.display.id)"
  echo "IDENTITY: PASS (gate written, valid 24 h)"
else
  rm -f "$GATES/identity.ok"
  echo "IDENTITY: FAIL ($FAILS mismatches). Nothing destructive may run against this phone."; exit 1
fi
