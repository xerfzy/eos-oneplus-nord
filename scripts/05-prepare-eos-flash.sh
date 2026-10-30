#!/usr/bin/env bash
# Laptop-only flashing preparation: unzips the verified /e/OS factory ZIP into staging/, checks that the
# installer is byte-identical to the audited copy and that every image it names is present, and prints
# what it will write. Never touches the phone. Writes staging/PREPARED.ok for 06-flash-eos.sh.
set -u
source "$(dirname "$0")/lib.sh"

[[ -f $EOS_ZIP ]] || die "the factory ZIP is not downloaded yet (see download-status.sh)"
echo "Hashing $(basename "$EOS_ZIP") ..."
[[ $(stat -L -c %s "$EOS_ZIP") == "$EOS_SIZE" && $(sha "$EOS_ZIP") == "$EOS_SHA256" ]] || die "ZIP does not match the published SHA-256"
echo "ZIP verified."

if [[ ! -f $STAGING/.extracted ]]; then
  rm -rf "$STAGING.tmp"; mkdir -p "$STAGING.tmp"
  unzip -q "$EOS_ZIP" -d "$STAGING.tmp" || die "unzip failed (CRC or disk error)"
  rm -rf "$STAGING"; mv "$STAGING.tmp" "$STAGING"; touch "$STAGING/.extracted"
fi
cd "$STAGING"

[[ $(sha flash_avicii_factory.sh) == "$FLASH_SH_SHA256" ]] || die "flash_avicii_factory.sh differs from the audited copy"
[[ $(sha factory.common) == "$FACTORY_COMMON_SHA256" ]] || die "factory.common differs from the audited copy"
for d in bin-linux-x86 bin-msys; do [[ -d $d ]] || die "missing $d/ (the guide says it must be there)"; done
[[ -x bin-linux-x86/fastboot ]] || chmod +x bin-linux-x86/fastboot

# The installer's own image lists: only its assignment lines are evaluated, nothing in it runs.
eval "$(grep -E '^(PRODUCT_ID|FLASH_AB_FW_IMGS|FLASH_AB_IMGS|FLASH_A_IMGS|ERASE_IMGS)=' flash_avicii_factory.sh)"
missing=0
for img in $FLASH_AB_FW_IMGS $FLASH_AB_IMGS $FLASH_A_IMGS; do
  [[ -s $img.img ]] || { echo "missing $img.img"; missing=1; }
done
(( missing == 0 )) || die "images missing from the extracted ZIP"

cat <<EOF
Staging folder: $STAGING
The official installer (flash_avicii_factory.sh, audited) will, on the phone with product '$PRODUCT_ID':
  1. check 'fastboot getvar unlocked' and stop if the bootloader is locked
  2. reboot from the bootloader to fastbootd ('fastboot reboot fastboot')
  3. flash to BOTH slots (_a and _b), firmware: $FLASH_AB_FW_IMGS
  4. flash to BOTH slots: $FLASH_AB_IMGS
  5. flash to the current slot (logical, in super): $FLASH_A_IMGS
  6. ERASE: $ERASE_IMGS   (all apps and data on the phone)
  7. reboot into /e/OS
It uses its bundled fastboot: $STAGING/bin-linux-x86/fastboot ($("$STAGING/bin-linux-x86/fastboot" --version 2>/dev/null | head -1))
EOF
{ echo "prepared=$(date -Is)"; echo "zip_sha256=$EOS_SHA256"; echo "flash_sh_sha256=$FLASH_SH_SHA256"; echo "factory_common_sha256=$FACTORY_COMMON_SHA256"; } >"$ROOT/staging/PREPARED.ok"
echo "PREPARED (staging/PREPARED.ok written). Nothing was sent to the phone."
