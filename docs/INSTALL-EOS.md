# Installing /e/OS on the OnePlus Nord (avicii)

This follows the official guide (<https://doc.e.foundation/devices/avicii/install>). Each step notes what the
phone actually showed during the 30 Oct 2026 install on an AC2001 (India) running `AC2001_11_F.24`.
Replace `<serial>` with your phone's serial (`adb devices -l`), the same one as in `config.env`.

## 1. Before you start

- Copy everything you want to keep to the computer, for example `adb pull /sdcard/. backup/`.
  Unlocking erases the phone, and so does the install.
  App data cannot be pulled without root, so export it from each app.
- Update to the latest stock OxygenOS 12 (Settings → System → System updates).
- Charge the battery above 50%.
- Sign out of Google (Factory Reset Protection).
- Settings → About phone → tap Build number 7 times. Then in Developer options turn on
  **OEM unlocking** and **USB debugging**.
- If the computer gets its internet from this phone's hotspot, connect it some other way first.

Then run the read-only checks. They must all pass (`04` lists the manual items too):

```sh
scripts/01-identify-device.sh && scripts/02-check-firmware.sh && scripts/03-verify-downloads.sh \
  && scripts/04-check-prerequisites.sh && scripts/05-prepare-eos-flash.sh
```

`01` and `02` write gates in `logs/gates/` that stay valid for 24 hours. `06` refuses to run without
them, so finish the install within a day of running the checks.

## 2. Unlock the bootloader (erases the phone)

```sh
adb -s <serial> reboot bootloader
fastboot devices                      # exactly one line: <serial>  fastboot
fastboot -s <serial> oem unlock
```

On the phone:
1. Choose the unlock option with the volume keys.
2. Confirm with the power key.

`fastboot` answers `OKAY` at once. The phone then erases itself and restarts into the stock setup
wizard. Its language is reset, so the first screen may be in Chinese. Don't set it up.

After the wipe, `adb devices` shows the phone as `unauthorized`, because the computer's USB debugging
key was erased. `adb reboot bootloader` no longer works. Use the keys instead:
1. Power the phone off: hold Power, or Power + Volume Up for the power menu.
2. Hold **Volume Up + Volume Down + Power** until the fastboot screen appears.

That screen now ends with `DEVICE STATE - unlocked`. Every boot from now on starts with a warning
that the bootloader is unlocked. That is expected.

## 3. Check for an unfinished system update

The Nord uses Virtual A/B. If a stock update was installed but its background "merge" never finished,
fastbootd refuses to erase `userdata` and `metadata`, and the installer stops halfway.

The bootloader may not report this state; fastbootd does:

```sh
fastboot -s <serial> reboot fastboot
fastboot -s <serial> getvar snapshot-update-status     # want: none
fastboot -s <serial> reboot bootloader
```

- **`none`:** go on. It said `none` on our phone after unlocking.
- **`snapshotted` or `merging`:** stop. Either boot the stock OS once and let the merge finish, or run
  `fastboot snapshot-update cancel`. AOSP warns that cancelling "may make the device unbootable until it
  is reflashed", which the install does next anyway.

## 4. Flash /e/OS

With the phone in the bootloader (not fastbootd):

```sh
scripts/06-flash-eos.sh --erase-and-flash --accept-unknown-snapshot-state   # the second flag only after step 3 said none
```

The wrapper checks everything again:
- the 24 h gates and `staging/`;
- exactly one fastboot device, and it is `<serial>`;
- `product` contains `lito`;
- `unlocked: yes`;
- the phone is not in fastbootd.

It then asks you to type `ERASE <serial>` and runs the official installer, which does this:

1. Checks `getvar unlocked`, then `fastboot reboot fastboot`.
2. Flashes firmware to **both** slots: abl aop bluetooth devcfg dsp featenabler hyp imagefv keymaster logo
   modem qupfw storsec tz uefisecapp xbl_config xbl.
3. Flashes boot, dtbo, recovery, vbmeta and vbmeta_system to **both** slots.
4. Flashes odm, product, system, system_ext and vendor to the current slot (logical partitions in `super`).
5. Erases `userdata` and `metadata`, then reboots.

It took about 3 minutes. Don't unplug the cable or press any buttons until the phone has rebooted.
The full session is saved in `logs/flash-<time>.log`. The first boot of /e/OS takes a few minutes.

## Known issues

- **Firmware region.** The package flashes the EU (AC2003) `F.23` firmware over the India `F.24`. /e/OS
  officially supports the AC2001 with this package, and it booted and ran fine. No official source covers
  anti-rollback across these builds, so treat other starting builds with care.
- **One phone at a time.** When several phones are in fastboot mode, the official script's `find_device`
  may report the wrong serial. `06-flash-eos.sh` refuses unless exactly one phone is in fastboot mode.
- **`no permissions` from fastboot.** systemd's `70-uaccess.rules` normally lets the logged-in user use
  fastboot. If it doesn't, the official guide suggests running fastboot as root.
- **Relocking.** Don't relock the bootloader while the phone is rooted. See
  <https://doc.e.foundation/os/learn/bootloader-relocking/> before relocking at all.
