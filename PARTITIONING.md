# 设备分区（首次安装的前置步骤）

面向 **小米 POCO F5 / Redmi Note 12 Turbo（marble，SM7475）**：在保留 Android 的前提下，从 UFS 上划出两个 Linux 分区，让 `boot_b` 的 U-Boot 能引导 deb 系发行版（Debian / Ubuntu / …，下同）。

## ⚠️ 安装前请阅读

- **分区不可逆。** 会动到 `userdata`，**Android 的数据会丢**，先备份自己重要的东西。
- **`boot_a` / `vendor_boot_a` / `super` / `persist` 及各 `*_a` 固件分区一律别碰**，Android 就还在；要回 Android 随时 `fastboot set_active a`。
- 需要：已解锁 Bootloader、PC 上有 `adb`/`fastboot`、会用 TWRP 的 shell 敲命令。
- 动分区表**之前**先备份：`sgdisk --backup=/tmp/gpt.bin /dev/sda`（没 sgdisk 就用 `parted /dev/sda unit s print > /tmp/gpt.txt`），再 `adb pull` 到 PC。备份没落盘别往下走。
- 只在一台机器（POCO F5，256 GB）上验证过；其他型号/容量未验证。
- 分区与刷机流程**与发行版无关**：目前发布的镜像是 Debian（`trixie` / `forky` / `sid`），Ubuntu 等 deb 系后续加入，用同一套分区和引导链。

## 推荐：让 AI 帮你操作

步骤不多但顺序严格，最省力的方式是交给能执行命令的 AI 编程助手（Claude Code、Codex CLI 等）。在 PC 上启动助手，把下面整段复制给它——它会读文档、探环境、做备份，每次写入前先向你确认；你只负责在手机上按按键、并在需要时回一句「确认」。

```text
我要在小米 POCO F5 / Redmi Note 12 Turbo（代号 marble）上安装 deb 系 Linux 发行版（Debian / Ubuntu 等，具体用哪个听我的），与 Android 双系统共存。请你作为操作助手，按下述规则帮我完成分区与刷机。

文档：本仓库（marble-deb-build）的 PARTITIONING.md 与 README.md。

1. 先通读 PARTITIONING.md 再动手。
2. 分区、格式化、铺文件全部在设备的 TWRP 里做：我会在手机上进 TWRP 并告诉你，你通过 adb shell 执行；PC 只用来 adb pull/push 和 fastboot flash。
3. 先探环境：TWRP 里 sgdisk/parted/mkfs.fat/mke2fs/resize2fs 是否齐全、/dev/sda 逻辑扇区是否 4096、当前分区表和空闲空间。缺工具就按文档附录的替代办法走，不要硬来。
4. 每步开始前用一两句话说明做什么、写哪里；凡是写分区表 / mkfs / fastboot flash 的操作，先把将要执行的命令列给我，我说「确认」再执行。
5. 动 GPT 之前必须先备份分区表并 adb pull 到 PC；备份没落盘不许进入任何写入步骤。
6. 绝不写入 boot_a、vendor_boot_a、super、persist、modem 等 Android 或固件分区；不改 userdata 的分区编号与 Name；未经我要求不执行 fastboot set_active。
7. 必须守住三条硬约束：GPT 名恰好是 esp 与 linux；ESP 的 FAT 是 4096 字节逻辑扇区（用 od 校验应输出 00 10）；刷入的 vmlinuz 是未压缩的 arm64 Image。
8. 出错就停：任何命令报错、或输出与文档预期不符，立刻停下把完整输出给我看；不要自己重试写命令。
9. 需要我在手机上操作（进 TWRP、按键、拔插数据线）时，明确告诉我做什么、等什么现象。
10. 完成后按文档的「验证与回退」自检一遍，并教我怎样在 Android 与 Linux 之间切换。
```

## 手动步骤

下面这些**全部在设备上的 TWRP / OrangeFox 里做**（关机 → 按住 音量+ + 电源 → PC 上 `adb shell`）。PC 只负责 `adb pull/push` 和 `fastboot`。

TWRP 是精简用户态（toybox/busybox + 几个自带工具），没有 systemd、没有包管理器，`mkfs.fat`/`parted` 这类工具的有无和参数都可能和桌面 Linux 不同——先探一下：

```sh
for t in sgdisk parted mkfs.fat mke2fs resize2fs od; do printf '%-10s %s\n' "$t" "$(command -v $t || echo MISSING)"; done
```

动手前在「Mount」菜单里勾掉全部挂载，再补一刀：

```sh
umount /data /sdcard /system /vendor 2>/dev/null; true
```

## 布局

`/dev/sda` = UFS LUN 0，逻辑扇区 **4096 字节**：

| GPT 名 | 大小 | 文件系统 |
|---|---|---|
| `esp` | 128 MiB | FAT32，**4096 字节逻辑扇区** |
| `linux` | ≥ 15 GiB | ext4（`fstab` 带 `x-systemd.growfs`，首启自动扩满） |

引导链：`ABL → boot_b(U-Boot) → esp:/extlinux/extlinux.conf → esp:/marble/vmlinuz + DTB → root=PARTLABEL=linux`，**无 initramfs**。

三条硬约束（都是踩过的坑）：

1. GPT 名必须**恰好**是 `esp` / `linux` —— U-Boot 板级脚本按名字找 ESP（`part number scsi 0 esp`），`fastboot flash <名>` 和 `root=PARTLABEL=` 也用它；
2. ESP 的 FAT 必须是 4096 字节逻辑扇区，512 的**静默挂不上**（开机黑屏 / 掉进紧急模式）；
3. `vmlinuz` 必须是**未压缩**的 arm64 `Image`（`booti` 不解压）。

