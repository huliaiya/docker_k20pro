# Docker 内核 · Redmi K20 Pro (raphael)

给 **Redmi K20 Pro / K20 Pro Premium（raphael / SM8150）** 编译一个能跑 Docker 的 4.14 内核，
产物是可直接刷入的 `boot-docker.img`。

不含 KernelSU、不含 NetHunter、不含 LXC。root 自己用 Magisk 或别的方式处理。

---

## 适用设备

| 项 | 值 |
|---|---|
| 机型 | Redmi K20 Pro / K20 Pro Premium（raphael） |
| SoC | 骁龙 855 / 855+（SM8150 / SM8150-AC） |
| 目标系统 | MIUI 12.5.6（RFKCNXM）/ Android 11 |
| 内核基线 | 设备原厂 4.14.180，编译自 4.14.268 源码 |

其它 ROM / 其它机型不保证能开机。刷之前先备份 boot 分区。

---

## 产物

一次构建只出一个文件：

**`boot-docker.img`** —— 新内核已经替换进原厂 boot.img，
`ramdisk` / `dtb` / `header` / `cmdline` 全部保留原样。

不是 AnyKernel3 卡刷包，不需要 Recovery 里跑脚本。直接刷镜像。

---

## 怎么用

1. Actions → **Docker 内核 · raphael** → **Run workflow**
2. 等 40~70 分钟
3. 下载 Artifacts → `boot-docker-raphael` → 得到 `boot-docker.img`

流水线共 10 步：拉仓库 → 装依赖 → 下 clang → 拉内核源码 → 注入 Docker 配置 →
编译 → 校验 → 准备 magiskboot → 塞进 boot.img → 上传。

---

## 刷入

```bash
# 1) 备份原厂 boot —— 必做，这是后悔药
adb shell su -c "dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot_stock.img"

# 2) 刷入
adb reboot bootloader
fastboot flash boot boot-docker.img
fastboot reboot
```

TWRP 也可以：安装 → 安装镜像 → 选 boot 分区 → 选 `boot-docker.img`。

**回滚**：同样方式刷回 `boot_stock.img`。

---

## 内核带了什么

配置由流水线在编译前注入，编译后 `DOCKER-VERIFY.sh` 逐项校验，缺一项直接构建失败：

| 类别 | 关键项 |
|---|---|
| 命名空间 | `PID_NS` `NET_NS` `IPC_NS` `UTS_NS` `USER_NS` |
| Cgroup v1 | `CGROUPS` `MEMCG` `CGROUP_DEVICE` `CGROUP_PIDS` `CPUSETS` `BLK_CGROUP` |
| 网络 / 防火墙 | `VETH` `BRIDGE` `NF_NAT` `IP_NF_NAT` `MASQUERADE` `XT_MATCH_ADDRTYPE` `XT_MARK` |
| 文件系统 | `OVERLAY_FS` `EXT4_FS` `F2FS_FS` `TMPFS_XATTR` `FHANDLE` |
| IPC | `SYSVIPC` `POSIX_MQUEUE` |
| 其它 | `SECCOMP` `SECCOMP_FILTER` `MODULES` `PSI` |

原始 `raphael_defconfig` 在 Docker 场景下缺 27 项（`PID_NS` 和 `FHANDLE` 甚至是显式关闭的）。
注入后用真实 kconfig 展开 6331 行 `.config`，校验结果 **致命缺失 0 项**。

### 两个已知限制

- **`CFS_BANDWIDTH` 开不了**：`init/Kconfig` 里写的是 `depends on !SCHED_WALT`，
  而高通 CAF 内核启用了 `SCHED_WALT`。代价是 `docker run --cpu-quota` 不生效，容器本身能正常跑。
- **开 `MEMCG` 会挤掉 `ANDROID_SIMPLE_LMK`**（它 `depends on !MEMCG`）。
  流水线补了 `CONFIG_PSI=y`，让 Android 11 的 lmkd 走压力停滞模式接管内存回收。

---

## 目录

```
.github/workflows/docker-kernel.yml   构建流水线（10 步）
boot/boot-stock.img.xz                原厂 boot.img，供流水线替换内核用
scripts/check-kernel-config/
  LXC-DOCKER-OPEN-CONFIG.sh           注入 160 项容器相关配置
  DOCKER-EXTRA-CONFIG.sh              补 4 项（SYSVIPC / TMPFS_XATTR / NET_CLASSID / PSI）
  DOCKER-VERIFY.sh                    编译后校验，缺项直接失败
docs/DOCKER-K20PRO.md                 从构建到跑起 dockerd 的完整流程
docs/WORKFLOW-FIX.md                  workflow 手改指引（备用）
```

---

## 刷完之后：跑 Docker

内核只是第一步，Android 本身没有 `dockerd`，还得在 chroot 的 Linux 里跑。
完整步骤见 **[docs/DOCKER-K20PRO.md](docs/DOCKER-K20PRO.md)** 第 5 节，几个要点：

- 需要 chroot 一个 arm64 的 Linux 发行版（Debian / Ubuntu 都行）
- 4.14 内核没有 nftables，`iptables` 要切到 `iptables-legacy`
- cgroup v1 要整个 `/sys/fs/cgroup` 透传进 chroot
- `/etc/resolv.conf` 要自己写
- `overlay2` 起不来就退到 `--storage-driver=vfs`

---

## 致谢

- 内核源码：[Laulan56/android_kernel_xiaomi_sm8150](https://github.com/Laulan56/android_kernel_xiaomi_sm8150)（`miui` 分支）
- boot 解包/重打包：[Magisk](https://github.com/topjohnwu/Magisk) 的 `magiskboot`
- 容器配置清单：[5kind/LXC-DOCKER-KernelSU_Action](https://github.com/5kind/LXC-DOCKER-KernelSU_Action)

---

## 免责

刷内核有风险，可能开不了机。刷之前备份 boot，出问题刷回去。
