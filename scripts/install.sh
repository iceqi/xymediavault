#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")" && pwd -P
)
LIB_DIR="$SCRIPT_DIR/lib"
BOOTSTRAP_TMP=
bootstrap_cleanup() {
	[ -n "${BOOTSTRAP_TMP:-}" ] && rm -rf "$BOOTSTRAP_TMP"
}
bootstrap_error() {
	printf '[xymedia] ERROR: %s\n' "$1" >&2
	exit 1
}
bootstrap_bundle() {
	ref=${XYMEDIA_INSTALLER_REF:-beta}
	repo=${XYMEDIA_INSTALLER_REPO:-iceqi/xymediavault}
	case "$ref" in
	'' | -* | *..* | *[!A-Za-z0-9._/-]*) bootstrap_error '无效的 installer ref。' ;;
	esac
	case "$repo" in
	[A-Za-z0-9._-]*/[A-Za-z0-9._-]*) ;;
	*) bootstrap_error '无效的 installer repo。' ;;
	esac
	command -v curl >/dev/null 2>&1 || bootstrap_error 'bootstrap 需要 curl。'
	command -v tar >/dev/null 2>&1 || bootstrap_error 'bootstrap 需要 tar。'
	BOOTSTRAP_TMP=$(mktemp -d "${TMPDIR:-/tmp}/xymedia-installer.XXXXXX") || bootstrap_error '无法创建临时目录。'
	trap 'bootstrap_cleanup' 0 HUP INT TERM
	archive="$BOOTSTRAP_TMP/bundle.tar.gz"
	if [ -n "${XYMEDIA_INSTALLER_ARCHIVE_URL:-}" ]; then
		url=$XYMEDIA_INSTALLER_ARCHIVE_URL
		if [ "${XYMEDIA_INSTALLER_TESTING:-0}" != 1 ]; then
			case "$url" in https://*) ;; *) bootstrap_error '生产环境 archive URL 必须使用 HTTPS。' ;; esac
		fi
	else
		base=https://codeload.github.com
		proxy=${XYMEDIA_GITHUB_PROXY:-https://gh-proxy.org/}
		if [ -n "$proxy" ]; then
			proxy=${proxy%/}/
			base=${proxy}https://codeload.github.com
		fi
		url="$base/$repo/tar.gz/refs/heads/$ref"
	fi
	if [ "${XYMEDIA_INSTALLER_TESTING:-0}" = 1 ]; then
		curl -fL --retry 3 --connect-timeout 15 --max-time 300 "$url" -o "$archive" || bootstrap_error '无法下载 installer bundle。'
	else
		curl --proto '=https' --tlsv1.2 -fL --retry 3 --connect-timeout 15 --max-time 300 "$url" -o "$archive" || bootstrap_error '无法下载 installer bundle。'
	fi
	size=$(wc -c <"$archive")
	case "$size" in '' | *[!0-9]*) bootstrap_error '无法检查 bundle 大小。' ;; esac
	[ "$size" -ge 1024 ] && [ "$size" -le 5242880 ] || bootstrap_error 'bundle 大小不在允许范围内。'
	prefix=
	while IFS= read -r entry; do
		case "$entry" in
		/* | ../* | */../* | *'/..') bootstrap_error 'bundle 包含不安全路径。' ;;
		esac
		case "$entry" in
		xymediavault-*)
			entry_prefix=${entry%%/*}
			[ -n "$prefix" ] || prefix=$entry_prefix
			[ "$entry_prefix" = "$prefix" ] || bootstrap_error 'bundle 包含多个顶层目录。'
			;;
		'') ;;
		*) bootstrap_error 'bundle 包含错误的顶层目录。' ;;
		esac
	done <<EOF
$(tar -tzf "$archive")
EOF
	[ -n "$prefix" ] || bootstrap_error 'bundle 为空。'
	case "$prefix" in xymediavault-*) ;; *) bootstrap_error 'bundle 顶层目录无效。' ;; esac
	while IFS= read -r detail; do
		case "$detail" in
		l* | h* | *' -> '* | *' link to '*) bootstrap_error 'bundle 不允许符号链接或硬链接。' ;;
		esac
	done <<EOF
$(tar -tvzf "$archive")
EOF
	repo_dir="$BOOTSTRAP_TMP/repo"
	mkdir "$repo_dir"
	tar -xzf "$archive" -C "$repo_dir" --strip-components=1 || bootstrap_error '无法提取 installer bundle。'
	for required in scripts/install.sh scripts/legacy-install.sh scripts/lib/common.sh scripts/lib/vault.sh scripts/lib/title.sh; do
		[ -f "$repo_dir/$required" ] && [ ! -L "$repo_dir/$required" ] || bootstrap_error "bundle 缺少或链接化文件：$required。"
	done
	chmod +x "$repo_dir/scripts/install.sh" "$repo_dir/scripts/legacy-install.sh"
	export XYMEDIA_INSTALLER_BOOTSTRAPPED=1
	child=$repo_dir/scripts/install.sh
	if [ "$#" -eq 0 ]; then
		if [ -r /dev/tty ] && [ -w /dev/tty ]; then
			sh "$child" </dev/tty >/dev/tty 2>/dev/tty
			status=$?
		else
			printf '%s\n' '无参数菜单需要可读写的 /dev/tty；请 clone 完整仓库后执行，或使用带参数的非交互命令。' >&2
			status=2
		fi
	else
		sh "$child" "$@" </dev/null
		status=$?
	fi
	bootstrap_cleanup
	trap - 0 HUP INT TERM
	exit "$status"
}

if [ ! -r "$LIB_DIR/common.sh" ] || [ ! -r "$LIB_DIR/vault.sh" ] || [ ! -r "$LIB_DIR/title.sh" ] || [ ! -r "$SCRIPT_DIR/legacy-install.sh" ]; then
	bootstrap_bundle "$@"
fi
for lib in common.sh vault.sh title.sh; do
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
	export MENU_INTERACTIVE=true
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
	printf '请选择：'
	IFS= read -r c || return 0
	case "$c" in 1) title_install stable ;; 2) title_install beta ;; esac
}
title_menu_upgrade() {
	title_check
	printf '%s\n' '升级 Title：1) 当前通道  2) stable  3) beta  0) 返回'
	printf '请选择：'
	IFS= read -r c || return 0
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
