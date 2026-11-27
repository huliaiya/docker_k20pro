# workflow 文件改不动？照这里改 5 处

GitHub App 没有 `workflows` 权限，`.github/workflows/*.yml` 无法通过 push 或 API 写入：

```
refusing to allow a GitHub App to create or update workflow
`.github/workflows/zbuild-kernel.yml` without `workflows` permission
```

所以这一步必须由有权限的账号在网页上完成。**只有 3 个动作**。

---

## 动作 1：打开文件

https://github.com/huliaiya/docker_k20pro/blob/master/.github/workflows/zbuild-kernel.yml

点右上角铅笔图标 → 进入编辑。

---

## 动作 2：全文替换 `@v3` → `@v4`

用浏览器的 Ctrl+F（手机端点编辑器的搜索），把 `@v3` 全部替换成 `@v4`。

一共 5 处：

| 行 | 原内容 | 改成 |
|---|---|---|
| 18 | `actions/checkout@v3` | `actions/checkout@v4` |
| 338 | `actions/upload-artifact@v3` | `actions/upload-artifact@v4` |
| 345 | `actions/upload-artifact@v3` | `actions/upload-artifact@v4` |
| 352 | `actions/upload-artifact@v3` | `actions/upload-artifact@v4` |
| 359 | `actions/upload-artifact@v3` | `actions/upload-artifact@v4` |

> `upload-artifact@v3` 已于 2025-01-30 停止服务，不换的话编译能跑完但产物下不来。

---

## 动作 3：给 LXC 配置那行补上 Docker 配置

搜索 `LXC-DOCKER-OPEN-CONFIG.sh`，会找到这一行（约第 161 行）：

```yaml
        bash $GITHUB_WORKSPACE/scripts/check-kernel-config/LXC-DOCKER-OPEN-CONFIG.sh arch/${{ env.ARCH }}/configs/${{ env.KERNEL_CONFIG }} -w
```

在**同一行末尾**追加 `&&` 和第二个脚本：

```yaml
        bash $GITHUB_WORKSPACE/scripts/check-kernel-config/LXC-DOCKER-OPEN-CONFIG.sh arch/${{ env.ARCH }}/configs/${{ env.KERNEL_CONFIG }} -w && bash $GITHUB_WORKSPACE/scripts/check-kernel-config/DOCKER-EXTRA-CONFIG.sh arch/${{ env.ARCH }}/configs/${{ env.KERNEL_CONFIG }} -w
```

这一步补的是 LXC 脚本没覆盖的 4 项：`SYSVIPC` / `TMPFS_XATTR` / `CGROUP_NET_CLASSID` / `PSI`。

> `PSI` 尤其重要：开了 `MEMCG`（Docker 必需）会挤掉 `ANDROID_SIMPLE_LMK`，不补 PSI 的话内核里就没有低内存杀手。

改完点 **Commit changes**。

---

## 可选动作：删掉废弃 workflow

https://github.com/huliaiya/docker_k20pro/blob/master/.github/workflows/xxxbuild-kernel.yml

右上角 → Delete file → Commit。

它硬编码了别人的 oppo a72 内核仓库，且与主流程触发条件相同——点一次 Star 会同时跑两份，这份必挂。

---

## 然后

Actions → **编译 ksu docker lxc nethunter 内核** → Run workflow。

约 40~70 分钟。日志末尾看这段：

```
==> Docker 能力校验: .config
==> 结果: 致命缺失 0 项, 提示 1 项
```

看到 `致命缺失 0 项` 就对了。产物在 Artifacts：

- `AnyKernel3-raphael-<时间>.zip` ← TWRP 刷这个
- `Image.gz-dtb-raphael-<时间>` ← 裸内核，自己修 boot.img 用

---

## 如果报 `clang: not found`

AOSP 的 clang 预编译仓库里很多版本目录是空占位，空目录打出的 tar 包也能 200 下载。改 `config.env`：

```ini
CLANG_BRANCH=master-kernel-build-2022
CLANG_VERSION=r450784e
```

这是已验证组合。

如果因警告被当成错误而中断，把 `DISABLE_CC_WERROR=false` 改成 `true`。
