# marble-deb

[![Build Debian RootFS](https://github.com/GhfunNiHe/marble-deb-build/actions/workflows/rootfs-debian.yml/badge.svg?branch=main)](https://github.com/GhfunNiHe/marble-deb-build/actions/workflows/rootfs-debian.yml)

> English version: [README.en.md](README.en.md)

> **项目状态**
>
> 本项目仍在持续开发中，部分功能可能尚未完善，构建产物可能存在未知问题。
>
> 如果遇到问题，欢迎提交 [Issue](https://github.com/GhfunNiHe/marble-deb-build/issues)。

---

## 项目简介

本项目使用 **GitHub Actions**，为 **小米 POCO F5 / Redmi Note 12 Turbo（marble，高通 SM7475）** 组装 **Debian arm64** 的 rootfs 与 ESP 镜像。

仓库只负责组装系统镜像，不包含设备源码。内核、设备支持层、网络与传感器组件、固件等全部以 `.deb` 形式从 [GhfunNiHe/marble-deb-packages](https://github.com/GhfunNiHe/marble-deb-packages) 的 Release 获取。

构建完成后会生成 Android sparse 镜像：

- `rootfs.simg.xz`：ext4 rootfs；
- `esp.simg.xz`：FAT ESP，包含内核、DTB 与 U-Boot 启动配置。

系统不使用 initramfs，由 U-Boot 直接启动内核。

---

## 快速开始

### 1. Fork 并启用 Actions

点击仓库右上角的 **Fork**，将项目复制到自己的 GitHub 账号。

进入 Fork 后仓库的 **Actions** 页面。如果 GitHub 提示需要启用工作流，点击
`I understand my workflows, go ahead and enable them`。

### 2. 运行构建

在左侧选择 **Build Debian RootFS**，点击右侧的 **Run workflow**。

展开后可以调整构建参数，具体说明见[高级配置](#高级配置)。如果全部保持默认，将构建：

- Debian `trixie`；
- Phosh 桌面；
- 用户名 `Redmi`；
- 主机名 `marble-debian`；
- 10 GiB rootfs 与 128 MiB ESP。

确认参数后，点击绿色的 **Run workflow** 开始构建。

### 3. 下载产物

构建完成后，打开本次运行的摘要页面，在 **Artifacts** 区域下载：

- `rootfs-<suite>-<desktop>`
- `esp-<suite>-<desktop>`

rootfs 产物中还包含 `SHA256SUMS`，可以在刷机前校验镜像完整性。

---

## 高级配置

通过 `workflow_dispatch` 手动运行 **Build Debian RootFS** 时，可以使用以下参数：

| 参数 | 说明 | 可选值 | 默认值 |
|---|---|---|---|
| **distro_suite** | 要安装的 Debian 版本。`trixie` 为 Debian 13，`forky` 为 Debian 14，`sid` 为滚动开发版。 | `trixie` / `forky` / `sid` | `trixie` |
| **desktop** | 预装的桌面环境。选择 `server` 时不安装图形界面。 | `Phosh` / `KDE Plasma Mobile` / `KDE Plasma` / `GNOME` / `server` | `Phosh` |
| **autologin** | 是否自动登录创建的用户。GNOME 使用 GDM，KDE Plasma 与 Plasma Mobile 在 `trixie` 使用 SDDM、在 `forky` 及更新版本使用 plasma-login-manager；**Phosh 不适用**——它必须经过 phrog 登录界面，greetd 的 `initial_session` 会绕过 greeter 导致会话里缺少 `XDG_CURRENT_DESKTOP`，GNOME 控制中心拒绝启动、系统没有「设置」应用。`server` 模式不适用。 | `true` / `false` | `true` |
| **username** | 非 root 用户名。用户会加入系统中可用的 `sudo`、`audio`、`video`、`render`、`input`、`netdev`、`plugdev` 等用户组。 | 字符串 | `Redmi` |
| **hostname** | 系统主机名。 | 字符串 | `marble-debian` |
| **language** | 系统语言。选择 `None (C.UTF-8)` 时保留默认 locale；选择其他项时会同时生成 `en_US.UTF-8` 和所选 locale，并将所选 locale 设为默认。 | `None (C.UTF-8)` / `en_US.UTF-8` / `zh_CN.UTF-8` / `zh_TW.UTF-8` / `ja_JP.UTF-8` / `ko_KR.UTF-8` / `de_DE.UTF-8` / `fr_FR.UTF-8` / `es_ES.UTF-8` / `ru_RU.UTF-8` | `None (C.UTF-8)` |
| **image_size** | rootfs 镜像的初始大小。`fstab` 配置了 `x-systemd.growfs`，首次启动时会自动扩展到实际分区大小。 | 形如 `10G`、`8192M` 的大小 | `10G` |
| **esp_size** | ESP 镜像大小，不应超过设备的 ESP 分区大小。 | 形如 `128M`、`1G` 的大小 | `128M` |
| **root_partition** | rootfs 所在 GPT 分区的标签。该值会写入 `fstab`，并由内核包的 `postinst` 同步到 `extlinux.conf` 的 `root=`。必须与实际分区标签一致。 | GPT 分区标签 | `linux` |
| **deb_repo** | 发布设备 `.deb` 的 GitHub 仓库。 | `owner/repository` | `GhfunNiHe/marble-deb-packages` |
| **deb_release** | 拉取设备 `.deb` 的 Release 标签。`latest` 表示最新 Release。 | Release 标签 | `latest` |
| **extra_deb_urls** | 额外 `.deb` 的下载地址，一行一个。 | 有效的 `.deb` URL | 空 |
| **extra_packages** | 追加安装到基础软件包集合中的 Debian 软件包，以空格分隔。 | 软件包名称 | 空 |

> **注意事项**
>
> - 镜像中普通用户和 root 的初始密码来自仓库 Secret `ROOTFS_PASSWORD`，建议在运行构建前创建该 Secret。
> - 如果未设置 `ROOTFS_PASSWORD`，构建仍会继续，但密码会回退为不安全的默认值 `password`。
> - `esp_size` 不应超过设备的 ESP 分区大小。
> - `root_partition` 必须与实际 GPT 分区标签一致；ESP 分区标签固定为 `esp`，因为 U-Boot 会按该标签查找启动分区。

---

## 产物说明

| 产物 | 说明 |
|---|---|
| `rootfs.simg.xz` | Android sparse ext4 镜像，没有分区表；文件系统 LABEL 固定为 `linux`。启动时使用 `root_partition` 指定的 GPT 分区标签。 |
| `esp.simg.xz` | Android sparse FAT 镜像，LABEL 为 `ESP`，使用 4096 字节逻辑扇区。 |
| `SHA256SUMS` | rootfs 与 ESP 镜像的 SHA-256 校验值，位于 rootfs 产物中。 |

ESP 中包含：

- `/marble/vmlinuz`；
- `/marble/sm8475-xiaomi-marble.dtb`；
- `/extlinux/extlinux.conf`。

`vmlinuz` 必须是未压缩的 arm64 `Image`，因为 U-Boot 使用 `booti` 启动内核。

ESP 必须使用 4096 字节逻辑扇区。marble 的 UFS 逻辑扇区大小为 4096 字节；使用 512 字节 FAT 时，Linux 可能无法挂载 ESP，表现为紧急模式或黑屏。构建过程会解析 FAT BPB 并检查扇区大小。

`esp.simg` 是裸文件系统镜像而不是磁盘镜像，因此构建阶段挂载它时没有 `PARTLABEL`。内核包的 postinst 因此也接受镜像的文件系统 `LABEL=ESP`；设备上的 ESP 分区仍应保留 `PARTLABEL=esp`。

设备启动链如下：

```text
ABL
  -> boot_b（U-Boot）
  -> esp:/extlinux/extlinux.conf
  -> esp:/marble/vmlinuz + DTB
  -> root=PARTLABEL=<root_partition>
```

构建过程中还会检查 ESP 文件是否齐全、内核是否为未压缩 arm64 Image，以及 `extlinux.conf` 的 `root=` 是否与 `fstab` 一致。

---

## 刷机

### 前置条件

- 已解锁 Bootloader；
- 已安装 TWRP/OrangeFox 等第三方Recovery；
- 电脑已配置 `platform-tools`；
- 设备上已经创建 `esp` 与 rootfs 分区（默认标签为 `linux`）；

> **警告**
>
> 以下操作会修改设备分区并可能造成数据丢失。请先备份重要数据，并确认自己理解每条命令的作用。

### 刷入镜像

假设你使用双系统启动方式，并且已经分区好 `esp` 和 `linux`。

下载当前设备的 [U-Boot 镜像](https://github.com/iLtanaka/u-boot-marble/releases/download/v20261008/boot-uboot.img) 以及构建好的 `esp.simg` 和 `rootfs.simg` 镜像。

先解压下载的 Artifact ZIP，并将 `rootfs.simg.xz`、`esp.simg.xz` 与 `SHA256SUMS` 放在同一目录，然后执行：

```bash
# 1. 校验并解压镜像
sha256sum -c SHA256SUMS
xz -d rootfs.simg.xz esp.simg.xz

# 2. 刷入 U-Boot
fastboot flash boot_b path/to/u-boot.img

# 3. 刷入 ESP
fastboot flash esp esp.simg

# 4. 刷入 rootfs
fastboot flash linux rootfs.simg

# 5. 设置启动槽位
fastboot set_active b

# 6. 重启
fastboot reboot
```

如果 `root_partition` 使用了自定义标签，请将 `fastboot flash linux` 中的 `linux` 替换为实际分区标签。

ESP 分区标签必须保持为 `esp`，不要只修改 `root_partition` 而忽略实际分区布局。

---

## 设备组件

所有设备专用软件包均由 [GhfunNiHe/marble-deb-packages](https://github.com/GhfunNiHe/marble-deb-packages) 构建并发布。具体补丁和版本信息记录在各包的 `debian/changelog` 中。

| 软件包 | 作用 | 上游 |
|---|---|---|
| `linux-redmi-marble` | marble 内核、DTB、内核模块与 ESP 启动载荷。 | [iLtanaka/linux-marble](https://github.com/iLtanaka/linux-marble) |
| `marble-device-support` | 设备支持服务，包括 WLAN / Bluetooth MAC 恢复、NetworkManager 配置、传感器恢复、IMS 使能和硬件调优。 | [iLtanaka/marble-device-support](https://github.com/iLtanaka/marble-device-support) |
| `modemmanager` | 带 marble 补丁的 ModemManager，用于 GNSS 解锁、NMEA 合成和相关修复。 | [freedesktop ModemManager](https://gitlab.freedesktop.org/mobile-broadband/ModemManager) |
| `libqmi` | QMI 通信库，包含 QMI_LOC 客户端标识 TLV。 | [freedesktop libqmi](https://gitlab.freedesktop.org/mobile-broadband/libqmi) |
| `libssc` | Qualcomm SSC / SLPI 传感器通信库。 | [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) |
| `iio-sensor-proxy-ssc` | 将 SSC 传感器数据提供给 D-Bus，供桌面读取。 | [hadess/iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) |
| `libva-v4l2` | VA-API 后端，配合内核补丁提供 H.264 / HEVC / VP9 硬件解码。 | [FFT-infra/qualcomm-iris-vaap](https://github.com/FFT-infra/qualcomm-iris-vaapi) |
| `firmware-redmi-marble` | ADSP、SLPI、modem、Adreno、IPA、WCN6855 Wi-Fi / Bluetooth 与传感器注册表等固件。 | [iLtanaka/firmware-xiaomi-marble](https://github.com/iLtanaka/firmware-xiaomi-marble) |

---

## 许可与第三方组件

本仓库自身只包含 GitHub Actions 工作流和一份 U-Boot 环境文件，目前未声明开源许可证。

仓库内以及构建期引入的第三方内容如下，版权归各自权利人所有：

| 内容 | 来源 | 许可 |
|---|---|---|
| `.github/workflows/rootfs-debian.yml` | 本仓库 | 未声明 |
| 全部设备 `.deb` | [GhfunNiHe/marble-deb-packages](https://github.com/GhfunNiHe/marble-deb-packages) 的 Release | 见各包 `debian/copyright` |
| `libva-v4l2` | [FFT-infra/qualcomm-iris-vaapi](https://github.com/FFT-infra/qualcomm-iris-vaapi) | MIT and LGPL-2.0 |
| 内核、驱动与设备补丁 | 见上表各上游项目 | GPL-2.0-only 等，随各自上游 |
| 固件 blob | 高通 / 小米，仅随设备分发 | 专有，仅用于在自有设备上运行 Linux |

---

## 致谢

本项目受益于以下项目和社区工作：

- **iLtanaka**：marble 主线移植，包括内核、U-Boot、设备支持层、pmaports、固件包与 ALT Mobile 集成；
- **ianchb**：ath11k MAC 方案的参考实现；
- **Dylan Van Assche**：`libssc` 与 `iio-sensor-proxy` 的 SSC 后端；
- **DebianOnMobile**：Phosh 元包与移动端集成。
