#!/usr/bin/env bash
# Installation prerequisites, laptop and phone. Read-only on the phone. Prints PASS / FAIL / WARN per item
# and the manual items no script can check. Exit 0 only when every automatic check passes.
set -u
source "$(dirname "$0")/lib.sh"
FAILS=0

echo "== Laptop"
for t in adb fastboot unzip python3 sha256sum curl; do
  command -v "$t" >/dev/null && ok "$t: $(command -v "$t")" || bad "$t missing"
done
info "the official installer uses its own bundled fastboot (staging/.../bin-linux-x86/fastboot), not the system one"
free=$(df --output=avail -B1 "$ROOT" | tail -1)
(( free > 8 * 1024**3 )) && ok "free disk $(numfmt --to=iec "$free") (ZIP 2.1 GB + extracted 4.4 GB)" || bad "free disk only $(numfmt --to=iec "$free"); need 8 GB"
if groups | grep -qw plugdev || grep -qs 'ff4203' /usr/lib/udev/rules.d/*.rules /etc/udev/rules.d/*.rules; then
  ok "fastboot USB access: plugdev group or a udev rule for the fastboot interface"
else
  warn "no udev rule for fastboot found: if 'fastboot devices' shows 'no permissions', the official guide suggests running fastboot as root"
fi

echo "== Downloads"
"$ROOT/scripts/03-verify-downloads.sh" >/dev/null 2>&1 && ok "all downloads verified" || bad "downloads not all verified (run 03-verify-downloads.sh or download-status.sh)"
[[ -f $ROOT/staging/PREPARED.ok ]] && ok "factory ZIP extracted and installer audited (05-prepare-eos-flash.sh)" || bad "05-prepare-eos-flash.sh has not prepared the staging folder"

echo "== Phone (read-only)"
if "$ROOT/scripts/01-identify-device.sh" >/dev/null 2>&1; then ok "identity: OnePlus AC2001 avicii, serial $SERIAL"; else bad "identity check failed (run 01-identify-device.sh)"; fi
if gate_fresh identity && "$ROOT/scripts/02-check-firmware.sh" >/dev/null 2>&1; then ok "firmware: stock Android 12, F.$MIN_STOCK_F_BUILD or newer"; else bad "firmware check failed (run 02-check-firmware.sh)"; fi
if adb devices | grep -qE "^$SERIAL\s+device"; then
  P=$(mktemp); trap 'rm -f "$P"' EXIT
  adb -s "$SERIAL" shell getprop | tr -d '\r' >"$P"
  level=$(adb -s "$SERIAL" shell dumpsys battery | tr -d '\r' | sed -n 's/^ *level: //p')
  (( level > 50 )) && ok "battery $level% (guide: above 50%)" || bad "battery $level%: the guide requires above 50%"
  [[ $(prop "$P" sys.oem_unlock_allowed) == 1 ]] && ok "OEM unlocking is allowed in Developer options" || bad "enable OEM unlocking in Developer options"
  accounts=$(adb -s "$SERIAL" shell dumpsys account | tr -d '\r' | sed -n 's/^ *Accounts: //p' | head -1)
  [[ $accounts == 0 ]] && ok "no accounts signed in (no Factory Reset Protection lock)" || bad "$accounts account(s) signed in: log out first (FRP)"
  if [[ $(prop "$P" ro.boot.flash.locked) == 1 ]]; then
    warn "bootloader LOCKED: unlocking (fastboot oem unlock) is a separate manual step that ERASES the phone"
  else ok "bootloader unlocked"; fi
  [[ -n $(prop "$P" ro.boot.slot_suffix) ]] && ok "A/B device, active slot $(prop "$P" ro.boot.slot_suffix)"
  [[ $(prop "$P" ro.virtual_ab.enabled) == true ]] &&
    info "Virtual A/B: an unfinished update merge blocks the installer's erase step; 06-flash-eos.sh checks snapshot-update-status"
fi

echo "== Manual (no script can check these)"
info "back up everything you want to keep (e.g. 'adb pull /sdcard/. backup/'); unlocking and flashing erase all of it"
info "the stock OS works: SIM calls, SMS, mobile data (VoLTE once, for IMS provisioning), if a SIM is available"
info "the PC's internet does not come from this phone's hotspot (check 'ip route'); the phone will be offline for a while"

echo
(( FAILS == 0 )) && echo "PREREQUISITES: ALL AUTOMATIC CHECKS PASS (do the manual items too)" || { echo "PREREQUISITES: $FAILS missing"; exit 1; }
