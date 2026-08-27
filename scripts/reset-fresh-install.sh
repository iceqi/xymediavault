#!/usr/bin/env sh
set -eu
umask 077

error() { printf '%s\n' "[xymedia] 错误：$1" >&2; exit 2; }
install_dir=
tty=${XYMEDIA_TEST_TTY:-/dev/tty}
if [ "$#" -ne 2 ] || [ "$1" != --install-dir ]; then
	error '用法：reset-fresh-install.sh --install-dir DIR'
fi
install_dir=$2
case "$install_dir" in /*) ;; *) error '安装目录必须是绝对路径。';; esac
[ "$install_dir" != / ] || error '不允许使用根目录作为安装目录。'
if [ ! -d "$install_dir" ] || [ -L "$install_dir" ]; then
	error '安装目录不存在或是符号链接。'
fi
canonical=$(cd -- "$install_dir" && pwd -P)
[ "$canonical" != / ] || error '不允许使用根目录作为安装目录。'
if [ ! -f "$install_dir/.env" ] || [ -L "$install_dir/.env" ]; then
	error '缺少安全的 .env 文件。'
fi
if [ ! -f "$install_dir/compose.yaml" ] || [ -L "$install_dir/compose.yaml" ]; then
	error '缺少安全的 compose.yaml 文件。'
fi
if LC_ALL=C printf '%s' "$install_dir" | LC_ALL=C grep -q '[[:cntrl:]]'; then error '安装目录不能包含 ASCII 控制字符。'; fi

project=$(awk '$0 ~ /^COMPOSE_PROJECT_NAME=/ { count++; value=substr($0, length("COMPOSE_PROJECT_NAME=") + 1) } END { if (count == 1) print value; else exit 1 }' "$install_dir/.env") || error '.env 中 COMPOSE_PROJECT_NAME 必须恰好出现一次。'
if ! LC_ALL=C printf '%s\n' "$project" | LC_ALL=C grep -Eq '^[a-z0-9][a-z0-9_-]{0,62}$'; then
	error 'COMPOSE_PROJECT_NAME 格式无效。'
fi
command -v docker >/dev/null 2>&1 || error '重置需要 Docker。'
if [ ! -r "$tty" ] || [ ! -w "$tty" ]; then
	error '重置必须在可读写的交互式终端中执行。'
fi
# FD3 receives confirmations; FD4 keeps prompts and progress on the TTY.
# shellcheck disable=SC2094
exec 3<"$tty" 4>>"$tty"
tab=$(printf '\t')

list_resources() {
	resources=$(mktemp "${TMPDIR:-/tmp}/xymedia-reset.XXXXXX") || error '无法创建重置清单。'
	trap 'rm -f "$resources"' 0 HUP INT TERM
# Keep each Docker listing command auditable and append its stable records.
# shellcheck disable=SC2129
	docker ps -a --filter "label=com.docker.compose.project=$project" --format '{{.ID}}\t{{.Names}}\tcontainer\t{{.Status}}' >>"$resources"
	docker volume ls --filter "label=com.docker.compose.project=$project" --format '{{.ID}}\t{{.Name}}\tvolume\t-' >>"$resources"
	docker network ls --filter "label=com.docker.compose.project=$project" --format '{{.ID}}\t{{.Name}}\tnetwork\t-' >>"$resources"
	sort -k3,3 -k1,1 "$resources" -o "$resources"
}
menu_print() { printf '%s\n' "$1" >&4; }
list_resources
menu_print "将清理 Compose 项目 $project 的以下 Docker 资源（仅精确标签匹配）："
if [ -s "$resources" ]; then cat "$resources" >&4; else menu_print '（没有发现资源）'; fi
menu_print "请输入 RESET $project 以继续："
IFS= read -r answer <&3 || answer=
[ "$answer" = "RESET $project" ] || { menu_print '已取消重置。'; exit 0; }
menu_print '该操作将永久删除列出的 Docker 数据。确认继续？[y/N]：'
IFS= read -r answer <&3 || answer=
case "$answer" in y|Y) ;; *) menu_print '已取消重置。'; exit 0;; esac

while IFS="$tab" read -r id name type _status; do
	[ -n "$id" ] || continue
	case "$type" in
	container) label=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$id");;
	volume|network) label=$(docker inspect --format '{{index .Labels "com.docker.compose.project"}}' "$id");;
	esac
	[ "$label" = "$project" ] || error "资源标签已变化，停止重置：$name"
	case "$type" in
	container) docker stop "$id" || error "停止容器失败：$name";;
	esac
	case "$type" in
	container) label=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$id");;
	volume|network) label=$(docker inspect --format '{{index .Labels "com.docker.compose.project"}}' "$id");;
	esac
	[ "$label" = "$project" ] || error "资源标签已变化，停止重置：$name"
	case "$type" in
	container) docker rm "$id" || error "删除容器失败：$name";;
	volume) docker volume rm "$id" || error "删除卷失败：$name";;
	network) docker network rm "$id" || error "删除网络失败：$name";;
	esac
done <"$resources"

timestamp=$(date +%Y%m%d-%H%M%S) || error '无法生成备份时间戳。'
backup="$install_dir/.xymedia-reset-backups/$timestamp"
mkdir -p "$backup"
chmod 700 "$install_dir/.xymedia-reset-backups" "$backup"
for item in .env compose.yaml compose.fuse.yaml config.yaml verify-release.sh releases secrets; do
	if [ -e "$install_dir/$item" ] && [ ! -L "$install_dir/$item" ]; then mv "$install_dir/$item" "$backup/$item" || error "备份文件失败：$item"; fi
done
menu_print "Docker 资源已删除。受控文件已备份到：$backup"
menu_print 'components、media、xiaoya 及其他宿主机数据未删除。'
