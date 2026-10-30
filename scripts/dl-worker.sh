#!/usr/bin/env bash
# Resumable download worker. Runs detached (systemd user unit, see start-downloads.sh).
# Reads scripts/downloads.tsv: id, dest (relative to the repository root), url, size, sha256.
# A file gets its final name only after its size and the publisher's SHA-256 both match.
# Network errors (DNS, stalls, resets) never end the worker: it backs off and resumes the .part file.
# Only one worker may run: a second one exits at once on the lock.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$ROOT/scripts/downloads.tsv"
STATE="$ROOT/logs/state"
mkdir -p "$STATE"
exec >>"$ROOT/logs/dl-worker.log" 2>&1
exec 9>"$STATE/worker.lock"
if ! flock -n 9; then echo "$(date -Is) another worker holds the lock; pid $$ exits"; exit 0; fi
echo "$(date -Is) worker start pid $$"
echo $$ >"$STATE/worker.pid"

set_status() { printf '%s\n' "$2" >"$STATE/$1.status"; echo "$(date -Is) $1: $2"; }

fetch() {
  local id=$1 dest=$2 url=$3 size=$4 sha=$5
  local final="$ROOT/$dest" part="$ROOT/$dest.part" backoff=15 have got rc
  mkdir -p "$(dirname "$final")"
  if [[ -f $final ]]; then
    got=$(sha256sum "$final" | cut -d' ' -f1)
    if [[ $got == "$sha" ]]; then set_status "$id" "VERIFIED sha256 $got"; return 0; fi
    mv -f "$final" "$final.bad.$(date +%s)"
  fi
  while :; do
    have=$(stat -c %s "$part" 2>/dev/null || echo 0)
    if (( have > size )); then
      set_status "$id" "OVERSIZE $have > $size, restarting"; mv -f "$part" "$part.bad.$(date +%s)"; have=0
    fi
    if (( have < size )); then
      set_status "$id" "DOWNLOADING from $have"
      curl -fL --no-progress-meter -C - --connect-timeout 30 --speed-limit 1024 --speed-time 90 \
        -o "$part" "$url"
      rc=$?
      if (( rc != 0 )); then
        set_status "$id" "RETRY in ${backoff}s (curl exit $rc)"
        sleep "$backoff"; (( backoff = backoff < 300 ? backoff * 2 : 300 ))
      else
        backoff=15
      fi
      continue
    fi
    set_status "$id" "HASHING"
    got=$(sha256sum "$part" | cut -d' ' -f1)
    if [[ $got == "$sha" ]]; then
      mv -f "$part" "$final"; set_status "$id" "VERIFIED sha256 $got"; return 0
    fi
    mv -f "$part" "$final.bad.$(date +%s)"
    set_status "$id" "CHECKSUM MISMATCH got $got want $sha; kept as .bad, downloading again"
  done
}

while IFS=$'\t' read -r id dest url size sha; do
  [[ -z $id || $id == \#* ]] && continue
  fetch "$id" "$dest" "$url" "$size" "$sha"
done <"$LIST"
echo "$(date -Is) worker done"
rm -f "$STATE/worker.pid"
