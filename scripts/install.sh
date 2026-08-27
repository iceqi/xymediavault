#!/usr/bin/env sh
set -eu

default_release=v1.4.0
release=${XYMEDIA_RELEASE:-$default_release}
component_updater_url='https://raw.githubusercontent.com/iceqi/xymediavault/21e99c95df0c800079fff327c5fcf78b05734612/scripts/update-components.sh'
migration_url='https://raw.githubusercontent.com/iceqi/xymediavault/9fa0ed12a8547895f44ecea036bf5558053798c2/scripts/migrate-components-storage.sh'
reset_url='https://raw.githubusercontent.com/iceqi/xymediavault/8da3d162ac9945d3887df524c7b6a5c8c89d3d1a/scripts/reset-fresh-install.sh'
interactive=0

error() {
	if [ "$interactive" -eq 1 ]; then
		printf '%s\n' "[xymedia] 错误：$1" >&4
	else
		printf '%s\n' "[xymedia] 错误：$1" >&2
	fi
	exit 2
}

digits_only() {
	case "$1" in
	'' | *[!0-9]*) return 1 ;;
	esac
}

valid_release() {
	tag=$1
	case "$tag" in
	v*.*.*-beta.*)
		base=${tag%-beta.*}
		beta=${tag#*-beta.}
		digits_only "$beta" || return 1
		;;
	v*.*.*)
		base=$tag
		;;
	*) return 1 ;;
	esac
	body=${base#v}
	major=${body%%.*}
	rest=${body#*.}
	minor=${rest%%.*}
	patch=${rest#*.}
	[ "$rest" != "$body" ] && [ "$patch" != "$rest" ] || return 1
	digits_only "$major" && digits_only "$minor" && digits_only "$patch"
}

valid_project() {
	case "$1" in
	'' | *[!a-z0-9_-]*) return 1 ;;
	esac
	case "$1" in
	[a-z0-9]*) [ "${#1}" -le 63 ] ;;
	*) return 1 ;;
	esac
}

[ "$#" -le 1 ] || error '只接受一个可选的 Release 标签参数，例如 v1.4.0。'
if [ "$#" -eq 1 ]; then
	release=$1
fi
valid_release "$release" || error "无效的 Release 标签：$release（格式应为 vX.Y.Z 或 vX.Y.Z-beta.N）。"
[ -z "${XYMEDIA_SKIP_SIGNATURE_VERIFY:-}" ] || error 'XYMEDIA_SKIP_SIGNATURE_VERIFY 已废弃且不再支持；请移除该变量。'

command -v curl >/dev/null 2>&1 || error '安装器需要 curl。'
command -v mktemp >/dev/null 2>&1 || error '安装器需要 mktemp。'

