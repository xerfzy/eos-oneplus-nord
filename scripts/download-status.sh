#!/usr/bin/env bash
# Download dashboard: file, size, progress, speed, ETA, worker state and verification.
#   download-status.sh            one reading (speed measured over 3 s)
#   download-status.sh --watch    refreshes every 2 s until Ctrl-C
# Reads only laptop files: scripts/downloads.tsv, logs/state/*.status and the file sizes on disk.
set -u
source "$(dirname "$0")/lib.sh"
LIST="$ROOT/scripts/downloads.tsv"
declare -A last

human() { numfmt --to=iec --suffix=B --format='%.1f' "$1"; }

current_size() {  # final file, else .part, else 0
  if [[ -f $ROOT/$1 ]]; then stat -L -c %s "$ROOT/$1"; elif [[ -f $ROOT/$1.part ]]; then stat -c %s "$ROOT/$1.part"; else echo 0; fi
}

unit_state() {
  local u state out=""
  for u in eos-downloads eos-extract-boot; do
    state=$(systemctl --user is-active "$u" 2>/dev/null)
    [[ $state == active ]] && out+="$u=active  "
  done
  echo "${out:-no download units active}"
}

render() {  # render <seconds since last sample>
  local dt=$1 id dest url size sha have pct speed eta status verify
  printf 'downloads  %s\n' "$(date '+%F %T')"
  printf 'units: %s\n\n' "$(unit_state)"
  printf '%-56s %10s %10s %6s %10s %8s  %s\n' FILE HAVE SIZE DONE SPEED ETA STATUS
  while IFS=$'\t' read -r id dest url size sha; do
    [[ -z $id || $id == \#* ]] && continue
    have=$(current_size "$dest")
    pct=$(( have * 100 / size ))
    speed=0
    [[ -n ${last[$id]:-} ]] && (( dt > 0 )) && speed=$(( (have - ${last[$id]}) / dt ))
    (( speed < 0 )) && speed=0
    last[$id]=$have
    if (( speed > 0 )); then eta=$(date -u -d "@$(( (size - have) / speed ))" +%H:%M:%S); else eta=-; fi
    status=$(cat "$ROOT/logs/state/$id.status" 2>/dev/null || echo "QUEUED")
    # A finished file the worker has not reached yet: hash it here if it is small.
    if [[ $status != VERIFIED* && -f $ROOT/$dest ]] && (( have < 200000000 )) && [[ $(sha "$ROOT/$dest") == "$sha" ]]; then
      status=VERIFIED
    fi
    if [[ $status == VERIFIED* && -f $ROOT/$dest ]]; then verify="VERIFIED (sha256 matches publisher)"
    elif [[ $status == CHECKSUM* ]]; then verify="MISMATCH"
    else verify="${status%% *}; not verified yet"; fi
    printf '%-56s %10s %10s %5s%% %9s/s %8s  %s\n' "$(basename "$dest")" "$(human "$have")" "$(human "$size")" \
      "$pct" "$(human "$speed")" "$eta" "$verify"
  done <"$LIST"
  echo
  if [[ -f $BOOT_UNMODIFIED ]]; then
    echo "boot.img for Magisk: extracted, $(cat "$(dirname "$BOOT_UNMODIFIED")/SHA256SUMS" 2>/dev/null)"
  else
    echo "boot.img for Magisk: waits for the verified /e/OS ZIP"
  fi
  echo "last worker log line: $(tail -n1 "$ROOT/logs/dl-worker.log" 2>/dev/null)"
}

prime() { while IFS=$'\t' read -r id dest _; do [[ -z $id || $id == \#* ]] && continue; last[$id]=$(current_size "$dest"); done <"$LIST"; }

if [[ ${1:-} == --watch ]]; then
  prime; sleep 2
  while :; do out=$(render 2); clear; printf '%s\n' "$out"; sleep 2; done
else
  prime; sleep 3; render 3
fi
