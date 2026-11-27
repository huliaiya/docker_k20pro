# Redmi K20 Pro (raphael) — Docker 内核构建与部署

目标设备：**Redmi K20 Pro Premium Edition / raphael / SM8150-AC**
当前系统：MIUI 12.5.6 (RFKCNXM) / Android 11 / 内核 4.14.180-perf-gb24d1131198a

本仓库 config.env 已按该设备配置好：编译 `Laulan56/android_kernel_xiaomi_sm8150` 的 `miui` 分支 + `raphael_defconfig`，产出带 KernelSU / LXC / Docker / NetHunter 支持的 `Image.gz-dtb`。

---

## 1. 为什么必须换内核

官方 MIUI 内核缺以下能力，`dockerd` 根本起不来（实测 `raphael_defconfig` 原始状态）：

| 缺失项 | 后果 |
|---|---|
| `CONFIG_PID_NS`（显式关闭）、`CONFIG_USER_NS` | 容器无法创建 PID/User 命名空间，`runc` 直接报错 |
| `CONFIG_FHANDLE`（显式关闭） | 部分容器运行时与 overlay 场景失败 |
| `CONFIG_MEMCG` / `CONFIG_CGROUP_DEVICE` / `CONFIG_CGROUP_PIDS` | 无法做内存/设备/PID 限制，dockerd 起不了 cgroup 管理 |
| `CONFIG_NETFILTER_ADVANCED` / `XT_MATCH_ADDRTYPE` / `XT_MARK` / `BRIDGE_NETFILTER` | docker0 网桥与端口映射不工作 |
| `CONFIG_SYSVIPC` | 容器内 IPC 程序异常 |

本仓库的处理链路：

```
LXC-DOCKER-OPEN-CONFIG.sh   → 补齐 160 项（含 PID_NS / USER_NS / MEMCG / CGROUP_DEVICE / VETH / OVERLAY_FS …）
DOCKER-EXTRA-CONFIG.sh      → 补 LXC 脚本漏掉的 3 项（SYSVIPC / TMPFS_XATTR / CGROUP_NET_CLASSID）
DOCKER-VERIFY.sh            → 编译后校验产物 .config，缺一项就让构建失败
```

实测：原始 defconfig 缺口 27 项 → 跑完前两个脚本 + KSU 补充配置后，用真实 kconfig（`make ARCH=arm64 raphael_defconfig`）展开 6331 行 `.config`，`DOCKER-VERIFY.sh` 报 **致命缺失 0 项**。

```
CONFIG_PID_NS=y   CONFIG_USER_NS=y   CONFIG_NET_NS=y    CONFIG_IPC_NS=y
CONFIG_UTS_NS=y   CONFIG_MEMCG=y     CONFIG_CGROUP_DEVICE=y  CONFIG_CGROUP_PIDS=y
CONFIG_FHANDLE=y  CONFIG_VETH=y      CONFIG_BRIDGE=y    CONFIG_OVERLAY_FS=y
CONFIG_NF_NAT=y   CONFIG_SYSVIPC=y   CONFIG_MODULES=y   CONFIG_PSI=y
```

### 两个必须知道的权衡

**1. `CONFIG_CFS_BANDWIDTH` 在这棵树上永远开不了**

`init/Kconfig:849` 写的是 `depends on !SCHED_WALT`，而高通 CAF 内核启用了 `CONFIG_SCHED_WALT`（MIUI 的调度/省电基础），所以该项物理上不可能为 y。
代价：`docker run --cpu-quota` 限制 CPU 带宽不生效，`docker info` 会提示 No CPU CFS quota support。容器能正常跑。

**2. 开 `CONFIG_MEMCG` 会挤掉 `CONFIG_ANDROID_SIMPLE_LMK`**

`drivers/android/Kconfig:59`：`depends on !ANDROID_LOW_MEMORY_KILLER && !MEMCG && !PSI`。
开了 MEMCG（Docker 限制容器内存必需），Simple LMK 自动消失。本仓库的做法是补 `CONFIG_PSI=y`，让 Android 11 的 lmkd 走压力停滞信息模式接管回收。
如果刷完发现后台进程被杀得异常，可以把 `scripts/check-kernel-config/DOCKER-EXTRA-CONFIG.sh` 里的 `CONFIG_PSI` 留下、改用关闭 MEMCG 的版本（Docker 仍可运行，但 `--memory` 不生效）。

---

## 2. 构建

> 推荐用 GitHub Actions：x86 runner + AOSP clang，40~70 分钟出包。
> 本机（proot 里的 aarch64 Ubuntu）编同样内核实测约 0.6s/目标文件，全量要几小时，不划算。

1. Fork 本仓库到自己的账号，或直接 push 到现有仓库。
2. `config.env` 已配好，不需要改：

   ```ini
   KERNEL_SOURCE=https://github.com/Laulan56/android_kernel_xiaomi_sm8150
   KERNEL_SOURCE_BRANCH=miui
   KERNEL_CONFIG=raphael_defconfig
   KERNEL_IMAGE_NAME=Image.gz-dtb     # 该树 CONFIG_IMG_GZ_DTB=y，产物就是这个名字
   ENABLE_KERNELSU=false              # 纯 Docker 内核，不内置 root
   BUILD_BOOT_IMG=false               # 只出 AnyKernel3 + 原始内核
   ```

