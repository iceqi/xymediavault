#!/usr/bin/env sh
# shellcheck disable=SC2317
set -eu
umask 077

die() { printf '%s\n' "[xymedia] 错误：$1" >&2; exit 2; }
usage() { printf '%s\n' '用法：migrate-components-storage.sh --install-dir ABS_DIR [--dry-run] [--yes]' >&2; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "需要 $1。"; }
progress() { if [ -t 2 ]; then printf '\r[%s/%s] %s' "$1" "$2" "$3" >&2; else printf '[%s/%s] %s\n' "$1" "$2" "$3" >&2; fi; }
progress_done() { if [ -t 2 ]; then printf '\n' >&2; fi; }

install_dir=; dry_run=false; yes=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-dir) [ "$#" -gt 1 ] || usage; install_dir=$2; shift 2;;
    --dry-run) dry_run=true; shift;;
    --yes) yes=true; shift;;
    -h|--help) usage;; *) usage;;
  esac
done
[ -n "$install_dir" ] || usage
case "$install_dir" in /*) ;; *) die '--install-dir 必须是绝对路径。';; esac
[ -d "$install_dir" ] || die '安装目录不存在。'
[ ! -L "$install_dir" ] || die '安装目录不能是符号链接。'
install_dir=$(cd "$install_dir" && pwd -P)
[ "$install_dir" != / ] || die '安装目录不能是根目录。'
env_file=$install_dir/.env; compose_file=$install_dir/compose.yaml
[ -f "$env_file" ] || die '找不到安装目录中的 .env。'
[ -f "$compose_file" ] || die '找不到安装目录中的 compose.yaml。'
[ ! -L "$env_file" ] || die '.env 不能是符号链接。'
[ ! -L "$compose_file" ] || die 'compose.yaml 不能是符号链接。'
need awk; need cmp; need date; need docker; need jq; need mktemp; need mkdir; need cp; need mv; need rm; need stat; need tar; need df; need seq; need sleep

app=xymedia-app; project=xymedia
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    XYMEDIA_APP_CONTAINER=*) app=${line#*=};;
    COMPOSE_PROJECT_NAME=*) project=${line#*=};;
  esac
done < "$env_file"
case "$app" in ''|*[!A-Za-z0-9_.-]*) die 'XYMEDIA_APP_CONTAINER 包含非法字符。';; esac
case "$project" in ''|*[!A-Za-z0-9_.-]*) die 'COMPOSE_PROJECT_NAME 包含非法字符。';; esac
target=$install_dir/components
tmp=$(mktemp -d "${TMPDIR:-/tmp}/xymedia-migrate.XXXXXX") || die '无法创建临时目录。'
cleanup() { rm -rf "$tmp"; }
trap cleanup 0 HUP INT TERM

app_json=$(docker inspect "$app") || die "找不到运行中的应用容器 $app。"
progress 1 9 '挂载与应用状态预检'
printf '%s' "$app_json" | jq -e '.[0].State.Running == true' >/dev/null || die "应用容器 $app 未运行。"
mount_json=$(printf '%s' "$app_json" | jq -c '[.[0].Mounts[] | select(.Destination=="/app/components")] | if length == 1 then .[0] else empty end')
[ -n "$mount_json" ] || die '/app/components mount 不存在或不唯一。'
mount_type=$(printf '%s' "$mount_json" | jq -r '.Type'); volume=
case "$mount_type" in
  volume)
    volume=$(printf '%s' "$mount_json" | jq -r '.Name // empty')
    case "$volume" in ''|*[!A-Za-z0-9_.-]*) die '拒绝 anonymous 或无效 named volume。';; esac
    labels=$(docker volume inspect "$volume") || die '无法检查组件 volume。'
    printf '%s' "$labels" | jq -e --arg p "$project" '.[0].Labels["com.docker.compose.project"] == $p and .[0].Labels["com.docker.compose.volume"] == "components"' >/dev/null || die '组件 volume 缺少精确的 Compose 管理标签。'
    ;;
  bind)
    source=$(printf '%s' "$mount_json" | jq -r '.Source // empty')
    [ "$source" = "$target" ] || die '现有 bind mount 指向外部路径，拒绝迁移。'
    count=$(awk '$0 == "      - \"${XYMEDIA_INSTALL_DIR}/components:/app/components\"" {n++} END {print n+0}' "$compose_file")
    [ "$count" -eq 1 ] || die '现有 canonical bind mount 未被 compose 精确管理。'
    printf '%s\n' '[xymedia] 阶段：存储检查完成，canonical bind 已迁移，无需修改。'
    exit 0
    ;;
  *) die '组件 mount 类型未知。';;
esac

if [ "$dry_run" = true ]; then
	progress 9 9 '预检完成：未修改文件或 Docker 状态'; progress_done
	printf '%s\n' '[xymedia] 阶段：预检完成；未修改文件、Docker 状态或组件目录。'
  exit 0
fi
[ "$yes" = true ] || {
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then die '没有可用 TTY，拒绝未确认的迁移。'; fi
  printf '%s' '将迁移组件存储并重启应用，继续？[y/N]：' >/dev/tty
  IFS= read -r answer </dev/tty || answer=
  case "$answer" in y|Y) ;; *) die '已取消迁移。';; esac
}
progress 2 9 '准备组件目录与剩余空间'
docker image inspect alpine:3.22 >/dev/null 2>&1 || die '需要本地已有 alpine:3.22，拒绝自动拉取。'

if [ -e "$target" ]; then
  [ -d "$target" ] || die 'components 目标不是目录。'
  [ ! -L "$target" ] || die 'components 目标不能是符号链接。'
  [ -z "$(ls -A "$target")" ] || die 'components 目标必须为空。'
else
  mkdir "$target"
fi
chmod 755 "$target"
free=$(df -Pk "$install_dir" | awk 'NR==2 {print $4}')
[ -n "$free" ] || die '无法检查安装目录剩余空间。'
progress 3 9 '复制并验证组件数据'
docker run --rm --mount "type=volume,src=$volume,dst=/components,readonly" --mount "type=bind,src=$target,dst=/target" --mount "type=bind,src=$tmp,dst=/stage" alpine:3.22 /bin/sh -c 'set -eu; test -r /components; test -w /target; used=$(du -sk /components | awk "NR==1 {print \$1}"); test "$used" -lt '"$free"'; tar -cpf /stage/components-source.tar -C /components .; tar -xpf /stage/components-source.tar -C /target; tar -cpf /tmp/source.signature -C /components .; tar -cpf /tmp/target.signature -C /target .; cmp /tmp/source.signature /tmp/target.signature' || die '阶段：源数据预检、复制、递归验证或空间检查失败，应用仍在运行。'
progress 4 9 '准备备份与迁移元数据'
backup_root=$install_dir/.xymedia-component-migrations
timestamp=$(date +%Y%m%d%H%M%S); backup=$backup_root/$timestamp
mkdir -p "$backup"; chmod 700 "$backup"
cp -p "$compose_file" "$backup/compose.yaml.pre-migration"; cp -p "$env_file" "$backup/.env.pre-migration"
mv "$tmp/components-source.tar" "$backup/components-source.tar"
printf '%s\n' '{"schema_version":1,"storage":"components","source":"managed-volume","status":"prepared"}' > "$backup/migration.json"

candidate=$tmp/compose.yaml
cp -p "$compose_file" "$candidate"
count=$(awk '$0 == "      - components:/app/components" {n++} END {print n+0}' "$candidate")
[ "$count" -eq 1 ] || die '阶段：compose 未找到唯一 v1.4.0 named volume 行，未停止应用。'
awk '{if ($0 == "      - components:/app/components") print "      - \"${XYMEDIA_INSTALL_DIR}/components:/app/components\""; else print}' "$candidate" > "$tmp/compose.new"
mv "$tmp/compose.new" "$candidate"
progress 5 9 '校验候选 compose 配置'
XYMEDIA_INSTALL_DIR="$install_dir" docker compose --project-directory "$install_dir" --env-file "$env_file" -f "$candidate" config -q || die '阶段：候选 compose 校验失败，未停止应用。'
cp -p "$candidate" "$tmp/compose.final"
mv "$tmp/compose.final" "$compose_file"
changed=false; stopped=false
rollback() {
  [ "${stopped:-false}" = true ] || return 0
  if [ "${changed:-false}" = true ]; then cp -p "$backup/compose.yaml.pre-migration" "$compose_file"; cp -p "$backup/.env.pre-migration" "$env_file"; fi
  docker compose --project-directory "$install_dir" --env-file "$env_file" -f "$compose_file" up -d --no-deps app >/dev/null 2>&1 || true
}
on_exit() {
  status=$?
  trap - 0 HUP INT TERM
  rollback
  cleanup
  exit "$status"
}
trap on_exit 0 HUP INT TERM
changed=true
stopped=true
progress 6 9 '停止应用并切换 compose 配置'
docker stop "$app" >/dev/null || die '阶段：停止应用失败。'
docker compose --project-directory "$install_dir" --env-file "$env_file" -f "$compose_file" up -d --no-deps app || die '阶段：切换应用失败，已恢复配置。'
progress 7 9 '验证 canonical bind mount'
new_json=$(docker inspect "$app") || die '阶段：无法检查切换后的应用。'
printf '%s' "$new_json" | jq -e --arg s "$target" '.[0].Mounts[] | select(.Destination=="/app/components" and .Type=="bind" and .Source==$s)' >/dev/null || die '阶段：未确认 canonical bind mount，已恢复配置。'
for i in $(seq 1 180); do : "$i"; status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' "$app") || status=unknown; [ "$status" = healthy ] && { progress 8 9 '应用健康检查通过'; progress_done; printf '%s\n' '[xymedia] 阶段：迁移完成，应用健康状态为 healthy。'; trap cleanup 0; trap - HUP INT TERM; exit 0; }; [ $((i % 5)) -eq 0 ] && progress 8 9 "等待应用健康检查（第 $i 次）"; sleep 1; done
progress 9 9 '健康检查超时，开始回滚'
die '阶段：新应用健康检查超时，已恢复原 named volume 配置。'
