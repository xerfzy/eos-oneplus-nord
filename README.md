# eos-oneplus-nord

Scripts and notes for installing **/e/OS 4.4.1 (Android 16)** on the **OnePlus Nord AC2001** (codename
`avicii`) from Linux, and rooting it with **Magisk v31.1**.

The install itself is the official one: the /e/OS factory image and its own installer script
(`flash_avicii_factory.sh`), run unchanged. These scripts add what the official guide leaves to you:
- resumable downloads checked against the publishers' SHA-256;
- read-only checks that the right phone is connected and on the right firmware;
- an audit of the installer before it runs;
- a guarded wrapper that refuses to flash when something is off.

On 30 Oct 2026, earlier versions of these scripts installed /e/OS on an AC2001 (India) running OxygenOS
12.1 `AC2001_11_F.24`. The installer took about three minutes and the phone booted into /e/OS. The
versions published here have since been made general (a serial in `config.env`, protected phones, a
`--erase-and-flash` flag). Their laptop-side scripts were re-tested; `01`, `02` and `06` have not been run
against a phone again since.

> **Unlocking the bootloader and flashing erase everything on the phone.** Back up first. Nothing here
> is official /e/OS or Magisk software; use it at your own risk.

## Requirements

- **Computer:** Linux with `adb`, `fastboot`, `curl`, `unzip`, `python3` and `sha256sum`, and about 8 GB free.
  The /e/OS package brings its own `fastboot` for the install.
- **Phone:**
  - a OnePlus Nord AC2001 on the latest stock OxygenOS 12 (`AC2001_11_F.23` or newer);
  - battery above 50%;
  - OEM unlocking turned on in Developer options;
  - USB debugging on;
  - no Google account signed in (Factory Reset Protection).
- **Network:** the computer's internet must not come from this phone's hotspot.

## Quick start

```sh
cp config.example.env config.env      # set SERIAL to the phone's serial from `adb devices -l`
scripts/start-downloads.sh            # /e/OS factory ZIP (2.1 GB) + Magisk, resumable, in the background
scripts/download-status.sh --watch    # progress; wait for VERIFIED on both
scripts/01-identify-device.sh         # read-only
scripts/02-check-firmware.sh          # read-only
scripts/03-verify-downloads.sh
scripts/04-check-prerequisites.sh     # read-only
scripts/05-prepare-eos-flash.sh       # unzips and audits the installer
```

Then unlock the bootloader and flash: see **[docs/INSTALL-EOS.md](docs/INSTALL-EOS.md)**.
To root afterwards, see **[docs/ROOTING.md](docs/ROOTING.md)**.

## Scripts

| Script | Touches the phone? | What it does |
|---|---|---|
| `start-downloads.sh` | no | Starts the download worker and the `boot.img` extraction as systemd user units (or detached processes). Safe to run again: it resumes and never starts a second worker. |
| `dl-worker.sh` | no | Downloads `scripts/downloads.tsv` with `curl -C -`, retries forever with back-off. A file is renamed to its final name only when size and SHA-256 match. |
| `download-status.sh` | no | Size, speed, ETA and verification for each download. |
| `extract-boot-after-verify.sh` | no | Waits for the verified ZIP, then copies `boot.img` out of it for Magisk and checks its hash. |
| `01-identify-device.sh` | read-only | Proves the phone is the AC2001 `avicii` named in `config.env`, and saves its properties to `device-info/`. |
| `02-check-firmware.sh` | read-only | Stock Android 12, build F.23 or newer, official release keys. |
| `03-verify-downloads.sh` | no | Re-hashes every download, `boot.img`, and the installer in `staging/`. |
| `04-check-prerequisites.sh` | read-only | Tools, disk, downloads, battery, OEM unlock, accounts, bootloader state, and the manual items. |
| `05-prepare-eos-flash.sh` | no | Unzips the factory ZIP into `staging/`, checks the installer against the audited hashes, and lists what it will write. |
| `06-flash-eos.sh --erase-and-flash` | **erases and flashes** | Checks gates, that exactly one phone is in fastboot, the serial, `product=lito`, `unlocked=yes` and the update-merge state. Then asks you to type `ERASE <serial>` and runs the official installer, logging to `logs/`. |
| `07-prepare-magisk.sh` | no | Verifies the Magisk APK and `boot.img`, and prints the rooting steps. |

`lib.sh` holds the pinned versions and hashes. Everything the scripts write (`downloads/`, `staging/`,
`logs/`, `device-info/`, `checksums/`) is git-ignored.

## Pinned versions

| What | Version | SHA-256 | Source |
|---|---|---|---|
| /e/OS factory image | `IMG-e-4.4.1-a16-20261021695349-official-avicii.zip` | `f193ad43…7b0d` | images.ecloud.global (API and `.sha256sum`) |
| Magisk | `Magisk-v31.1.apk` | `89cefac0…c6e7` | GitHub release asset digest |
| `boot.img` inside the ZIP | header v2, ramdisk present | `899e9c25…cb37` | extracted locally |

To move to a newer build:
1. Update the URL, size and hash in `scripts/downloads.tsv`.
2. Update `EOS_VERSION`, `EOS_SHA256`, `EOS_SIZE` and `BOOT_UNMODIFIED_SHA256` in `scripts/lib.sh`.
3. Read the new `flash_avicii_factory.sh` and `factory.common`. Put their hashes in `lib.sh` only if they
   still do what [docs/INSTALL-EOS.md](docs/INSTALL-EOS.md) describes.

## Sources

- /e/OS for the Nord: <https://doc.e.foundation/devices/avicii> and `/devices/avicii/install`
- /e/OS rooting notes: <https://doc.e.foundation/os/advanced/rooting/>
- Magisk installation: <https://topjohnwu.github.io/Magisk/install.html>
- Magisk OTA updates: <https://topjohnwu.github.io/Magisk/ota.html>
- AOSP fastboot and fastbootd (`snapshot-update-status`): <https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/>
