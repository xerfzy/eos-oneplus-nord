#!/usr/bin/env bash
# ┌──────────────────────────────────────────────────────────────────────────────────────────────┐
# │ ERASES THE PHONE: every app and file. Back up first and read docs/INSTALL-EOS.md.            │
# └──────────────────────────────────────────────────────────────────────────────────────────────┘
# Guarded wrapper around the official /e/OS installer (flash_avicii_factory.sh, unchanged).
# It adds the checks the official script lacks, then runs it exactly as the guide says:
#   chmod +x flash_avicii_factory.sh && ./flash_avicii_factory.sh
# It never unlocks the bootloader and never reboots the phone into fastboot itself: the phone must
# already be unlocked and sitting in the bootloader (Volume Up + Volume Down + Power from power-off).
#
#   06-flash-eos.sh --erase-and-flash [--accept-unknown-snapshot-state]
set -u
source "$(dirname "$0")/lib.sh"
LOG="$ROOT/logs/flash-$(date +%Y%m%d-%H%M%S).log"
accept_unknown_snapshot=0
[[ ${1:-} == --erase-and-flash ]] || die "refusing: pass --erase-and-flash to confirm that the phone may be erased"
require_serial
[[ ${2:-} == --accept-unknown-snapshot-state ]] && accept_unknown_snapshot=1
FAILS=0

echo "== Gates (laptop)"
gate_fresh identity && ok "identity verified in the last 24 h ($(sed -n 4p "$GATES/identity.ok"))" || bad "run 01-identify-device.sh (phone booted, USB debugging on) first"
gate_fresh firmware && ok "firmware verified in the last 24 h ($(sed -n 4p "$GATES/firmware.ok"))" || bad "run 02-check-firmware.sh first"
[[ -f $ROOT/staging/PREPARED.ok ]] && ok "staging prepared" || bad "run 05-prepare-eos-flash.sh first"
if [[ -d $STAGING ]]; then
  [[ $(sha "$STAGING/flash_avicii_factory.sh") == "$FLASH_SH_SHA256" && $(sha "$STAGING/factory.common") == "$FACTORY_COMMON_SHA256" ]] &&
    ok "installer identical to the audited copy" || bad "installer in staging changed since the audit"
fi
(( FAILS == 0 )) || die "$FAILS gate(s) missing; nothing was sent to the phone"

FB="$STAGING/bin-linux-x86/fastboot"
echo "== Phone in fastboot mode"
refuse_protected
mapfile -t devs < <("$FB" devices 2>/dev/null | awk '$2 == "fastboot" {print $1}')
# The upstream find_device names the last serial it saw, not the matched one, when several are connected.
(( ${#devs[@]} == 1 )) || die "need exactly one device in fastboot mode, found ${#devs[@]}: ${devs[*]:-none}"
[[ ${devs[0]} == "$SERIAL" ]] || die "the fastboot device is ${devs[0]}, not $SERIAL from config.env"
ok "one fastboot device: $SERIAL"
v() { "$FB" -s "$SERIAL" getvar "$1" 2>&1 | sed -n "s/^$1: *//p" | head -1; }
product=$(v product); unlocked=$(v unlocked); userspace=$(v is-userspace); snapshot=$(v snapshot-update-status)
[[ $product == *"$EXPECT_PLATFORM"* ]] && ok "product: $product" || die "product '$product' does not contain '$EXPECT_PLATFORM'"
[[ $unlocked == yes ]] && ok "bootloader unlocked" || die "bootloader not unlocked ('$unlocked'); unlocking is a separate manual step"
[[ $userspace == yes ]] && die "the phone is in fastbootd; start from the bootloader (the installer switches to fastbootd itself)"
ok "in the bootloader (not fastbootd)"
case $snapshot in
  none) ok "snapshot-update-status: none (no unfinished Virtual A/B merge)" ;;
  snapshotted|merging)
    die "snapshot-update-status: $snapshot. fastbootd refuses to erase userdata/metadata during a merge, so the installer would stop
       half way. Options (not run by this script): boot stock once and let the merge finish, or
       '$FB -s $SERIAL snapshot-update cancel' (AOSP: 'may make the device unbootable until it is reflashed')." ;;
  *)
    if (( accept_unknown_snapshot )); then
      warn "snapshot-update-status not reported by the bootloader ('$snapshot'); continuing because --accept-unknown-snapshot-state was given"
    else
      die "snapshot-update-status not reported by the bootloader ('$snapshot'). fastbootd reports it: run
         fastboot -s $SERIAL reboot fastboot
         fastboot -s $SERIAL getvar snapshot-update-status
         fastboot -s $SERIAL reboot bootloader
       and re-run with --accept-unknown-snapshot-state only if it said 'none'."
    fi ;;
esac

cat <<EOF

About to run the official installer on $SERIAL ($product). It will:
  flash firmware and boot/dtbo/recovery/vbmeta to both slots, flash system/vendor/product/system_ext/odm,
  ERASE userdata and metadata (every app and file on the phone), then reboot into /e/OS.
Full session log: $LOG
EOF
read -rp "Type 'ERASE $SERIAL' to continue: " answer
[[ $answer == "ERASE $SERIAL" ]] || die "not confirmed; nothing was flashed"

cd "$STAGING"
chmod +x flash_avicii_factory.sh
script -q -e -c ./flash_avicii_factory.sh "$LOG"
rc=$?
echo "Installer exited with $rc. Log: $LOG"
exit "$rc"
