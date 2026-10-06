# Fingerprint (EgisTech 1c7a:0584) on Debian 13

The ASUS Zenbook UX3402VA fingerprint reader is an **EgisTech** device
(`1c7a:0584`) that stock libfprint does not support. This setup uses the
community fork [TenSeventy7/libfprint-egismoc-sdcp](https://github.com/TenSeventy7/libfprint-egismoc-sdcp)
(LGPL-2.1), which adds the `egismoc` driver.

## Build patch

The fork's `meson.build` is missing the driver feature mapping, so the build
fails. One line fixes it (`patches/libfprint-egismoc-sdcp-add-egismoc.patch`):

```diff
     'uru4000' : [ 'openssl' ],
+    'egismoc' : [ 'openssl' ],
     'elanspi' : [ 'udev' ],
```

## Build and install

```bash
sudo apt install build-essential meson ninja-build libssl-dev \
  libglib2.0-dev libgudev-1.0-dev libusb-1.0-0-dev libpixman-1-dev \
  libcairo2-dev libgirepository1.0-dev libudev-dev

git clone https://github.com/TenSeventy7/libfprint-egismoc-sdcp
cd libfprint-egismoc-sdcp
git apply /path/to/43pr-debian/patches/libfprint-egismoc-sdcp-add-egismoc.patch
meson setup builddir
ninja -C builddir
sudo ninja -C builddir install
```

Notes from the original build on trixie:

- If `libudev-dev` is not installed, meson cannot find `udev.pc`. The local
  build used a small pkg-config shim (`udev.pc` copied from systemd) to work
  around it; installing `libudev-dev` is the clean solution.
- `sudo ninja install` **replaces the Debian libfprint**; a later
  `apt upgrade` of `libfprint-2-2` may overwrite it (re-install the fork if
  fingerprint stops working). Consider `apt-mark hold libfprint-2-2` if this
  bothers you.
- Unplug/replug or reboot after installing so the device is picked up.

## Enroll and test

```bash
fprintd-enroll          # enroll a finger (run as your user)
fprintd-verify          # test
fprintd-delete          # remove enrollments
lsusb | grep 1c7a       # device present?
```

## PAM integration

`etc/pam.d/greetd` (installed to `/etc/pam.d/greetd`) enables fingerprint at
the login screen:

```
#%PAM-1.0
auth        [success=end default=ignore]        pam_fprintd.so max-tries=1 timeout=10
@include login

-auth        optional        pam_gnome_keyring.so
-auth        optional        pam_kwallet5.so

-session     optional        pam_gnome_keyring.so auto_start
-session     optional        pam_kwallet5.so auto_start
```

Order matters: `pam_fprintd` is tried first (`success=end` means a good finger
ends authentication immediately; failure falls through to the password via
`@include login`). Increase `max-tries`/`timeout` if you want more attempts.

For screen unlocking, the fingerprint block in `hyprlock.conf` is already
enabled in this repo (no PAM file change needed for hyprlock).
