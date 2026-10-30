#!/usr/bin/env bash
# Magisk rooting preparation, laptop only: verifies the Magisk APK and the unmodified boot.img taken from
# the verified /e/OS ZIP, confirms boot.img is the image to patch, and prints the later steps.
# Patches nothing, installs nothing, flashes nothing.
set -u
source "$(dirname "$0")/lib.sh"
FAILS=0

echo "== Magisk"
[[ -f $MAGISK_APK && $(sha "$MAGISK_APK") == "$MAGISK_SHA256" ]] &&
  ok "$(basename "$MAGISK_APK") matches the GitHub release digest $MAGISK_SHA256" || bad "Magisk APK missing or wrong hash"

echo "== Image to patch"
info "the Nord has no init_boot or vendor_boot partition (ls /dev/block/by-name); boot.img carries the ramdisk"
if [[ -f $BOOT_UNMODIFIED ]]; then
  [[ $(sha "$BOOT_UNMODIFIED") == "$BOOT_UNMODIFIED_SHA256" ]] && ok "boot.img is the one inside the verified ZIP ($BOOT_UNMODIFIED_SHA256)" || bad "boot.img changed"
  python3 -I - "$BOOT_UNMODIFIED" <<'EOF' || FAILS=$((FAILS + 1))
import sys, struct
h = open(sys.argv[1], 'rb').read(4096)
assert h[:8] == b'ANDROID!', 'not a boot image'
kernel, _, ramdisk = struct.unpack('<3I', h[8:20]); version = struct.unpack('<I', h[40:44])[0]
osv = struct.unpack('<I', h[44:48])[0]; v, lvl = osv >> 11, osv & 0x7ff
print(f'  PASS  boot.img header v{version}, kernel {kernel} B, ramdisk {ramdisk} B, '
      f'Android {v >> 14}, patch {2000 + (lvl >> 4)}-{lvl & 0xf:02d}')
assert ramdisk > 0
EOF
else
  bad "boot.img not extracted yet: it appears once the /e/OS ZIP is verified (start-downloads.sh)"
fi

S=${SERIAL:-<serial>}
cat <<EOF

After /e/OS $EOS_VERSION is installed and set up, with USB debugging on (full guide: docs/ROOTING.md;
official method: https://topjohnwu.github.io/Magisk/install.html, "Patching Images"):
  1. Settings > About phone: the build must still be $EOS_VERSION. If /e/OS has updated itself,
     this boot.img no longer matches: take boot.img from the matching factory ZIP instead.
  2. adb -s $S install -r downloads/magisk/$(basename "$MAGISK_APK")
  3. adb -s $S push downloads/eos/unmodified/boot.img /sdcard/Download/
  4. In Magisk: check "Ramdisk: Yes", then Install > "Patch firmware / image" > "Select from storage" > boot.img
  5. adb -s $S pull /sdcard/Download/magisk_patched-<version>_<random>.img downloads/magisk/
  6. adb -s $S reboot bootloader
     fastboot -s $S flash boot downloads/magisk/magisk_patched-<version>_<random>.img   (active slot)
     fastboot -s $S reboot; open Magisk and accept its "environment fix" reboot
  Never flash an image patched on another phone (Magisk's own warning).
  Keep downloads/eos/unmodified/boot.img: flashing it back removes root.
EOF
echo
(( FAILS == 0 )) && echo "MAGISK PREPARATION: READY" || { echo "MAGISK PREPARATION: $FAILS problem(s)"; exit 1; }
