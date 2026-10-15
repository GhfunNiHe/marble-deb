# marble-deb-build

[![Build Debian RootFS](https://github.com/GhfunNiHe/marble-deb-build/actions/workflows/rootfs-debian.yml/badge.svg?branch=main)](https://github.com/GhfunNiHe/marble-deb-build/actions/workflows/rootfs-debian.yml)

> 中文版：[README.md](README.md)

This repository assembles **Debian arm64** rootfs and ESP images for the **Xiaomi POCO F5 / Redmi Note 12 Turbo (marble, Qualcomm SM7475)** with **GitHub Actions**.
Both artifacts are Android sparse images (`.simg.xz`) that are flashed to their partitions with `fastboot` after decompression.

This repository only **assembles** images and contains no device source code: every device `.deb` (kernel, device-support layer, ModemManager, libqmi, libssc, iio-sensor-proxy-ssc, libva-v4l2, firmware) comes from a release of [GhfunNiHe/marble-deb-packages](https://github.com/GhfunNiHe/marble-deb-packages).
The system runs **without an initramfs**; U-Boot boots the kernel directly.

## Usage

1. Fork this repository (or enable Actions in your own copy).
2. `Actions` → `Build Debian RootFS` → `Run workflow`, then fill in the inputs listed below.
3. When the run finishes, download `rootfs-<suite>-<desktop>` and `esp-<suite>-<desktop>` from the run's
   `Artifacts`.

## Inputs

| Input | Default | Description |
|---|---|---|
| **distro_suite** | `trixie` | Debian suite, `trixie`, `forky` or `sid` |
| **desktop** | `Phosh` | `Phosh` / `KDE Plasma Mobile` / `KDE Plasma` / `GNOME` / `server` (no desktop) |
| **autologin** | `true` | Phosh/GNOME: writes `/etc/gdm3/daemon.conf` (plus AccountsService `Session=phosh` for Phosh); Plasma / Plasma Mobile: writes `/etc/sddm.conf.d/autologin.conf` |
| **username / hostname** | `Redmi` / `marble-debian` | User (added to sudo plus audio/video/render/input/netdev/plugdev) and hostname |
| **language** | `None (C.UTF-8)` | One of ten locales; the chosen locale is generated and configured |
| **image_size** | `10G` | Initial rootfs size; `fstab` carries `x-systemd.growfs`, so the first boot grows it to the real partition |
| **esp_size** | `128M` | ESP image size (marble's esp partition is 128M — do not exceed it) |
| **root_partition** | `linux` | GPT label of the root partition; goes into `fstab`, and the kernel package's postinst copies it into `extlinux.conf` as `root=` |
| **deb_repo / deb_release** | `GhfunNiHe/marble-deb-packages` / `latest` | Where the device debs come from (`latest` = newest release) |
| **extra_deb_urls** | *(empty)* | Extra `.deb` URLs, one per line (optional) |
| **extra_packages** | *(empty)* | Extra packages appended to the base set, space separated (optional) |
| **android_boot_entry** | `true` | Write `extras/others.env` to `esp:/extlinux/others.env` so U-Boot's menu offers "Other systems..." (i.e. boot Android from U-Boot) |

The password is **not** an input: the initial password of the user and of root comes from the repository `ROOTFS_PASSWORD` secret only (falling back to `password` with a warning when it is unset), so it never appears in the `workflow_dispatch` input summary.

## Artifacts and flashing

```sh
xz -d rootfs.simg.xz esp.simg.xz
fastboot flash linux rootfs.simg
fastboot flash esp   esp.simg
```

- **rootfs.simg** — Android sparse ext4, **no partition table**, filesystem LABEL taken from
  `root_partition` (default `linux`).
- **esp.simg** — Android sparse FAT32, LABEL=ESP, **4096-byte logical sectors**. marble's UFS uses 4096-byte
  logical sectors; a 512-byte FAT never mounts (emergency mode / black screen), so the build parses the BPB
  and hard-fails if the sector size is wrong.
- ESP layout: `/marble/vmlinuz`, `/marble/sm8475-xiaomi-marble.dtb`, `/extlinux/extlinux.conf`. `vmlinuz`
  must be the **uncompressed arm64 Image** (`booti` cannot load a compressed kernel).
- Boot chain: `ABL → boot_b (U-Boot) → esp:/extlinux/extlinux.conf → esp:/marble/vmlinuz + DTB → root=PARTLABEL=<root_partition>`.
- The build asserts that all three ESP files exist, that the kernel is an uncompressed Image, and that
  `extlinux.conf`'s `root=` matches `fstab` (this covers the kernel postinst path that rewrites extlinux
  from `/etc/fstab`).

## U-Boot menu and `others.env`

With `android_boot_entry` enabled (the default) the build writes `extras/others.env` to
`esp:/extlinux/others.env`. That file backs the "Other systems..." submenu in U-Boot's boot menu (see
`board/qualcomm/xiaomi-marble.env` in [u-boot-marble](https://github.com/iLtanaka/u-boot-marble) —
`others_next` from `preboot`, and `others_menu` behind `bootmenu_1`), letting you boot Android (slot a)
or come back to Debian straight from U-Boot instead of switching slots with fastboot.

The file deliberately omits `next_title` / `next_boot`: those implement a "one-shot default entry" that the
booted system is expected to clear (the original project ships `marble-oneshot-clear.service`, Debian does
not), so writing them would make Android the default entry on every single boot.

## Components and patch provenance

All device debs are built by [marble-deb-packages](https://github.com/GhfunNiHe/marble-deb-packages). The table
below lists only each package's upstream origin and patch set; each patch's origin is recorded in that package's
changelog:

| Package | Upstream (fetched at build time) | Patches / local changes |
|---|---|---|
| `linux-redmi-marble` | [iLtanaka/linux-marble](https://github.com/iLtanaka/linux-marble) `main` | `ath11k-load-wlan-mac-from-firmware.patch`: read the MAC from the firmware's `wlan_mac.bin` when there is no other source (otherwise the interface comes up with a random MAC). `iris-decode-order-output.patch`: expose the display-delay controls and forward `HFI_PROP_DECODE_ORDER_OUTPUT` — libva-v4l2 relies on it. Both are applied by the package itself, from `series` in `debian/rules`, so a patch that stops applying fails the build. |
| `marble-device-support` | [iLtanaka/marble-device-support](https://github.com/iLtanaka/marble-device-support) (git clone) | `debian/` overlay: hexagonrpcd firmware-root adaptation, `marble-mac-restore.service` (WLAN MAC plus the BT address as MAC−1), a read-only NetworkManager `ct-data` profile, the ath11k_pci blacklist, the sensor-chain units that re-pull hexagonrpcd after an SLPI crash (iio-sensor-proxy restarts with it via `PartOf`), and the IMS/SMS pieces `marble-imsctl` + `marble-ims-enable.service` (paired with `Recommends: 81voltd`). |
| `modemmanager` | [freedesktop ModemManager](https://gitlab.freedesktop.org/mobile-broadband/ModemManager) @ `98777e6` | `0002`: unlock the AFW-gated GNSS engines when LOC starts (otherwise QMI error 46); `0003`: synthesize NMEA from the Position Report; `0004`: backport of the netlink use-after-free fix (upstream `9317cbc4`). `3.0 (quilt)`, applied from `series`. |
| `libqmi` | [freedesktop libqmi](https://gitlab.freedesktop.org/mobile-broadband/libqmi) @ `d9e8af5` (1.39.1-dev) | No local patches: this commit already carries the QMI_LOC client-identification TLVs (upstream MR !470) that trixie's 1.38.0 lacks. |
| `libssc` | [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) (tag taken from the changelog, currently 0.4.4) | `wait-for-qmi-service.patch`: wait for the SSC service to appear on QRTR (the DSP publishes it late, and there is no initramfs to order against); `0002-libssc-light-four-element.patch`: marble's lux sits in `intensity[1]` while upstream reads `[0]` and stays at 0; `0003-libssc-light-trim-padding.patch`: strip the trailing zero padding of the placeholder report before unpacking. On 0.4.4-4 the sensor reads correctly (≈200 lux in daylight). |
| `libva-v4l2` | [radxa-pkg/libva-v4l2](https://github.com/radxa-pkg/libva-v4l2) @ `0e4ce1e0` | No local patches; meson `-Dfastcv=disabled`, plus the `msm_drv_video.so` alias and the GStreamer VA environment overrides. Fills in the VA driver Debian lacks; with the iris patch above, H.264/HEVC/VP9 decode in hardware. |
| `iio-sensor-proxy-ssc` | [hadess/iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) 3.9 | No local patches: built with `-Dssc-support` to use libssc's SSC/SLPI chain. Known issue: its own udev rule tags every `fastrpc-*` device `ssc-light`, so the proxy can land on the ADSP and the desktop `LightLevel` stays 0; the sensor is on-change as well, so its initial value is only sent when it is enabled. |
| `firmware-redmi-marble` | [iLtanaka/firmware-xiaomi-marble](https://github.com/iLtanaka/firmware-xiaomi-marble) `v20261008-2` | No patches: the closed-source ADSP, SLPI, modem, Adreno, IPA, WCN6855 Wi-Fi/BT and sensor-registry blobs. |

## License and third-party components

This repository contains only a build workflow and one U-Boot environment file, and declares no open-source
license for itself. Third-party content pulled in by the repository or at build time is listed below; all
rights stay with the respective owners:

| Content | Source | License |
|---|---|---|
| `.github/workflows/rootfs-debian.yml` | this repository | not declared |
| `extras/others.env` | this project's U-Boot boot-menu convention (paired with `others_next`/`others_menu` in [u-boot-marble](https://github.com/iLtanaka/u-boot-marble)) | follows upstream |
| All device `.deb` packages | releases of [GhfunNiHe/marble-deb-packages](https://github.com/GhfunNiHe/marble-deb-packages) | see each package's `debian/copyright` |
| `libva-v4l2` (VA-API backend) | [radxa-pkg/libva-v4l2](https://github.com/radxa-pkg/libva-v4l2) (originally forked from strongtz/libva-v4l2) | MIT |
| Kernel, drivers and the patches above | their upstreams, per the table | GPL-2.0-only and others, follows upstream |
| Firmware blobs | Qualcomm / Xiaomi (device-redistributable only) | proprietary, for running Linux on your own device |

## Credits

- **iLtanaka** — mainline port for marble (kernel, U-Boot, device-support layer, pmaports, firmware package) and the ALT Mobile integration
- **ianchb** — the reference ath11k MAC implementation
- **Dylan Van Assche** — the SSC backends in `libssc` and `iio-sensor-proxy`
- **DebianOnMobile** — Phosh metapackages and mobile integration
