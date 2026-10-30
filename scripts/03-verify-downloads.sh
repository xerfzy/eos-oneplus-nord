#!/usr/bin/env bash
# Re-hashes every finished download against the publisher's SHA-256 (scripts/downloads.tsv), plus the
# extracted boot.img and the installer in staging/. Laptop files only. Exit 0 only if everything matches.
set -u
source "$(dirname "$0")/lib.sh"
FAILS=0
REPORT="$ROOT/checksums/verification-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p "$ROOT/checksums"
{
  echo "== Downloads (expected SHA-256 from images.ecloud.global API / .sha256sum, GitHub release asset digest)"
  while IFS=$'\t' read -r id dest url size sha; do
    [[ -z $id || $id == \#* ]] && continue
    f="$ROOT/$dest"
    if [[ ! -f $f ]]; then
      [[ -f $f.part ]] && bad "$(basename "$f"): incomplete ($(stat -c %s "$f.part") of $size bytes)" || bad "$(basename "$f"): missing"
      continue
    fi
    got=$(sha "$f")
    [[ $(stat -L -c %s "$f") == "$size" && $got == "$sha" ]] && ok "$(basename "$f") $got" ||
      bad "$(basename "$f") got $got, expected $sha"
  done <"$ROOT/scripts/downloads.tsv"

  echo "== Official installer (extracted by 05-prepare-eos-flash.sh)"
  if [[ -d $STAGING ]]; then
    [[ $(sha "$STAGING/flash_avicii_factory.sh") == "$FLASH_SH_SHA256" && $(sha "$STAGING/factory.common") == "$FACTORY_COMMON_SHA256" ]] &&
      ok "flash_avicii_factory.sh and factory.common match the audited hashes" || bad "installer in staging differs from the audited hashes"
  else
    info "not extracted yet (05-prepare-eos-flash.sh)"
  fi

  echo "== Unmodified boot.img (for Magisk)"
  if [[ -f $BOOT_UNMODIFIED ]]; then
    [[ $(sha "$BOOT_UNMODIFIED") == "$BOOT_UNMODIFIED_SHA256" ]] && ok "boot.img $BOOT_UNMODIFIED_SHA256 (from the verified ZIP)" ||
      bad "boot.img does not match $BOOT_UNMODIFIED_SHA256"
  else
    info "boot.img not extracted yet (waits for the verified ZIP)"
  fi
} 2>&1 | tee "$REPORT"
FAILS=$(grep -c 'FAIL' "$REPORT")
echo "Saved $REPORT"
(( FAILS == 0 )) && echo "DOWNLOADS: ALL VERIFIED" || { echo "DOWNLOADS: $FAILS problem(s)"; exit 1; }
