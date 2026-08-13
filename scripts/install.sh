#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")" && pwd -P
)
LIB_DIR="$SCRIPT_DIR/lib"
for lib in common.sh vault.sh title.sh; do
	if [ ! -r "$LIB_DIR/$lib" ]; then
		printf '%s\n' "缺少安装器组件：$LIB_DIR/$lib。请下载完整 bundle 后重试。" >&2
		exit 1
	fi
	# shellcheck disable=SC1090
	. "$LIB_DIR/$lib"
done

installer_help() {
	cat <<'EOF'
XyMediaVault unified installer

Usage:
  bash install.sh menu
  bash install.sh vault install --channel stable|beta [--dir DIR] [--non-interactive]
  bash install.sh vault check
  bash install.sh vault upgrade [--channel stable|beta] [--yes]
  bash install.sh vault switch --channel stable|beta [--yes]
  bash install.sh title install --channel stable|beta [--yes]
  bash install.sh title check
  bash install.sh title upgrade [--channel stable|beta] [--yes]
  bash install.sh env | version | status [--json]
  bash install.sh uninstall vault|title [--purge-data] [--yes]
  bash install.sh help

Run without arguments only from a TTY to open the numeric menu.
EOF
}

menu() {
	MENU_INTERACTIVE=true
	while :; do
		cat <<'EOF'

XyMediaVault 管理菜单
1) 安装 XyMediaVault 稳定版
2) 安装 XyMediaVault Beta
3) 检查/升级 XyMediaVault
4) 切换 XyMediaVault 版本通道
5) 安装 XyMedia Title
6) 检查/升级 XyMedia Title
7) 环境检测
8) 当前版本
9) 服务状态
10) 卸载/维护
0) 退出
EOF
		printf '请选择：'
		IFS= read -r choice || return 0
		case "$choice" in
		1)
			vault_install stable
			pause_menu
			;;
		2)
			vault_install beta
			pause_menu
			;;
		3)
			vault_check
			confirm false '升级 Vault 并备份/替换容器。' || continue
			vault_upgrade --yes
			pause_menu
			;;
		4)
			vault_switch
			pause_menu
			;;
		5)
			title_menu_install
			pause_menu
			;;
		6)
			title_menu_upgrade
			pause_menu
			;;
		7)
			env_report
			pause_menu
			;;
		8)
			version_report
			pause_menu
			;;
		9)
			status_report
			pause_menu
			;;
		10) maintenance_menu ;;
		0) return 0 ;; *) printf '%s\n' '无效选择，请输入菜单数字。' ;;
		esac
	done
}
title_menu_install() {
	printf '%s\n' 'Title 通道：1) stable  2) beta  0) 返回'
	printf '请选择：'; IFS= read -r c || return 0
	case "$c" in 1) title_install stable ;; 2) title_install beta ;; esac
}
title_menu_upgrade() {
	title_check
	printf '%s\n' '升级 Title：1) 当前通道  2) stable  3) beta  0) 返回'
	printf '请选择：'; IFS= read -r c || return 0
	case "$c" in 1) title_upgrade --yes ;; 2) title_upgrade --channel stable --yes ;; 3) title_upgrade --channel beta --yes ;; esac
}
pause_menu() {
	printf '按回车继续...'
	IFS= read -r _ || true
}
maintenance_menu() {
	printf '%s\n' '维护：1) 卸载 Vault  2) 卸载 Title 0) 返回'
	printf '请选择：'
	IFS= read -r c || return 0
	case "$c" in 1) uninstall_service vault ;; 2) uninstall_service title ;; esac
}

legacy_dispatch() {
	printf '%s\n' '警告：旧版位置参数安装已弃用，将映射为 vault install。' >&2
	dir=$1
	vault_install stable --dir "$dir"
}

case "${1:-}" in
'') if is_tty; then menu; else
	installer_help >&2
	exit 2
fi ;;
menu) menu ;;
help | -h | --help) installer_help ;;
env) env_report ;;
version) version_report ;;
status)
	shift
	status_report "$@"
	;;
vault)
	shift
	vault_command "$@"
	;;
title)
	shift
	title_command "$@"
	;;
uninstall)
	shift
	uninstall_service "$@"
	;;
-*)
	printf '%s\n' "未知命令：$1" >&2
	installer_help >&2
	exit 2
	;;
/* | ./* | ../*) legacy_dispatch "$@" ;;
*)
	printf '%s\n' "未知命令：$1" >&2
	installer_help >&2
	exit 2
	;;
esac