3. Actions → **编译 ksu docker lxc nethunter 内核** → Run workflow。
4. 产物（Artifacts）：

   | 文件 | 用途 |
   |---|---|
   | `AnyKernel3-raphael-<时间>.zip` | **TWRP 直接刷**，只换内核，保留原机 ramdisk/dtb |
   | `Image.gz-dtb-raphael-<时间>` | 裸内核，用于自己修补 boot.img 或 fastboot |

> 构建日志末尾会打印 `Docker 能力校验` 结果。看到 `致命缺失 0 项` 才继续往下走。

### 工具链是常见卡点

AOSP 的 clang 预编译仓库里，每个 kernel-build 分支都会列出所有版本目录，但大多是**空占位**——空目录打出的 tar 包照样 HTTP 200 下载成功，只会在几十分钟后报 `clang: not found`。

workflow 里已加防呆：解包后检查 `clang-aosp/bin/clang` 是否存在，不存在立即失败。
真遇到这个问题，把 `config.env` 改成已验证组合：

```ini
CLANG_BRANCH=master-kernel-build-2022
CLANG_VERSION=r450784e
```

若因警告被当成错误而中断，把 `DISABLE_CC_WERROR` 改成 `true`。

---

## 3. 刷入与回滚

**前提**：已解锁 Bootloader 并有 TWRP（或能从 fastboot 引导 TWRP）。

```bash
# 1) 备份原厂 boot —— 必做，这一步是后悔药
adb shell su -c "dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot_stock.img"
adb pull /sdcard/boot_stock.img
```

**刷入**：把 `AnyKernel3-*.zip` 拷到手机，TWRP → 安装 → 选 zip → 滑动刷入 → 重启系统。

**回滚**：

```bash
adb shell su -c "dd if=/sdcard/boot_stock.img of=/dev/block/bootdevice/by-name/boot"
# 或 TWRP 里刷回 boot_stock.img（安装镜像 → 选 boot 分区）
```

### 本机 boot.img 的实际情况（已实测）

用 magiskboot 解包你给的 boot.img，结果：

```
HEADER_VER      [1]
KERNEL_SZ       [43958745]      # raw Image（已解压）
RAMDISK_SZ      [0]             # ← 没有 ramdisk
OS_VERSION      [11.0.0]  OS_PATCH_LEVEL [2021-10]
CMDLINE         [console=ttyMSM0,115200n8 earlycon=... buildvariant=user]
KERNEL_DTB_SZ   [1995189]       # dtb 是单独一段
```

因为 `ramdisk_size=0`，Magisk 无法用常规方式往 ramdisk 里注入 `magiskinit`。要 root 只有两条路：

- 刷一个自带 KernelSU 的内核（把 `config.env` 里 `ENABLE_KERNELSU` 改回 `true`，`KERNELSU_TAG` 必须是 `v0.9.5`）
- 用 Magisk 的“安装到未激活的槽位/其他方式”——本机单槽且无 ramdisk，成功率低

**纯 Docker 用途不需要 root 之外的东西**：只要内核带 namespace/cgroup/netfilter/overlayfs，root 用哪种方案都行。

### 自己修补 boot.img（不经 TWRP）

拿到 Actions 产出的 `Image.gz-dtb` 后，用 Magisk 自带的 `magiskboot`：

```bash
# 工作目录里放：boot.img（原厂）、Image.gz-dtb（新内核）
magiskboot unpack -h boot.img          # 得到 kernel / kernel_dtb / header
cp Image.gz-dtb kernel                 # 直接当 kernel 丢进去，magiskboot 会自己分离 dtb
magiskboot repack boot.img boot-new.img
fastboot flash boot boot-new.img
```

若想严格保留原厂 dtb，就把新内核拆成 raw Image 只替 `kernel`，`kernel_dtb` 不动。

---

## 4. 验证内核真的支持容器

```bash
su
zcat /proc/config.gz | grep -E '^CONFIG_(PID_NS|USER_NS|NET_NS|IPC_NS|UTS_NS|CGROUPS|MEMCG|CGROUP_DEVICE|CGROUP_PIDS|FHANDLE|VETH|BRIDGE|OVERLAY_FS|IP_NF_NAT|SYSVIPC)=y'
```

全 `=y` 才叫能用。再跑一次命名空间实测：

```bash
unshare -p -f --mount-proc sh -c 'echo "PID NS OK"; ps -ef | head -3'
unshare -n sh -c 'ip link set lo up; ip addr show lo'
```

两条都成功 → 内核侧齐了。

---

## 5. 部署 Docker

Android 没有 dockerd，需要 rootfs。这里用你现有的 Ubuntu chroot（`/data/ubuntu` 之类），或新建一个：

