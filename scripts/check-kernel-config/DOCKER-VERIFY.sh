#!/bin/bash
# 校验编译产物 .config 是否真的具备 Docker 运行所需能力。
# 用法: DOCKER-VERIFY.sh <.config 路径>
# 任何一项不是 =y 就返回非 0，让构建直接失败，避免刷出一个跑不了容器的内核。
set -u

FILE=$1
[ -f "$FILE" ] || {
	echo "Provide a built .config as argument: $FILE"
	exit 1
}

# 分组的必需项。全部要求 =y：容器是核心功能，不接受 =m。
REQUIRED="
CONFIG_NAMESPACES
CONFIG_NET_NS
CONFIG_PID_NS
CONFIG_IPC_NS
CONFIG_UTS_NS
CONFIG_USER_NS
CONFIG_CGROUPS
CONFIG_MEMCG
CONFIG_CGROUP_DEVICE
CONFIG_CGROUP_PIDS
CONFIG_CGROUP_FREEZER
CONFIG_CPUSETS
CONFIG_CGROUP_CPUACCT
CONFIG_BLK_CGROUP
CONFIG_VETH
CONFIG_BRIDGE
CONFIG_NETFILTER
CONFIG_NETFILTER_ADVANCED
CONFIG_NF_CONNTRACK
CONFIG_NF_NAT
CONFIG_IP_NF_IPTABLES
CONFIG_IP_NF_FILTER
CONFIG_IP_NF_NAT
CONFIG_IP_NF_TARGET_MASQUERADE
CONFIG_IP_NF_TARGET_REDIRECT
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
CONFIG_NETFILTER_XT_MARK
CONFIG_BRIDGE_NETFILTER
CONFIG_OVERLAY_FS
CONFIG_EXT4_FS
CONFIG_F2FS_FS
CONFIG_TMPFS_XATTR
CONFIG_TMPFS_POSIX_ACL
CONFIG_BLK_DEV_LOOP
CONFIG_FHANDLE
CONFIG_SYSVIPC
CONFIG_POSIX_MQUEUE
CONFIG_MULTIUSER
CONFIG_SECCOMP
CONFIG_SECCOMP_FILTER
CONFIG_UNIX
CONFIG_PACKET
CONFIG_INET
"

miss=0
warn=0

echo "==> Docker 能力校验: $FILE"

for c in $REQUIRED; do
	if grep -qE "^${c}=y$" "$FILE"; then
		continue
	fi
	if grep -qE "^${c}=m$" "$FILE"; then
		echo "  [FATAL] $c=m，容器功能必须是内置 =y"
		miss=$((miss + 1))
	elif grep -qE "^# ${c} is not set$" "$FILE"; then
		echo "  [FATAL] $c 被显式关闭"
		miss=$((miss + 1))
	else
		echo "  [FATAL] $c 未出现在配置中（依赖不满足或内核版本无此项）"
		miss=$((miss + 1))
	fi
done

# 非致命但影响体验的项
# CFS_BANDWIDTH: 本树 init/Kconfig 里是 "depends on !SCHED_WALT"，
# 而高通 CAF 内核开 SCHED_WALT，所以物理上不可能开启。
# 代价只是 docker 无法用 --cpu-quota 限制 CPU 带宽，不影响启动与运行。
for c in CONFIG_CFS_BANDWIDTH CONFIG_CGROUP_NET_CLASSID CONFIG_CGROUP_NET_PRIO CONFIG_CHECKPOINT_RESTORE CONFIG_NETFILTER_XT_MATCH_COMMENT; do
	grep -qE "^${c}=y$" "$FILE" || {
		echo "  [warn]  $c 未启用（不阻塞构建）"
		warn=$((warn + 1))
	}
done

echo "==> 结果: 致命缺失 $miss 项, 提示 $warn 项"
[ "$miss" -eq 0 ] || exit 1
exit 0