## 步骤（TWRP shell 里执行）

```sh
# 1) 勘察
cat /sys/block/sda/queue/logical_block_size    # 应输出 4096
sgdisk -p /dev/sda                             # 没 sgdisk → parted /dev/sda unit MiB print free
ls -l /dev/block/by-name/                      # 已有 esp/linux 就是分过区了，直接跳第 5 步

# 2) 缩 userdata 腾空间（顺序不能反：先缩文件系统，再缩分区）
umount /data
resize2fs /dev/block/by-name/userdata 40G      # f2fs 则用 resize.f2fs（先 resize.f2fs -h 看单位）
parted /dev/sda unit MiB resizepart <N> <新结束>   # <N>=userdata 编号；编号/Name/类型都别动

# 3) 建两个分区
sgdisk -n 0:0:+128M -t 0:ef00 -c 0:esp /dev/sda
sgdisk -n 0:0:0              -c 0:linux /dev/sda

# 4) 让内核重读分区表（没有 partprobe 就重启回 TWRP）
partprobe /dev/sda
ls -l /dev/block/by-name/esp /dev/block/by-name/linux
```

```sh
# 5) PC 上刷：文件系统由镜像提供，TWRP 里不需要 mkfs
fastboot flash boot_b boot-uboot.img && fastboot set_active b
fastboot flash esp esp.simg && fastboot flash linux rootfs.simg
```

rootfs 分区比镜像大是正常的（首启 growfs）。**只有手工铺文件（没有镜像）**时，才需要在 TWRP 里 `mke2fs -t ext4 -L linux <设备>` ＋ `mkfs.fat -F 32 -S 4096 -n ESP <设备>`，并用 `od -An -tx1 -j11 -N2 <esp设备>` 确认输出 `00 10`。

## 验证与回退

```sh
cat /proc/cmdline; df -h /; findmnt /boot/efi; ls /boot/efi/marble /boot/efi/extlinux
```

回 Android：`fastboot set_active a` —— Linux 分区和数据都留着（U-Boot 仍在 `boot_b`）。

## 故障排查

| 现象 | 原因 |
|---|---|
| 黑屏 / 掉进紧急模式 | ESP 的 FAT 不是 4096 逻辑扇区（`od` 应为 `00 10`） |
| U-Boot 菜单里没有 Linux 项 | GPT 名不是 `esp`，或 ESP 不在 LUN 0，或缺 `/extlinux/extlinux.conf` |
| `fastboot flash linux` 报找不到分区 | GPT 名不是 `linux` |
| 改完分区 Android 起不来 | userdata 的**编号或 Name**被改了 |

## 附录：细节

**TWRP 里工具缺失时：**

| 缺 | 替代 |
|---|---|
| `sgdisk` 与 `parted` 都没有 | 别硬来：换一个自带分区工具的 recovery（OrangeFox 一般都有） |
| `mkfs.fat` 是 busybox 精简版、不认 `-S` | 不要在设备上做 ESP：PC 上 `mkfs.fat -F 32 -S 4096 -n ESP esp.img` 再写进分区，或直接用 `esp.simg` |
| `partprobe` | 重启回 recovery（内核重扫 GPT，ueventd 重建 `/dev/block/by-name/*`） |
| `od` | `dd if=<设备> bs=1 skip=11 count=2 2>/dev/null \| hexdump -C` |

**扇区换算 / sgdisk 语义**：4096 字节扇区下 `1 MiB = 256 扇区`、`128 MiB = 32768`、`15 GiB = 3932160`（可直接写 `+128M`）。`sgdisk -n 0:…` 的 `0` = 用第一个可用编号，同一条命令里后续 `-c 0:` / `-t 0:` 指同一个分区；`sgdisk -F/-E` 是**最大一块空闲区**的起止扇区。缩分区优先 `parted resizepart`（不碰编号/Name/类型）；非要用 `sgdisk` 就得"删掉按原起点重建"，重建前先用 `sgdisk -i <N>` 抄下起始扇区与类型码。

**其他发行版对照**（同一台机器可以放多套，但装的时候只用一套）：

| | pmOS | ALT Mobile | 本项目 |
|---|---|---|---|
| 分区名 | `esp` + `pmos` | `esp` + `rootfs2` | `esp` + `linux` |
| ESP 大小 | 512 MiB–1 GiB | 实测 `/dev/sda34` | 128 MiB（实测 GPT 号 34） |
| ESP 内路径 | `/extlinux/extlinux.conf` | `/alt/vmlinuz`、`/extlinux/alt.conf` | `/marble/vmlinuz`、`/extlinux/extlinux.conf` |
| 装法 | recovery 里铺文件 | recovery 里铺文件 | `fastboot flash` 刷 sparse 镜像 |

设备上 ESP 挂在 **`/boot/efi`**；内核 deb 的 postinst 会读 `/etc/fstab` 改写 `extlinux.conf` 的 `root=` 并同步三件套到 ESP，所以升级内核不用重刷镜像。刷 `linux` 分区 = 重装系统，分区内数据（含 `/home`）全没。

参考：`iLtanaka/linux-marble` 的 `AGENTS.md` 部署架构、本仓库 `README.md` 与 `rootfs-debian.yml`、`iLtanaka/u-boot-marble` 的 `board/qualcomm/xiaomi-marble.env`、[作者的安装指南](https://wiki.nura.eco/wiki/Xiaomi_POCO_F5_/_Redmi_Note_12_Turbo_(xiaomi-marble))。