```bash
# 以 Debian 12 arm64 rootfs 为例（在 PC 上下载后 push）
# https://github.com/debuerreotype/docker-debian-artifacts 取 bookworm rootfs.tar.xz
su
mkdir -p /data/docker-root
tar -xJf /sdcard/bookworm-arm64.tar.xz -C /data/docker-root
```

### 5.1 启动脚本（Android 侧，root 执行）

`: /data/local/bin/start-chroot.sh`

```bash
#!/system/bin/sh
R=/data/docker-root

# 基础挂载
mount -t proc proc   $R/proc
mount -t sysfs sysfs $R/sys
mount --rbind /dev    $R/dev
mount -t tmpfs tmpfs  $R/dev/shm

# cgroup v1 整个目录透传（4.14 只有 v1）
mount --rbind /sys/fs/cgroup $R/sys/fs/cgroup

# 网络转发（容器出网必需）
echo 1 > /proc/sys/net/ipv4/ip_forward

# SELinux 放行
setenforce 0 2>/dev/null

# DNS
mkdir -p $R/run/systemd/resolve
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > $R/etc/resolv.conf

exec chroot $R /bin/bash -l
```

```bash
chmod 755 /data/local/bin/start-chroot.sh
/data/local/bin/start-chroot.sh
```

### 5.2 chroot 内安装

```bash
apt update
apt install -y docker.io iptables

# 关键：4.14 内核没有 nftables，必须切 legacy
update-alternatives --set iptables  /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
```

### 5.3 启动 dockerd

```bash
mkdir -p /var/log
nohup dockerd \
  --exec-opt native.cgroupdriver=cgroupfs \
  --storage-driver=overlay2 \
  --iptables=true \
  --bridge=docker0 \
  >/var/log/dockerd.log 2>&1 &

sleep 5 && docker info
```

堆栈跟踪在 `/var/log/dockerd.log`。

---

## 6. 常见坑

| 现象 | 原因 | 处理 |
|---|---|---|
| `failed to start daemon: Error initializing network controller: iptables: not found` | 内核无 iptables 匹配或用户态缺 iptables | 确认 `CONFIG_IP_NF_IPTABLES=y`，并切到 `iptables-legacy` |
| `operation not permitted` 创建 cgroup | cgroup 未透传 / SELinux enforcing | 检查 `mount \| grep cgroup`，`setenforce 0` |
| `overlay2` 驱动初始化失败 | 上层目录所在 fs 不支持 xattr/d_type | 换 `--storage-driver=vfs`（慢但能跑），或把 `/var/lib/docker` 放到 f2fs 上 |
| 容器内无网络 | `ip_forward=0` 或 MIUI 防火墙链拦截 | `echo 1 > /proc/sys/net/ipv4/ip_forward`，检查 `iptables -t nat -L POSTROUTING` |
| 容器内 DNS 失败 | 没有 `/etc/resolv.conf` | 见 5.1 脚本里的 DNS 段 |
| 内核刷完不开机 | ramdisk/dtb 不匹配 | 用 AnyKernel3 方式刷入（保留原机 ramdisk），别用 boot.img 重打包 |
| 管理器连不上内核 | KSU 管理器版本与内核版本不一致 | 内核 0.9.5 → 管理器必须 0.9.5 |

---

## 7. 实测记录

在本地拉下真实内核树（4.14.268 / `miui` 分支）做过以下验证：

| 验证项 | 结果 |
|---|---|
| `patches/Makefile.patch` 应用 | 通过（`patch --dry-run` exit 0） |
| `patches/Android-Container/cgroup.patch` 应用 | 通过，但靠 fuzz 1 + offset -144（上下文已漂移，脆弱） |
| `xt_qtaguid.patch` | 该树无 `net/netfilter/xt_qtaguid.c`，workflow 里的文件判断会自动跳过 |
| NetHunter 4.14 五个补丁 | 全部可应用 |
| 子模块 `fs/exfat` | `.gitmodules` 里唯一子模块，必须 `--init --recursive` |
| 配置注入 → kconfig 展开 | defconfig 显式要求 867 项，最终落地 856 项 |
| `DOCKER-VERIFY.sh` | 致命缺失 0，仅 CFS_BANDWIDTH 警告 |

未落地的 11 项：`CFS_BANDWIDTH` / `ANDROID_SIMPLE_LMK`（原因见上），`AUFS_FS`，以及 NetHunter 的 6 项（`BT_HCIBTUSB_BCM/RTL`、`DVB_RTL2830/2832/2832_SDR/SI2168/ZD1301_DEMOD`、`RTL8XXXU_UNTESTED`）——后者依赖在 defconfig 里没开，属可选外设支持，不影响 Docker。

## 8. 已知未验证项

- 本仓库改完的 workflow **尚未在 GitHub Actions 上跑出过完整产物**（本地只验证到配置层与补丁层）。
- 真机刷入后的开机与 dockerd 启动需在你的设备上实测；MIUI 12.5.6 的 dtb/ramdisk 兼容性以实际刷入为准。
- 内核源码树 `Laulan56/android_kernel_xiaomi_sm8150` 已于 2026-06-28 归档（只读），`miui` 分支仍可克隆，但不再接受更新。
