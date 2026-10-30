#!/usr/bin/env bash
# Starts (or resumes) the background downloads and the boot.img extraction as systemd user units.
# Safe to run any number of times: it never starts a second worker.
# The units outlive this terminal. They stop at logout or reboot
# unless lingering is on (`loginctl enable-linger $USER`); running this script again resumes them.
set -u
source "$(dirname "$0")/lib.sh"

start_unit() {  # start_unit <unit> <script>
  if systemctl --user is-active --quiet "$1"; then echo "$1: already running"; return; fi
  if systemd-run --user --unit="$1" --collect --description="eos-oneplus-nord $1" /bin/bash "$ROOT/scripts/$2" >/dev/null 2>&1; then
    echo "$1: started as a systemd user unit"
  else
    setsid nohup /bin/bash "$ROOT/scripts/$2" >/dev/null 2>&1 </dev/null &
    echo "$1: systemd-run unavailable; started detached with setsid (pid $!)"
  fi
}

if pgrep -fx "/bin/bash $ROOT/scripts/dl-worker.sh" >/dev/null; then
  echo "download worker: already running (pid $(pgrep -fx "/bin/bash $ROOT/scripts/dl-worker.sh" | tr '\n' ' '))"
else
  start_unit eos-downloads dl-worker.sh
fi
if [[ -f $BOOT_UNMODIFIED ]]; then
  echo "boot.img: already extracted"
elif pgrep -fx "/bin/bash $ROOT/scripts/extract-boot-after-verify.sh" >/dev/null; then
  echo "boot.img extraction: already waiting"
else
  start_unit eos-extract-boot extract-boot-after-verify.sh
fi
[[ $(loginctl show-user "$USER" -p Linger --value 2>/dev/null) == yes ]] ||
  echo "note: lingering is off, so a logout or reboot stops the downloads; run this script again to resume"
echo "progress: $ROOT/scripts/download-status.sh --watch"
