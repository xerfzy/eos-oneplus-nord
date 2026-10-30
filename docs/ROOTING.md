# Rooting /e/OS on the OnePlus Nord with Magisk

## Why Magisk

Official /e/OS builds are `userdebug` builds disguised as `user` builds (with `ih8sn`), so the
"Rooted debugging" / `adb root` option is missing from Developer options. /e/OS's own rooting page says
to use a community build for that option, or Magisk
(<https://doc.e.foundation/os/advanced/rooting/>). `adb root` only gives root to the adb shell anyway;
apps that need root need Magisk.

/e/OS does not recommend rooting and warns that Magisk "may create some side effects and strange
behaviors". Use it knowing that.

## How it works

Magisk is "systemless": it never writes to `system`, `vendor` or the other read-only partitions. It
changes only the **boot image**:

1. The Magisk app on the phone takes a copy of `boot.img` and replaces the `init` in its ramdisk with
   `magiskinit`. The result is a new file, `magisk_patched-<version>_<random>.img`.
2. You flash that file to the `boot` partition with fastboot. The phone needs an unlocked bootloader to
   boot a modified image.
3. At every boot `magiskinit` starts first. It sets up Magisk's daemon and its overlays (modules, the
   `su` command) in memory, then hands over to the normal Android `init`.
4. When an app or `adb shell` runs `su`, the Magisk app asks you to Grant or Deny, and remembers the answer
   per app. The Superuser tab lists every app you've granted.

Because the system partitions stay untouched, removing root is just flashing the original `boot.img` back.

On the Nord, `boot.img` is the right image: the phone has no `init_boot` or `vendor_boot` partition, and
the /e/OS `boot.img` (header v2) carries a ramdisk. The Magisk app should show **Ramdisk: Yes**.

## Steps

You need:
- the bootloader still unlocked (it is after the /e/OS install);
- USB debugging on in /e/OS (Settings → About phone → tap Build number 7 times; then System →
  Developer options → USB debugging), with this computer allowed;
- `scripts/07-prepare-magisk.sh` passing. It verifies the APK and `boot.img`.

1. **Check the build.** Settings → About phone must show the same build as the `boot.img`
   (`4.4.1-a16-20261021695349`). If /e/OS has installed an update since, this `boot.img` is the wrong one.
   Take `boot.img` from the factory ZIP of the build you're running, or give Magisk that ZIP directly
   (it can extract the image itself).

2. **Install Magisk and copy the image to the phone:**
   ```sh
   adb -s <serial> install -r downloads/magisk/Magisk-v31.1.apk
   adb -s <serial> push downloads/eos/unmodified/boot.img /sdcard/Download/
   ```

3. **Patch it on the phone.** In Magisk:
   1. Check that the Magisk card says **Ramdisk: Yes**.
   2. Tap **Install** → **Patch firmware / image** → **Select from storage**, and pick
      `Download/boot.img`.
   3. Start it and wait for "All done!".

   Always patch on the phone you will flash. Never use an image patched on another phone, even the same
   model (Magisk's own warning).

4. **Copy the patched image back:**
   ```sh
   adb -s <serial> shell ls /sdcard/Download/          # find magisk_patched-31100_xxxxx.img
   adb -s <serial> pull /sdcard/Download/magisk_patched-31100_xxxxx.img downloads/magisk/
   ```

5. **Flash it and reboot:**
   ```sh
   adb -s <serial> reboot bootloader
   fastboot devices                                     # exactly one line: <serial>  fastboot
   fastboot -s <serial> flash boot downloads/magisk/magisk_patched-31100_xxxxx.img
   fastboot -s <serial> reboot
   ```
   - `flash boot` writes the active slot only, which is the slot the phone boots.
   - Magisk's optional `vbmeta --disable-verity --disable-verification` step isn't needed here. It can
     wipe data, so keep it for when the patched image fails to boot.

6. **Finish.**
   1. Open Magisk. If it asks for an "environment fix" / additional setup, accept it and let it reboot.
   2. The Magisk card should then show **Installed: 31.1**.
   3. Test with `adb -s <serial> shell su -c id`. The phone asks whether to grant Shell; grant it, and
      the command prints `uid=0(root)`.

## If it doesn't boot

The system partitions are untouched, so this always gets you back to unrooted /e/OS without losing data.
In the bootloader (power off, then Volume Up + Volume Down + Power):

```sh
fastboot -s <serial> flash boot downloads/eos/unmodified/boot.img
fastboot -s <serial> reboot
```

## /e/OS updates (OTA) and root

An /e/OS update replaces `boot`, so a plain update removes root. The Nord is an A/B device, so Magisk
can carry root across, following <https://topjohnwu.github.io/Magisk/ota.html>:

1. Don't let updates install and reboot on their own. Turn off automatic updates in the updater, or in
   Developer options if it is offered.
2. When an update is offered, first run Magisk → **Uninstall** → **Restore Images**. Don't reboot, or
   Magisk is gone. This restores the original boot image so the update's checks pass.
3. Install the update in Settings → System updates and wait until it has completely finished. **Don't
   tap Reboot.**
4. Magisk → **Install** → **Install to Inactive Slot (After OTA)**.
5. Now reboot from the update screen. The phone starts the updated slot, still rooted.

Magisk's guide says this exact workflow is tested only on Pixels. If root is lost anyway, patch the new
build's `boot.img` again from step 1 above.

## Removing root

Magisk → **Uninstall** → **Complete Uninstall**. Or flash the original `boot.img` as in "If it doesn't
boot" and remove the Magisk app.

## Good habits

- Grant root only to apps you trust. A rooted app can read and change anything on the phone.
- Keep `downloads/eos/unmodified/boot.img` for the build you are running. It is your way back.
- Install Magisk modules one at a time. A bad module can stop the phone booting. If that happens, boot
  into Android safe mode (usually by holding Volume Down while the phone starts) and Magisk disables all
  modules.
