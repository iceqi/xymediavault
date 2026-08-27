#!/usr/bin/env sh
set -eu

default_release=v1.4.0
release=${XYMEDIA_RELEASE:-$default_release}

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
sh "$tmp" "$release"
