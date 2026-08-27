#!/usr/bin/env sh
set -eu

default_release=v1.4.0
release=${XYMEDIA_RELEASE:-$default_release}
component_updater_url='https://raw.githubusercontent.com/iceqi/xymediavault/21e99c95df0c800079fff327c5fcf78b05734612/scripts/update-components.sh'
migration_url='https://raw.githubusercontent.com/iceqi/xymediavault/9fa0ed12a8547895f44ecea036bf5558053798c2/scripts/migrate-components-storage.sh'

error() {
	printf '%s\n' "[xymedia] 错误：$1" >&2
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

[ "$#" -le 1 ] || error '只接受一个可选的 Release 标签参数，例如 v1.4.0。'
if [ "$#" -eq 1 ]; then
	release=$1
fi
valid_release "$release" || error "无效的 Release 标签：$release（格式应为 vX.Y.Z 或 vX.Y.Z-beta.N）。"
[ -z "${XYMEDIA_SKIP_SIGNATURE_VERIFY:-}" ] || error 'XYMEDIA_SKIP_SIGNATURE_VERIFY 已废弃且不再支持；请移除该变量。'

command -v curl >/dev/null 2>&1 || error '安装器需要 curl。'
command -v mktemp >/dev/null 2>&1 || error '安装器需要 mktemp。'

tty=${XYMEDIA_TEST_TTY:-/dev/tty}

run_component_updater() {
	component=$1
	install_dir=$2
	updater_tmp=$(mktemp "${TMPDIR:-/tmp}/xymedia-component-updater.XXXXXX") || error '无法创建组件更新临时文件。'
	# shellcheck disable=SC2317
	cleanup_updater() { rm -f "$updater_tmp"; }
	trap cleanup_updater 0 HUP INT TERM
	if ! curl --proto '=https' --tlsv1.2 -fsSL "$component_updater_url" -o "$updater_tmp"; then
		error '无法下载组件更新器，请稍后重试。'
	fi
	sh "$updater_tmp" --install-dir "$install_dir" --component "$component" --dry-run
	printf '%s\n' '验证完成。实际更新会停止并重启应用容器，是否继续？[y/N]：' >&2
	if IFS= read -r answer <&3 && case "$answer" in y|Y) true;; *) false;; esac; then
		sh "$updater_tmp" --install-dir "$install_dir" --component "$component" --yes
	else
		printf '%s\n' '已取消实际更新。'
	fi
}

component_menu() {
	while :; do
		printf '%s\n' '更新 Title/TMM 组件' '1) 更新 Title' '2) 更新 TMM' '3) 更新全部' '4) 返回上一级' '请选择 [4]：'
		IFS= read -r choice <&3 || choice=
		case "$choice" in
		'') return 0;;
		1) component=title;;
		2) component=tmm;;
		3) component=all;;
		4) return 0;;
		*) printf '%s\n' '请输入 1、2、3 或 4。' >&2; continue;;
		esac
		printf '%s\n' '请输入 XyMediaVault 安装目录 [/opt/xymedia]：'
		IFS= read -r install_dir <&3 || install_dir=
		[ -n "$install_dir" ] || install_dir=/opt/xymedia
		printf '%s\n' '预检模式不会改变 Docker 状态，开始验证组件更新。'
		run_component_updater "$component" "$install_dir"
		return $?
	done
}

run_storage_migration() {
	install_dir=$1
	migration_tmp=$(mktemp "${TMPDIR:-/tmp}/xymedia-storage-migration.XXXXXX") || error '无法创建组件迁移临时文件。'
	# shellcheck disable=SC2317
	cleanup_migration() { rm -f "$migration_tmp"; }
	trap cleanup_migration 0 HUP INT TERM
	if ! curl --proto '=https' --tlsv1.2 -fsSL "$migration_url" -o "$migration_tmp"; then
		error '无法下载组件存储迁移脚本，请稍后重试。'
	fi
	printf '%s\n' '预检模式不会改变 Docker 状态，开始验证组件存储迁移。'
	if ! sh "$migration_tmp" --install-dir "$install_dir" --dry-run; then
		printf '%s\n' '组件存储迁移预检失败，未执行实际迁移。' >&2
		return 1
	fi
	printf '%s\n' '预检完成。实际迁移会复制组件、修改 compose.yaml、重建应用，可能中断服务。是否继续？[y/N]：' >&2
	if IFS= read -r answer <&3 && case "$answer" in y|Y) true;; *) false;; esac; then
		sh "$migration_tmp" --install-dir "$install_dir" --yes
	else
		printf '%s\n' '已取消组件存储迁移。'
	fi
}

if [ "$#" -eq 0 ] && [ "${XYMEDIA_RELEASE+x}" != x ] && [ "${XYMEDIA_COMMAND+x}" != x ] && [ -r "$tty" ] && [ -w "$tty" ] && exec 3<"$tty" 2>/dev/null; then
	while :; do
		printf '%s\n' 'XyMediaVault' '1) 安装或升级应用' '2) 更新 Title/TMM 组件' '3) 仅生成 Compose 配置（不创建容器）' '4) 迁移组件存储到宿主机目录' '5) 退出' '请选择 [1]：'
		IFS= read -r choice <&3 || choice=
		case "$choice" in
		1) :;;
		'') :;;
		2) component_menu; exit $?;;
		3) compose_only=1; break;;
		4)
			printf '%s\n' '请输入 XyMediaVault 安装目录 [/opt/xymedia]：'
			IFS= read -r install_dir <&3 || install_dir=
			[ -n "$install_dir" ] || install_dir=/opt/xymedia
			run_storage_migration "$install_dir"
			exit $?
			;;
		5) printf '%s\n' '已退出。'; exit 0;;
		*) printf '%s\n' '请输入 1、2、3、4 或 5。' >&2; continue;;
		esac
	done
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/xymedia-bootstrap.XXXXXX") || error '无法创建临时文件。'
cleanup() { rm -f "$tmp"; }
trap cleanup 0 HUP INT TERM

asset="https://github.com/iceqi/xymediavault/releases/download/$release/bootstrap.sh"
if [ -n "${XYMEDIA_DOWNLOAD_PROXY:-}" ]; then
	proxy=${XYMEDIA_DOWNLOAD_PROXY%/}
	case "$proxy" in
	https://*) ;;
	*) error '生产环境 XYMEDIA_DOWNLOAD_PROXY 必须使用 HTTPS。' ;;
	esac
	asset="$proxy/$asset"
fi

curl --proto '=https' --tlsv1.2 -fsSL "$asset" -o "$tmp" || error "无法下载 $release Release bootstrap。"
if [ "${compose_only:-0}" -eq 1 ]; then
	XYMEDIA_COMMAND=compose-only sh "$tmp" "$release"
else
	sh "$tmp" "$release"
fi
