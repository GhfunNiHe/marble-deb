# marble-deb-build

[![Build Debian RootFS](https://github.com/GhfunNiHe/marble-deb-build/actions/workflows/rootfs-debian.yml/badge.svg?branch=main)](https://github.com/GhfunNiHe/marble-deb-build/actions/workflows/rootfs-debian.yml)

> English version: [README.en.md](README.en.md)

本仓库用 **GitHub Actions** 为 **小米 POCO F5 / Redmi Note 12 Turbo（marble / 高通 SM7475）** 组装 **Debian arm64** 的 rootfs 与 ESP 镜像，产物是 Android sparse 镜像（`.simg.xz`），解压后可直接用 `fastboot` 刷入设备对应分区。

本仓库**只做组装**，不含任何设备源码：所有设备 `.deb`（内核、设备支持层、ModemManager、libqmi、libssc、iio-sensor-proxy-ssc、libva-v4l2、固件）都取自 [GhfunNiHe/marble-deb-package](https://github.com/GhfunNiHe/marble-deb-package) 发布的 release。
系统**不使用 initramfs**，由 U-Boot 直接启动内核。

## 使用方法

1. Fork 本仓库（或在任意仓库里启用 Actions）。
2. 进入 `Actions` → `Build Debian RootFS` → `Run workflow`，按需填写参数（见下表）。
3. 构建完成后，在本次运行的 `Artifacts` 中下载 `rootfs-<suite>-<desktop>` 与 `esp-<suite>-<desktop>`。

## 参数说明

| 参数 | 默认值 | 说明 |
|---|---|---|
| **distro_suite** | `trixie` | Debian 版本，可选 `trixie` / `forky` / `sid` |
| **desktop** | `Phosh` | 桌面环境：`Phosh` / `KDE Plasma Mobile` / `KDE Plasma` / `GNOME` / `server`（无图形界面） |
| **autologin** | `true` | 自动登录：Phosh/GNOME 写 `/etc/gdm3/daemon.conf`（Phosh 时另写 AccountsService 的 `Session=phosh`）；Plasma / Plasma Mobile 写 `/etc/sddm.conf.d/autologin.conf` |
| **username / hostname** | `Redmi` / `marble-debian` | 用户名与主机名（用户会加入 sudo + audio/video/render/input/netdev/plugdev） |
| **language** | `None (C.UTF-8)` | 10 种可选；选定后生成该 locale 并写入系统配置 |
| **image_size** | `10G` | rootfs 镜像初始大小；`fstab` 带 `x-systemd.growfs`，首次启动自动扩到分区实际大小 |
| **esp_size** | `128M` | ESP 镜像大小（marble 的 esp 分区是 128M，别超过） |
| **root_partition** | `linux` | rootfs 所在 GPT 分区标签；会写进 `fstab`，内核包的 postinst 再据此改写 `extlinux.conf` 的 `root=` |
| **deb_repo / deb_release** | `GhfunNiHe/marble-deb-package` / `latest` | 设备 deb 的来源仓库与 release 标签（`latest` = 最新） |
| **extra_deb_urls** | *(空)* | 额外 deb 的直链，一行一个（可选） |
| **extra_packages** | *(空)* | 追加进基础包集的包名，空格分隔（可选） |
| **android_boot_entry** | `true` | 是否把 `extras/others.env` 写到 `esp:/extlinux/others.env`，让 U-Boot 菜单出现「Other systems...」（可从 U-Boot 启动 Android） |

口令**不是**输入项：镜像里普通用户与 root 的初始口令只从仓库 Secret `ROOTFS_PASSWORD` 取（未设置时回落到 `password` 并给出 warning），这样口令不会出现在 `workflow_dispatch` 的输入摘要里。

## 产物与刷机

```sh
xz -d rootfs.simg.xz esp.simg.xz
fastboot flash linux rootfs.simg
fastboot flash esp   esp.simg
```

- **rootfs.simg** —— Android sparse ext4，**没有分区表**，文件系统 LABEL 由 `root_partition` 决定（默认 `linux`）。
- **esp.simg** —— Android sparse FAT32，LABEL=ESP，**4096 字节逻辑扇区**。marble 的 UFS 逻辑扇区是 4096，
  用 512 字节的 FAT 会静默挂不上（表现为紧急模式/黑屏）；构建时解析 BPB 并硬断言这一项。
- ESP 布局：`/marble/vmlinuz`、`/marble/sm8475-xiaomi-marble.dtb`、`/extlinux/extlinux.conf`。
  `vmlinuz` 必须是**未压缩的 arm64 Image**（`booti` 不能加载压缩镜像）。
- 引导链：`ABL → boot_b（U-Boot）→ esp:/extlinux/extlinux.conf → esp:/marble/vmlinuz + DTB → root=PARTLABEL=<root_partition>`。
- 构建期会断言：ESP 上三件套齐全、内核是未压缩 Image、且 `extlinux.conf` 的 `root=` 与 `fstab` 一致
  （这条串起了内核包 postinst「读 fstab 改 extlinux」的整条链路）。

## U-Boot 菜单与 `others.env`

`android_boot_entry` 打开时（默认），构建会把 `extras/others.env` 写到 `esp:/extlinux/others.env`。
这个文件是 U-Boot 启动菜单里「Other systems...」子菜单的数据源（见
[u-boot-marble](https://github.com/iLtanaka/u-boot-marble) 的 `board/qualcomm/xiaomi-marble.env`，
`preboot` 里的 `others_next` 与 `bootmenu_1` 的 `others_menu`），打开后可以从 U-Boot 直接启动
Android（slot a）或回到 Debian，不必用 fastboot 切槽。

文件里**刻意不写** `next_title` / `next_boot`：那是「一次性默认项」机制，需要被启动的系统自行清除
（上游项目用 `marble-oneshot-clear.service`，Debian 没有这个服务），一旦写入，Android 就会变成每次开机
的默认项。

## 组件与补丁来源

所有设备 deb 由 [marble-deb-package](https://github.com/GhfunNiHe/marble-deb-package) 构建，
下表列出每个包的上游来源与其携带的补丁出处：

| 包 | 上游来源（构建时拉取） | 补丁 / 本地改动 |
|---|---|---|
| `linux-redmi-marble` | [iLtanaka/linux-marble](https://github.com/iLtanaka/linux-marble) `main` | `ath11k-load-wlan-mac-from-firmware.patch`：ath11k 走 PCIe、没有 `local-mac-address`、固件里也没有 MAC，导致每次开机随机 MAC；补丁在 DT 与固件 MAC 均为 0 时加载 `ath11k/WCN6855/hw2.1/wlan_mac.bin`。`iris-decode-order-output.patch`：在 HFI gen2 解码器能力表上暴露标准的 display-delay 控件，并按需转发 `HFI_PROP_DECODE_ORDER_OUTPUT`；没有它，libva-v4l2 后端会在解码器构造时以 “S_CTRL DISPLAY_DELAY (Iris decode-order patch required): Invalid argument” 中止，VA-API 应用静默退回软解。两个补丁都由内核包自己在 `debian/rules` 的 configure 阶段应用 `debian/patches/series`（本地 `dpkg-buildpackage` 与 CI 行为一致，打不上会直接构建失败）。 |
| `marble-device-support` | [iLtanaka/marble-device-support](https://github.com/iLtanaka/marble-device-support)（git clone） | `debian/` 覆盖层：hexagonrpcd 固件根适配、`marble-mac-restore.service`（写 WLAN MAC，并用 MAC−1 的最后一位配置 BT 地址）、只读的 NM `ct-data` 配置、ath11k_pci 黑名单；两个 systemd drop-in 让传感器链能自愈（hexagonrpcd 在 SLPI 崩溃后 `Restart=always`，iio-sensor-proxy 在其后端消失时会段错误、故补 `Restart=on-failure`）；以及 IMS/SMS 使能件 `marble-imsctl` + `marble-ims-enable.service`（经 QMI IMSS 下发「Set IMS Services Enabled」，配合 `Recommends: 81voltd`）。 |
| `modemmanager` | [freedesktop ModemManager](https://gitlab.freedesktop.org/mobile-broadband/ModemManager) @ `98777e6` | `0002`：在 LOC 启动时解锁 AFW 门控的 GNSS 引擎（否则 QMI error 46，GPS 起不来）；`0003`：由 Position Report 合成 NMEA；`0004`：netlink use-after-free 修复的回移（上游 `9317cbc4`）。`3.0 (quilt)`，补丁由 `debian/patches/series` 自动应用。 |
| `libqmi` | [freedesktop libqmi](https://gitlab.freedesktop.org/mobile-broadband/libqmi) @ `d9e8af5`（1.39.1-dev） | 无本地补丁：该 commit 本身已带 QMI_LOC 客户端标识 TLV（上游 MR !470），AFW 门控的 GNSS 引擎需要它，而 trixie 自带的 1.38.0 没有。 |
| `libssc` | [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc)（tag 由 changelog 决定） | `wait-for-qmi-service.patch`（等 QMI 服务就绪）。此前的 `0002-libssc-light-four-element.patch` 已移除：marble 的光照传感器固件报告本身无效（末尾四个 0 字节被 protobuf-c 判为非法 tag，且三路强度恒为 0），留着只会造成「ALS 可用」的假象；加速度计、陀螺仪、指南针与接近传感器不受影响。 |
| `libva-v4l2` | [radxa-pkg/libva-v4l2](https://github.com/radxa-pkg/libva-v4l2) @ `0e4ce1e0` | 无本地补丁；meson 构建时 `-Dfastcv=disabled`，附带 `msm_drv_video.so` 别名与 GStreamer VA 环境覆盖（`/usr/lib/environment.d`、`/etc/profile.d`）。Debian 只带 Intel/Mesa 的 VA 驱动，没有它就等于浏览器/ffmpeg 无硬解路径；配合上面的 iris decode-order 补丁，marble 上 H.264/HEVC/VP9 1080p 已实测经 `/dev/video0` 解码。 |
| `iio-sensor-proxy-ssc` | [hadess/iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) 3.9 | 无本地补丁：编译时打开 `-Dssc-support`，配合 libssc 走 SSC/SLPI 传感器链。 |
| `firmware-redmi-marble` | [iLtanaka/firmware-xiaomi-marble](https://github.com/iLtanaka/firmware-xiaomi-marble) `v20261008-2` | 无补丁：ADSP、SLPI、modem、Adreno、IPA、WCN6855 Wi-Fi/BT、传感器注册表等闭源 blob。 |

## 许可与第三方组件

本仓库自身只有构建脚本与一份 U-Boot 环境文件，未声明开源许可证。仓库内及构建期引入的第三方内容如下，
版权归各自权利人：

| 内容 | 来源 | 许可 |
|---|---|---|
| `.github/workflows/rootfs-debian.yml` | 本仓库 | 未声明 |
| `extras/others.env` | 本项目的 U-Boot 启动菜单约定（配合 [u-boot-marble](https://github.com/iLtanaka/u-boot-marble) 的 `others_next`/`others_menu`） | 随上游 |
| 全部设备 `.deb` | [GhfunNiHe/marble-deb-package](https://github.com/GhfunNiHe/marble-deb-package) 的 release | 见各包 `debian/copyright` |
| `libva-v4l2`（VA-API 后端） | [radxa-pkg/libva-v4l2](https://github.com/radxa-pkg/libva-v4l2)（原 fork 为 strongtz/libva-v4l2） | MIT |
| 内核、驱动与上表补丁 | 见上表各自上游 | GPL-2.0-only 等，随各自上游 |
| 固件 blob | 高通 / 小米（仅随设备分发） | 专有，仅用于在自有设备上运行 Linux |

## 致谢

- **iLtanaka** —— marble 主线移植（内核、U-Boot、设备支持层、pmaports、固件包）与 ALT Mobile 集成
- **ianchb** —— ath11k MAC 方案的参考实现
- **Dylan Van Assche** —— `libssc` 与 `iio-sensor-proxy` 的 SSC 后端
- **DebianOnMobile** —— Phosh 元包与移动端集成
