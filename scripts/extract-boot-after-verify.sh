#!/usr/bin/env bash
# Waits until the /e/OS factory ZIP has passed its published SHA-256, then copies boot.img out of it,
# unmodified, for later Magisk patching on the phone. Laptop files only; never touches the phone.
# Runs detached (start-downloads.sh starts it as the user unit eos-extract-boot).
set -u
source "$(dirname "$0")/lib.sh"
exec >>"$ROOT/logs/extract-boot.log" 2>&1
echo "$(date -Is) waiting for a verified $EOS_ZIP"
until [[ -f $EOS_ZIP ]] && grep -q '^VERIFIED' "$ROOT/logs/state/eos-factory.status" 2>/dev/null; do
  sleep 60
done
[[ $(sha "$EOS_ZIP") == "$EOS_SHA256" ]] || { echo "$(date -Is) ZIP hash mismatch, nothing extracted"; exit 1; }
mkdir -p "$(dirname "$BOOT_UNMODIFIED")"
# zipfile checks each member's CRC-32 while reading; the header check confirms it is a boot image with a ramdisk.
python3 -I - "$EOS_ZIP" "$BOOT_UNMODIFIED" <<'EOF' || { echo "$(date -Is) extraction failed"; exit 1; }
import sys, zipfile, struct, os
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as z:
    data = z.read('boot.img')
assert data[:8] == b'ANDROID!', 'not an Android boot image'
kernel, _, ramdisk = struct.unpack('<3I', data[8:20])
version = struct.unpack('<I', data[40:44])[0]
assert ramdisk > 0, 'boot.img has no ramdisk'
tmp = dst + '.tmp'
open(tmp, 'wb').write(data)
os.replace(tmp, dst)
print(f'boot.img: {len(data)} bytes, header v{version}, kernel {kernel}, ramdisk {ramdisk}')
EOF
[[ $(sha "$BOOT_UNMODIFIED") == "$BOOT_UNMODIFIED_SHA256" ]] || { echo "$(date -Is) extracted boot.img has an unexpected SHA-256"; exit 1; }
(cd "$(dirname "$BOOT_UNMODIFIED")" && sha256sum boot.img >SHA256SUMS)
echo "$(date -Is) extracted $(cat "$(dirname "$BOOT_UNMODIFIED")/SHA256SUMS")"
