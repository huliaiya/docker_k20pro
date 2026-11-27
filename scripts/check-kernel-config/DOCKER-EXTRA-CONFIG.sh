#!/bin/bash
# 补齐 LXC-DOCKER-OPEN-CONFIG.sh 未覆盖、但 dockerd 需要的配置项。
# 用法: DOCKER-EXTRA-CONFIG.sh <defconfig 路径> [-w]
# 不带 -w 只检查，带 -w 直接写入。
set -u

FILE=$1
[ -f "$FILE" ] || {
	echo "Provide a config file as argument"
	exit 1
}

write=false
[ "${2:-}" = "-w" ] && write=true

# dockerd 真正依赖、LXC 脚本没管的项：
#   SYSVIPC      POSIX 共享内存/信号量，容器内大量程序依赖
#   TMPFS_XATTR  tmpfs 上 overlay/容器的 xattr 操作
#   CGROUP_NET_CLASSID  net_cls 控制器，--net-cls 与部分编排工具会读
#   PSI          开启 MEMCG 后会挤掉 ANDROID_SIMPLE_LMK（它 depends on !MEMCG），
#                开 PSI 让 Android 11 的 lmkd 用压力停滞信息接管内存回收，
#                否则内核里将没有低内存杀手。
CONFIGS_ON="
CONFIG_SYSVIPC
CONFIG_TMPFS_XATTR
CONFIG_CGROUP_NET_CLASSID
CONFIG_PSI
"

errors=0
fixes=0

echo "==> Docker 补充配置检查: $FILE"

for c in $CONFIGS_ON; do
	if grep -qE "^${c}=(y|m)" "$FILE"; then
		echo "  [ok]   $c 已启用"
		continue
	fi

	if ! $write; then
		echo "  [miss] $c 未启用"
		errors=$((errors + 1))
		continue
	fi

	if grep -qE "^# ${c} is not set$" "$FILE"; then
		sed -i "s,^# ${c} is not set$,${c}=y," "$FILE"
	else
		# 去重后追加，避免多次运行堆出重复行
		sed -i "/^# ${c} is not set$/d" "$FILE"
		printf '%s=y\n' "$c" >>"$FILE"
	fi
	echo "  [fix]  $c -> =y"
	fixes=$((fixes + 1))
done

if $write; then
	echo "==> 写入完成，修改 $fixes 项"
else
	echo "==> 缺失 $errors 项"
fi

[ "$errors" -eq 0 ] || exit 1