validate_path_text() {
	path=$1
	if LC_ALL=C printf '%s' "$path" | LC_ALL=C grep -q '[[:cntrl:]]'; then
		error '安装目录不能包含 ASCII 控制字符。'
	fi
case "$path" in
	/*) ;;
	*) error '安装目录必须是绝对路径。' ;;
esac
[ "$path" != / ] || error '不允许使用根目录作为安装目录。'
}

select_utf8_locale() {
	path=$1
	if ! LC_ALL=C printf '%s' "$path" | LC_ALL=C grep -q '[^ -~]'; then
		selected_locale=
		return 0
	fi
	selected_locale=
	current_locale=${LC_ALL:-${LANG:-}}
	if [ -n "$current_locale" ] && LC_ALL="$current_locale" locale charmap 2>/dev/null | LC_ALL=C grep -qi 'UTF-8'; then
		selected_locale=$current_locale
	elif LC_ALL=C.UTF-8 locale charmap 2>/dev/null | LC_ALL=C grep -qi 'UTF-8'; then
		selected_locale=C.UTF-8
	elif LC_ALL=en_US.UTF-8 locale charmap 2>/dev/null | LC_ALL=C grep -qi 'UTF-8'; then
		selected_locale=en_US.UTF-8
	else
		while IFS= read -r candidate; do
			if [ -n "$candidate" ] && LC_ALL="$candidate" locale charmap 2>/dev/null | LC_ALL=C grep -qi 'UTF-8'; then
				selected_locale=$candidate
				break
			fi
		done <<EOF
$(LC_ALL=C locale -a 2>/dev/null)
EOF
	fi
	[ -n "$selected_locale" ] || error '系统缺少 UTF-8 locale，无法安全处理中文路径。'
}

tty=${XYMEDIA_TEST_TTY:-/dev/tty}
if [ -n "${XYMEDIA_INSTALL_DIR:-}" ]; then
	install_dir=$XYMEDIA_INSTALL_DIR
	validate_path_text "$XYMEDIA_INSTALL_DIR"
	select_utf8_locale "$XYMEDIA_INSTALL_DIR"
fi
menu_default=/opt/xymedia
if current_dir=$(pwd -P 2>/dev/null) && [ "$current_dir" != / ]; then
	menu_default=$current_dir
fi

menu_print() { printf '%s\n' "$1" >&4; }
status_print() {
	if [ "$interactive" -eq 1 ]; then
		printf '%s\n' "$1" >&4
	else
		printf '%s\n' "$1" >&2
	fi
}

configure_download_url() {
	raw_url=$1
	proxy=${XYMEDIA_DOWNLOAD_PROXY-https://gh-proxy.org/}
	download_mode=直连
	download_url=$raw_url
	if [ -n "$proxy" ]; then
		while [ "${proxy%/}" != "$proxy" ]; do proxy=${proxy%/}; done
		case "$proxy" in
		https://*) ;;
		*) error '生产环境 XYMEDIA_DOWNLOAD_PROXY 必须使用 HTTPS。' ;;
		esac
		download_url="$proxy/$raw_url"
		download_mode=代理
	fi
}

download_public_script() {
	label=$1
	raw_url=$2
	destination=$3
	configure_download_url "$raw_url"
	status_print "正在下载$label（使用${download_mode}）..."
	if [ "$interactive" -eq 1 ]; then
		curl --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 --retry 2 --retry-delay 1 --progress-bar -fsSL "$download_url" -o "$destination" 2>&4
	else
		curl --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 --retry 2 --retry-delay 1 -fsSL "$download_url" -o "$destination"
	fi
}

updater_tmp=
migration_tmp=
reset_tmp=
bootstrap_tmp=
cleanup_temps() {
	[ -z "$updater_tmp" ] || rm -f "$updater_tmp"
	[ -z "$migration_tmp" ] || rm -f "$migration_tmp"
	[ -z "$reset_tmp" ] || rm -f "$reset_tmp"
	[ -z "$bootstrap_tmp" ] || rm -f "$bootstrap_tmp"
}
trap cleanup_temps 0 HUP INT TERM

run_component_updater() {
	component=$1
	install_dir=$2
	updater_tmp=$(mktemp "${TMPDIR:-/tmp}/xymedia-component-updater.XXXXXX") || error '无法创建组件更新临时文件。'
	if ! download_public_script '组件更新器' "$component_updater_url" "$updater_tmp"; then
		error "无法下载组件更新器（使用${download_mode}，目标：$download_url）。请设置 XYMEDIA_DOWNLOAD_PROXY='' 可直连重试。"
	fi
	sh "$updater_tmp" --install-dir "$install_dir" --component "$component" --dry-run >&4 2>&4
	menu_print '验证完成。实际更新会停止并重启应用容器，是否继续？[y/N]：'
	if IFS= read -r answer <&3 && case "$answer" in y|Y) true;; *) false;; esac; then
		sh "$updater_tmp" --install-dir "$install_dir" --component "$component" --yes >&4 2>&4
	else
		menu_print '已取消实际更新。'
	fi
}

component_menu() {
	while :; do
		menu_print '更新 Title/TMM 组件'
		menu_print '1) 更新 Title'
		menu_print '2) 更新 TMM'
		menu_print '3) 更新全部'
		menu_print '4) 返回上一级'
		menu_print '请选择 [4]：'
		IFS= read -r choice <&3 || choice=
		case "$choice" in
		'') return 0;;
		1) component=title;;
		2) component=tmm;;
		3) component=all;;
		4) return 0;;
		*) menu_print '请输入 1、2、3 或 4。'; continue;;
		esac
		menu_print "请输入 XyMediaVault 安装目录 [$menu_default]（留空使用当前目录）："
		IFS= read -r install_dir <&3 || install_dir=
		[ -n "$install_dir" ] || install_dir=$menu_default
		menu_print '预检模式不会改变 Docker 状态，开始验证组件更新。'
		run_component_updater "$component" "$install_dir"
		return $?
	done
}

run_storage_migration() {
	install_dir=$1
	migration_tmp=$(mktemp "${TMPDIR:-/tmp}/xymedia-storage-migration.XXXXXX") || error '无法创建组件迁移临时文件。'
	if ! download_public_script '组件存储迁移脚本' "$migration_url" "$migration_tmp"; then
		error "无法下载组件存储迁移脚本（使用${download_mode}，目标：$download_url）。请设置 XYMEDIA_DOWNLOAD_PROXY='' 可直连重试。"
	fi
	menu_print '预检模式不会改变 Docker 状态，开始验证组件存储迁移。'
	if ! sh "$migration_tmp" --install-dir "$install_dir" --dry-run >&4 2>&4; then
		printf '%s\n' '组件存储迁移预检失败，未执行实际迁移。' >&2
		return 1
	fi
	menu_print '预检完成。实际迁移会复制组件、修改 compose.yaml、重建应用，可能中断服务。是否继续？[y/N]：'
	if IFS= read -r answer <&3 && case "$answer" in y|Y) true;; *) false;; esac; then
		sh "$migration_tmp" --install-dir "$install_dir" --yes >&4 2>&4
	else
		menu_print '已取消组件存储迁移。'
	fi
}

run_fresh_reset() {
	install_dir=$1
	project=$2
	validate_path_text "$install_dir"
	select_utf8_locale "$install_dir"
	reset_tmp=$(mktemp "${TMPDIR:-/tmp}/xymedia-reset-script.XXXXXX") || error '无法创建重置临时文件。'
	if ! download_public_script '全新重置脚本' "$reset_url" "$reset_tmp"; then
		error "无法下载全新重置脚本（使用${download_mode}，目标：$download_url）。请设置 XYMEDIA_DOWNLOAD_PROXY='' 可直连重试。"
	fi
	menu_print '开始执行全新重置。请按重置脚本提示完成两次确认。'
	if ! sh "$reset_tmp" --install-dir "$install_dir" --project "$project" >&4 2>&4; then
		menu_print '全新重置未成功，未启动全新安装。'
		return 1
	fi
	menu_print 'Docker 数据重置成功，开始启动 v1.4.0 全新安装。'
	release=$default_release
}

	if [ "$#" -eq 0 ] && [ "${XYMEDIA_RELEASE+x}" != x ] && [ "${XYMEDIA_COMMAND+x}" != x ] && [ -r "$tty" ] && [ -w "$tty" ] && exec 3<"$tty" 2>/dev/null && exec 4>>"$tty" 2>/dev/null; then
		interactive=1
		if command -v clear >/dev/null 2>&1 && { [ "${XYMEDIA_TEST_TTY+x}" != x ] || [ "${XYMEDIA_TEST_NO_CLEAR:-0}" != 1 ]; }; then
			clear >&4 2>/dev/null || true
		fi
	while :; do
		menu_print 'XyMediaVault'
		menu_print '1) 安装或升级应用'
		menu_print '2) 更新 Title/TMM 组件'
		menu_print '3) 仅生成 Compose 配置（不创建容器）'
		menu_print '4) 迁移组件存储到宿主机目录'
		menu_print '5) 全新重置安装（永久删除此 Compose 项目的 Docker 数据）'
		menu_print '6) 退出'
		menu_print '请选择 [1]：'
		IFS= read -r choice <&3 || choice=
		case "$choice" in
		1)
			menu_print "请输入 XyMediaVault 安装目录 [$menu_default]（留空使用当前目录）："
			IFS= read -r install_dir <&3 || install_dir=
			[ -n "$install_dir" ] || install_dir=$menu_default
			status_print "[0/2] 已确认安装目录：$install_dir"
			validate_path_text "$install_dir"
			select_utf8_locale "$install_dir"
			menu_install=1
			break
			;;
		'') :;;
		2) component_menu; exit $?;;
		3)
			compose_only=1
			menu_print "请输入 XyMediaVault 安装目录 [$menu_default]（留空使用当前目录）："
			IFS= read -r install_dir <&3 || install_dir=
			[ -n "$install_dir" ] || install_dir=$menu_default
			status_print "[0/2] 已确认安装目录：$install_dir"
			validate_path_text "$install_dir"
			select_utf8_locale "$install_dir"
			break
			;;
		4)
			menu_print "请输入 XyMediaVault 安装目录 [$menu_default]（留空使用当前目录）："
			IFS= read -r install_dir <&3 || install_dir=
			[ -n "$install_dir" ] || install_dir=$menu_default
			status_print "[0/2] 已确认安装目录：$install_dir"
			run_storage_migration "$install_dir"
			exit $?
			;;
		5)
			menu_print "请输入 XyMediaVault 安装目录 [$menu_default]（留空使用当前目录）："
			IFS= read -r install_dir <&3 || install_dir=
			[ -n "$install_dir" ] || install_dir=$menu_default
			status_print "[0/2] 已确认安装目录：$install_dir"
			menu_print '请输入 Compose 项目名 [xymedia]（留空使用默认值）：'
			IFS= read -r project <&3 || project=
			[ -n "$project" ] || project=xymedia
			if ! valid_project "$project"; then
				error 'Compose 项目名格式无效。请输入 1-63 位小写字母、数字、下划线或连字符，且必须以小写字母或数字开头。'
			fi
			status_print "[0/2] 已确认 Compose 项目名：$project"
			run_fresh_reset "$install_dir" "$project" || exit $?
			menu_install=1
			break
			;;
		6) menu_print '已退出。'; exit 0;;
		*) menu_print '请输入 1、2、3、4、5 或 6。'; continue;;
		esac
	done
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/xymedia-bootstrap.XXXXXX") || error '无法创建临时文件。'
bootstrap_tmp=$tmp

asset="https://github.com/iceqi/xymediavault/releases/download/$release/bootstrap.sh"
configure_download_url "$asset"
asset=$download_url

if [ "$interactive" -eq 1 ] && [ "${menu_install:-0}" -eq 1 ]; then
	status_print "[1/2] 正在下载 $release 安装引导脚本..."
	if ! curl --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 --retry 2 --retry-delay 1 --progress-bar -fsSL "$asset" -o "$tmp" 2>&4; then
		error "无法下载 $release Release bootstrap（使用${download_mode}，目标：$asset）。请设置 XYMEDIA_DOWNLOAD_PROXY='' 可直连重试。"
	fi
	status_print "[2/2] 正在启动 $release 安装器；该 Release bootstrap 将继续校验并下载安装器。"
else
	status_print "正在下载 $release 安装引导脚本（使用${download_mode}）。"
	if ! curl --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 180 --retry 2 --retry-delay 1 -fsSL "$asset" -o "$tmp"; then
		error "无法下载 $release Release bootstrap（使用${download_mode}，目标：$asset）。请设置 XYMEDIA_DOWNLOAD_PROXY='' 可直连重试。"
	fi
fi
bootstrap_env=${selected_locale:-}
if [ "${compose_only:-0}" -eq 1 ]; then
	if [ -n "${bootstrap_env:-}" ]; then
		env LC_ALL="$selected_locale" LANG="$selected_locale" XYMEDIA_COMMAND=compose-only XYMEDIA_INSTALL_DIR="$install_dir" sh "$tmp" "$release"
	else
		if [ "${menu_install:-0}" -eq 1 ]; then XYMEDIA_COMMAND=compose-only XYMEDIA_INSTALL_DIR="$install_dir" sh "$tmp" "$release"; else XYMEDIA_COMMAND=compose-only sh "$tmp" "$release"; fi
	fi
else
	if [ -n "${bootstrap_env:-}" ]; then
		if [ "${menu_install:-0}" -eq 1 ]; then env LC_ALL="$selected_locale" LANG="$selected_locale" XYMEDIA_COMMAND=install XYMEDIA_INSTALL_DIR="$install_dir" sh "$tmp" "$release"; else env LC_ALL="$selected_locale" LANG="$selected_locale" sh "$tmp" "$release"; fi
	else
		if [ "${menu_install:-0}" -eq 1 ]; then XYMEDIA_COMMAND=install XYMEDIA_INSTALL_DIR="$install_dir" sh "$tmp" "$release"; else sh "$tmp" "$release"; fi
	fi
fi
