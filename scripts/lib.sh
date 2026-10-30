# Shared constants and helpers. Sourced by the other scripts, never run on its own.
# Device values were read from a stock OnePlus Nord AC2001 and the release values from official sources
# (/e/OS image server, Magisk's GitHub release); docs/INSTALL-EOS.md says where each one comes from.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# config.env (not committed) names the one phone these scripts may act on. See config.example.env.
[[ -f $ROOT/config.env ]] && source "$ROOT/config.env"
SERIAL=${SERIAL:-}
PROTECTED_SERIALS=${PROTECTED_SERIALS:-}   # phones that must never be touched; scripts stop if one is connected

EXPECT_MANUFACTURER=OnePlus
EXPECT_MODEL=AC2001                   # India; the EU AC2003 and global AC2005 Nords are not checked here
EXPECT_CODENAME=avicii                # ro.boot.project_codename
EXPECT_STOCK_DEVICE=Nord              # ro.product.device on OxygenOS
EXPECT_PLATFORM=lito                  # ro.board.platform, and `fastboot getvar product` in the installer
MIN_STOCK_F_BUILD=23                  # the /e/OS 4.4.1 package bundles AC2003_11_F.23 firmware

EOS_VERSION=4.4.1-a16-20261021695349-official-avicii
EOS_ZIP="$ROOT/downloads/eos/IMG-e-$EOS_VERSION.zip"
EOS_SHA256=f193ad43ddd9958137f8eabe1e9eae02275312c74c9fc5cf4fbfd67747903b0d
EOS_SIZE=2152487920
STAGING="$ROOT/staging/IMG-e-$EOS_VERSION"

# The official installer files inside that ZIP, as read and audited before the first install.
FLASH_SH_SHA256=c94f5efcd97dfa45244409b8ac3ab4ccc3364d371f87aa58fa8cfb5791d52dd4
FACTORY_COMMON_SHA256=b694ba694b7b1f71141e39810bb4318c32d70f4ef01143573f0701279f0eb7df

MAGISK_APK="$ROOT/downloads/magisk/Magisk-v31.1.apk"
MAGISK_SHA256=89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7
BOOT_UNMODIFIED="$ROOT/downloads/eos/unmodified/boot.img"
BOOT_UNMODIFIED_SHA256=899e9c250b2c37d2e33af002f10548e53c331ff8d565704181a8f995e97ccb37

GATES="$ROOT/logs/gates"
GATE_MAX_AGE=$((24 * 3600))

mkdir -p "$GATES" "$ROOT/logs" "$ROOT/device-info"

ok()   { printf '  \e[32mPASS\e[0m  %s\n' "$*"; }
bad()  { printf '  \e[31mFAIL\e[0m  %s\n' "$*"; FAILS=$((${FAILS:-0} + 1)); }
warn() { printf '  \e[33mWARN\e[0m  %s\n' "$*"; }
info() { printf '  ....  %s\n' "$*"; }
die()  { printf '\e[31mSTOP:\e[0m %s\n' "$*" >&2; exit 1; }
sha()  { sha256sum "$1" | cut -d' ' -f1; }

require_serial() {
  [[ -n $SERIAL ]] || die "no target phone: copy config.example.env to config.env and set SERIAL (see 'adb devices -l')"
}

# Stops if any protected phone is visible to adb or fastboot.
refuse_protected() {
  local s
  for s in $PROTECTED_SERIALS; do
    { adb devices; fastboot devices 2>/dev/null; } | grep -q "^$s\b" &&
      die "protected phone $s is connected: unplug it first"
  done
  return 0
}

# Requires the target phone in adb "device" state; refuses to guess when it is absent.
require_adb_target() {
  require_serial
  refuse_protected
  local list
  list=$(adb devices -l | tail -n +2 | sed '/^\s*$/d')
  printf '%s\n' "$list" | sed 's/^/  adb: /'
  printf '%s\n' "$list" | grep -qE "^$SERIAL\s+device" ||
    die "target phone $SERIAL is not connected in adb 'device' state"
}

# getprop value from a saved dump: prop <file> <name>
prop() { sed -n "s/^\[$2\]: \[\(.*\)\]$/\1/p" "$1"; }

write_gate() { printf 'serial=%s\nepoch=%s\nwhen=%s\n%s\n' "$SERIAL" "$(date +%s)" "$(date -Is)" "${2:-}" >"$GATES/$1.ok"; }

# gate_fresh <name>: the gate exists, names this serial and is younger than GATE_MAX_AGE.
gate_fresh() {
  local f="$GATES/$1.ok" epoch
  [[ -f $f ]] || return 1
  grep -qx "serial=$SERIAL" "$f" || return 1
  epoch=$(sed -n 's/^epoch=//p' "$f")
  (( $(date +%s) - epoch < GATE_MAX_AGE ))
}
