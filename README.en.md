# marble-deb

[![Build Debian RootFS](https://github.com/GhfunNiHe/marble-deb-build/actions/workflows/rootfs-debian.yml/badge.svg?branch=main)](https://github.com/GhfunNiHe/marble-deb-build/actions/workflows/rootfs-debian.yml)

> Simplified Chinese version: [README.md](README.md)

> **Project Status**
>
> This project is still under active development. Some features may be incomplete, and build artifacts may contain unknown issues.
>
> If you encounter a problem, please open an [Issue](https://github.com/GhfunNiHe/marble-deb-build/issues).

---

## Overview

This repository uses **GitHub Actions** to assemble **Debian arm64** rootfs and ESP images for the **Xiaomi POCO F5 / Redmi Note 12 Turbo (marble, Qualcomm SM7475)**.

The repository only assembles system images and contains no device source code. The kernel, device-support layer, networking and sensor components, firmware, and other device-specific packages are all obtained as `.deb` files from releases of [GhfunNiHe/marble-deb-packages](https://github.com/GhfunNiHe/marble-deb-packages).

Each build produces Android sparse images:

- `rootfs.simg.xz`: ext4 rootfs;
- `esp.simg.xz`: FAT ESP containing the kernel, DTB, and U-Boot boot configuration.

The system does not use an initramfs; U-Boot starts the kernel directly.

---

## Quick Start

### 1. Fork and Enable Actions

Click **Fork** in the upper-right corner to copy the repository to your GitHub account.

Open the **Actions** tab in your fork. If GitHub asks you to enable the workflows, click
`I understand my workflows, go ahead and enable them`.

### 2. Run the Build

Select **Build Debian RootFS** in the left sidebar, then click **Run workflow** on the right.

Expand the form to adjust the build parameters. See [Advanced Configuration](#advanced-configuration) for details. With all defaults unchanged, the build will produce:

- Debian `trixie`;
- the Phosh desktop;
- username `Redmi`;
- hostname `marble-debian`;
- a 10 GiB rootfs and a 128 MiB ESP.

Click the green **Run workflow** button to start the build.

### 3. Download the Artifacts

When the build finishes, open the run summary and download the following from the **Artifacts** section:

- `rootfs-<suite>-<desktop>`
- `esp-<suite>-<desktop>`

The rootfs artifact also contains `SHA256SUMS`, which can be used to verify image integrity before flashing.

---

## Advanced Configuration

The following inputs are available when running **Build Debian RootFS** through `workflow_dispatch`:

| Parameter | Description | Options | Default |
|---|---|---|---|
| **distro_suite** | Debian release to install. `trixie` is Debian 13, `forky` is Debian 14, and `sid` is the rolling development release. | `trixie` / `forky` / `sid` | `trixie` |
| **desktop** | Desktop environment to preinstall. Select `server` to build without a graphical interface. | `Phosh` / `KDE Plasma Mobile` / `KDE Plasma` / `GNOME` / `server` | `Phosh` |
| **autologin** | Whether the created user should be logged in automatically. GNOME uses GDM; KDE Plasma and Plasma Mobile use SDDM on `trixie` and plasma-login-manager on `forky` and newer; **not applicable to Phosh**, which has to go through the phrog greeter — greetd's `initial_session` bypasses it and the session then misses `XDG_CURRENT_DESKTOP`, so gnome-control-center refuses to start and the phone has no Settings app. Not applicable to `server` mode. | `true` / `false` | `true` |
| **username** | Name of the non-root user. The user is added to the available `sudo`, `audio`, `video`, `render`, `input`, `netdev`, and `plugdev` groups. | string | `Redmi` |
| **hostname** | System hostname. | string | `marble-debian` |
| **language** | System locale. Selecting `None (C.UTF-8)` keeps the default locale; selecting another option generates both `en_US.UTF-8` and the selected locale, and makes the selected locale the default. | `None (C.UTF-8)` / `en_US.UTF-8` / `zh_CN.UTF-8` / `zh_TW.UTF-8` / `ja_JP.UTF-8` / `ko_KR.UTF-8` / `de_DE.UTF-8` / `fr_FR.UTF-8` / `es_ES.UTF-8` / `ru_RU.UTF-8` | `None (C.UTF-8)` |
| **image_size** | Initial rootfs image size. `fstab` enables `x-systemd.growfs`, so the filesystem grows to the real partition size on first boot. | a size such as `10G` or `8192M` | `10G` |
| **esp_size** | ESP image size; must not exceed the device's ESP partition size. | a size such as `128M` or `1G` | `128M` |
| **root_partition** | GPT partition label containing the rootfs. The value is written to `fstab`, and the kernel package's `postinst` copies it to `root=` in `extlinux.conf`. It must match the actual partition label. | GPT partition label | `linux` |
| **deb_repo** | GitHub repository that publishes the device `.deb` packages. | `owner/repository` | `GhfunNiHe/marble-deb-packages` |
| **deb_release** | Release tag from which to download the device `.deb` packages. `latest` means the newest release. | release tag | `latest` |
| **extra_deb_urls** | Additional `.deb` download URLs, one per line. | valid `.deb` URL | empty |
| **extra_packages** | Additional Debian packages appended to the base package set, separated by spaces. | package names | empty |

> **Notes**
>
> - The initial passwords for the normal user and root come from the repository secret `ROOTFS_PASSWORD`. Create this secret before running the build.
> - If `ROOTFS_PASSWORD` is not set, the build still runs, but the password falls back to the insecure default value `password`.
> - `esp_size` must not exceed the device's ESP partition size.
> - `root_partition` must match the actual GPT partition label. The ESP partition label must remain `esp`, because U-Boot locates the boot partition by that label.

---

## Artifacts

| Artifact | Description |
|---|---|
| `rootfs.simg.xz` | Android sparse ext4 image with no partition table. The filesystem LABEL is fixed to `linux`; booting uses the GPT partition label specified by `root_partition`. |
| `esp.simg.xz` | Android sparse FAT image with LABEL `ESP` and 4096-byte logical sectors. |
| `SHA256SUMS` | SHA-256 checksums for the rootfs and ESP images, included in the rootfs artifact. |

The ESP contains:

- `/marble/vmlinuz`;
- `/marble/sm8475-xiaomi-marble.dtb`;
- `/extlinux/extlinux.conf`.

`vmlinuz` must be an uncompressed arm64 `Image`, because U-Boot boots the kernel with `booti`.

The ESP must use 4096-byte logical sectors. The marble UFS uses 4096-byte logical sectors; with a 512-byte FAT, Linux may fail to mount the ESP, resulting in emergency mode or a black screen. The build parses the FAT BPB and verifies the sector size.

`esp.simg` is a bare filesystem image rather than a disk image, so its loop mount used during assembly has no `PARTLABEL`. The kernel postinst therefore also accepts the image's filesystem `LABEL=ESP`; on the device, the partition should still retain `PARTLABEL=esp`.

The device boot chain is:

```text
ABL
  -> boot_b (U-Boot)
  -> esp:/extlinux/extlinux.conf
  -> esp:/marble/vmlinuz + DTB
  -> root=PARTLABEL=<root_partition>
```

The build also checks that all expected ESP files are present, that the kernel is an uncompressed arm64 Image, and that `root=` in `extlinux.conf` matches `fstab`.

---

## Flashing

### Prerequisites

- Bootloader is unlocked;
- a third-party recovery such as TWRP or OrangeFox is installed;
- `platform-tools` is configured on your computer;
- `esp` and rootfs partitions already exist on the device (the default rootfs label is `linux`).

> **Warning**
>
> The following steps modify device partitions and may cause data loss. Back up important data first, and make sure you understand each command.

### Flash the Images

These instructions assume a dual-boot setup with `esp` and `linux` already partitioned.

Download the current device's [U-Boot image](https://github.com/iLtanaka/u-boot-marble/releases/download/v20261008/boot-uboot.img) and the built `esp.simg` and `rootfs.simg` images.

Extract the downloaded Artifact ZIP files, place `rootfs.simg.xz`, `esp.simg.xz`, and `SHA256SUMS` in the same directory, and run:

```bash
# 1. Verify and decompress the images
sha256sum -c SHA256SUMS
xz -d rootfs.simg.xz esp.simg.xz

# 2. Flash U-Boot
fastboot flash boot_b path/to/u-boot.img

# 3. Flash the ESP
fastboot flash esp esp.simg

# 4. Flash the rootfs
fastboot flash linux rootfs.simg

# 5. Set the active boot slot
fastboot set_active b

# 6. Reboot
fastboot reboot
```

If you used a custom label for `root_partition`, replace `linux` in `fastboot flash linux` with the actual partition label.

The ESP partition label must remain `esp`; do not change only `root_partition` while ignoring the actual partition layout.

---

## Device Components

All device-specific packages are built and published by [GhfunNiHe/marble-deb-packages](https://github.com/GhfunNiHe/marble-deb-packages). Patch and version details are recorded in each package's `debian/changelog`.

| Package | Purpose | Upstream |
|---|---|---|
| `linux-redmi-marble` | marble kernel, DTB, kernel modules, and ESP boot payload. | [iLtanaka/linux-marble](https://github.com/iLtanaka/linux-marble) |
| `marble-device-support` | Device services, including WLAN / Bluetooth MAC restoration, NetworkManager configuration, sensor recovery, IMS enablement, and hardware tuning. | [iLtanaka/marble-device-support](https://github.com/iLtanaka/marble-device-support) |
| `modemmanager` | ModemManager with marble patches for GNSS unlocking, NMEA synthesis, and related fixes. | [freedesktop ModemManager](https://gitlab.freedesktop.org/mobile-broadband/ModemManager) |
| `libqmi` | QMI communication library including the QMI_LOC client-identification TLV. | [freedesktop libqmi](https://gitlab.freedesktop.org/mobile-broadband/libqmi) |
| `libssc` | Qualcomm SSC / SLPI sensor communication library. | [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) |
| `iio-sensor-proxy-ssc` | Exposes SSC sensor data over D-Bus for desktop environments. | [hadess/iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) |
| `libva-v4l2` | VA-API backend providing hardware H.264 / HEVC / VP9 decoding together with the kernel patch. | [radxa-pkg/libva-v4l2](https://github.com/radxa-pkg/libva-v4l2) |
| `firmware-redmi-marble` | Firmware for ADSP, SLPI, modem, Adreno, IPA, WCN6855 Wi-Fi / Bluetooth, the sensor registry, and related components. | [iLtanaka/firmware-xiaomi-marble](https://github.com/iLtanaka/firmware-xiaomi-marble) |

---

## License and Third-Party Components

This repository contains only the GitHub Actions workflow and one U-Boot environment file, and does not currently declare an open-source license.

The repository and build process use the following third-party content. All rights remain with the respective owners:

| Content | Source | License |
|---|---|---|
| `.github/workflows/rootfs-debian.yml` | this repository | not declared |
| all device `.deb` packages | releases of [GhfunNiHe/marble-deb-packages](https://github.com/GhfunNiHe/marble-deb-packages) | see each package's `debian/copyright` |
| `libva-v4l2` | [radxa-pkg/libva-v4l2](https://github.com/radxa-pkg/libva-v4l2) | MIT |
| kernel, drivers, and device patches | their respective upstream projects listed above | GPL-2.0-only and others, following upstream |
| firmware blobs | Qualcomm / Xiaomi, distributed only for the device | proprietary, for running Linux on your own device |

---

## Credits

This project benefits from the following projects and community work:

- **iLtanaka**: mainline marble port, including the kernel, U-Boot, device-support layer, pmaports, firmware packages, and ALT Mobile integration;
- **ianchb**: reference implementation of the ath11k MAC solution;
- **Dylan Van Assche**: SSC backends for `libssc` and `iio-sensor-proxy`;
- **DebianOnMobile**: Phosh metapackages and mobile integration.
