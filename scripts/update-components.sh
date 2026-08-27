#!/usr/bin/env sh
set -eu

# The lock is deliberately data, rather than a release lookup. Changes to it
# should be reviewed together with this script.
LOCK_JSON='{
  "title": {"repository":"iceqi/xymedia-title","tag":"component-sha-007ed892afaf","release_version":"sha-007ed892afaf","assets":{"linux/amd64":{"name":"xymedia-title-sha-007ed892afaf-linux-amd64.tar.zst","platform":"linux/amd64","sha256":"ea719e6a86907b44b79ab0dc5fef43e83adb89706bf50973d4b3353b168f0534"},"linux/arm64":{"name":"xymedia-title-sha-007ed892afaf-linux-arm64.tar.zst","platform":"linux/arm64","sha256":"e7ebd6de5be7a62f6abf4c8bbed2ac18fce9ed5e10ed7cc5fb2abb46bb53a0ba"}}},
  "tmm": {"repository":"iceqi/xymedia-tmm","tag":"component-sha-61e9e46df421","release_version":"sha-61e9e46df421","assets":{"linux/amd64":{"name":"xymedia-tmm-sha-61e9e46df421-linux-any.tar.zst","platform":"linux/any","sha256":"5012a1d228d481343507c19578c6cb9b3bf946319ea71058a7f808185a04c664"},"linux/arm64":{"name":"xymedia-tmm-sha-61e9e46df421-linux-any.tar.zst","platform":"linux/any","sha256":"5012a1d228d481343507c19578c6cb9b3bf946319ea71058a7f808185a04c664"}}}
}'

die() { printf '%s\n' "[xymedia] 错误：$1" >&2; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "需要 $1。"; }
usage() { printf '%s\n' '用法：update-components.sh --install-dir DIR --component title|tmm|all [--yes] [--dry-run] [--lock-file FILE]' >&2; exit 2; }

install_dir='' component='' dry_run=false yes=false lock_file=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-dir) [ "$#" -ge 2 ] || usage; install_dir=$2; shift 2;;
    --component) [ "$#" -ge 2 ] || usage; component=$2; shift 2;;
    --yes) yes=true; shift;;
    --dry-run) dry_run=true; shift;;
    --lock-file) [ "$#" -ge 2 ] || usage; lock_file=$2; shift 2;;
    -h|--help) usage;; *) usage;;
  esac
done
if [ -z "$install_dir" ] || [ ! -d "$install_dir" ]; then die '必须提供存在的 --install-dir。'; fi
case "$component" in title|tmm) ;; all) component='title tmm';; *) die '组件必须是 title、tmm 或 all。';; esac
[ -f "$install_dir/.env" ] || die "找不到 $install_dir/.env。"

need curl; need jq; need zstd; need tar; need sha256sum; need awk; need grep; need sort; need mktemp
if [ "$dry_run" = false ]; then need docker; fi
case "$install_dir" in /*) ;; *) die '--install-dir 必须是绝对路径。';; esac

lock=$LOCK_JSON
if [ -n "$lock_file" ]; then
  case "$lock_file" in /*) ;; *) die '--lock-file 必须是绝对路径。';; esac
  lock=$(cat "$lock_file") || die '无法读取 lock 文件。'
fi
lock_query='type == "object" and (keys|sort == ["title","tmm"]) and all(.[]; (.repository|type=="string" and test("^[^/]+/[^/]+$")) and (.tag|type=="string" and test("^component-sha-[0-9a-f]{12}$")) and (.release_version|type=="string" and test("^sha-[0-9a-f]{12}$")) and (.assets|type=="object") and all(.assets[]; (.name|type=="string" and test("^[A-Za-z0-9._-]+\\.tar\\.zst$")) and (.platform|type=="string" and test("^linux/(amd64|arm64|any)$")) and (.sha256|type=="string" and test("^[0-9a-fA-F]{64}$"))))'
if ! printf '%s' "$lock" | jq -e "$lock_query" >/dev/null; then die 'lock 文件格式、tag、release_version、asset 或 checksum 无效。'; fi
token=${GH_TOKEN:-${GITHUB_TOKEN:-}}
if [ -z "$token" ]; then die '私有组件 Release 下载需要设置 GH_TOKEN 或 GITHUB_TOKEN。'; fi

# Parse only KEY=value lines, without evaluating .env as shell code.
app=xymedia-app
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    XYMEDIA_APP_CONTAINER=*) app=${line#*=};;
  esac
done < "$install_dir/.env"
case "$app" in ''|*[!A-Za-z0-9_.-]*) die 'XYMEDIA_APP_CONTAINER 包含非法字符。';; esac

tmp=$(mktemp -d "${TMPDIR:-/tmp}/xymedia-components.XXXXXX") || die '无法创建临时目录。'
lock_dir=$install_dir/.install.lock
lock_acquired=false
completed=false
changed=false
mutation_started=false
stop_attempted=false
app_was_running=false
timestamp=''
volume=''
# shellcheck disable=SC2317
cleanup() {
  rm -rf "$tmp"
  if [ "$lock_acquired" = true ]; then rmdir "$lock_dir" 2>/dev/null || true; fi
}
trap cleanup 0 HUP INT TERM
mkdir "$lock_dir" 2>/dev/null || die '另一个安装或组件更新正在进行。'
lock_acquired=true

platform=
if [ "$dry_run" = false ]; then
  app_json=$(docker inspect "$app") || die "找不到运行中的应用容器 $app。"
  printf '%s' "$app_json" | jq -e '.[0].State.Running == true' >/dev/null || die "应用容器 $app 未运行。"
  image=$(printf '%s' "$app_json" | jq -r '.[0].Image // empty')
  [ -n "$image" ] || die '应用容器没有 image ID。'
  arch=$(docker image inspect "$image" | jq -r '.[0].Architecture // empty')
  case "$arch" in amd64) platform=linux/amd64;; arm64|aarch64) platform=linux/arm64;; *) die "不支持的应用镜像架构：$arch。";; esac
  volume=$(printf '%s' "$app_json" | jq -r '.[0].Mounts[] | select(.Destination=="/app/components") | if .Type=="volume" and (.Name|type=="string") and (.Name|test("^[A-Za-z0-9][A-Za-z0-9_.-]*$")) then .Name else "INVALID" end' | head -n 1)
  if [ "$volume" = INVALID ] || [ -z "$volume" ]; then die '/app/components 必须是一个 named Docker volume。'; fi
  docker image inspect alpine:3.22 >/dev/null 2>&1 || die '需要本地已有 alpine:3.22，拒绝在维护窗口拉取镜像。'
else
  platform=${XYMEDIA_TEST_PLATFORM:-linux/amd64}
fi

for name in $component; do
  repo=$(printf '%s' "$lock" | jq -r --arg c "$name" '.[$c].repository')
  tag=$(printf '%s' "$lock" | jq -r --arg c "$name" '.[$c].tag')
  release_version=$(printf '%s' "$lock" | jq -r --arg c "$name" '.[$c].release_version')
  asset=$(printf '%s' "$lock" | jq -r --arg c "$name" --arg p "$platform" '.[$c].assets[$p].name // empty')
  archive_platform=$(printf '%s' "$lock" | jq -r --arg c "$name" --arg p "$platform" '.[$c].assets[$p].platform // empty')
  expected=$(printf '%s' "$lock" | jq -r --arg c "$name" --arg p "$platform" '.[$c].assets[$p].sha256 // empty')
  if [ -z "$asset" ] || [ -z "$expected" ] || [ -z "$archive_platform" ]; then die "lock 没有 $name/$platform 资产。"; fi
  archive=$tmp/$name.tar.zst; checksum=$tmp/$name.sha256
  api_url="https://api.github.com/repos/$repo/releases/tags/$tag"
  curl_auth() {
    curl --proto '=https' --tlsv1.2 -fsSL -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' "$@"
  }
  release_json=$tmp/$name-release.json
  curl_auth "$api_url" -o "$release_json" || die "无法查询 $name Release。"
  asset_id=$(jq -e -r --arg name "$asset" --arg tag "$tag" 'if .tag_name != $tag then error("release tag mismatch") else [.assets[]? | select(.name == $name)] as $matches | if ($matches|length) != 1 then error("asset count mismatch") elif (($matches[0].id|type) != "number" or ($matches[0].id|floor != $matches[0].id)) then error("asset id is not an integer") else $matches[0].id end end' "$release_json") || die "$name Release asset 缺失、重复或 ID 无效。"
  case "$asset_id" in ''|*[!0-9]*) die "$name Release asset ID 无效。";; esac
  checksum_asset="$asset.sha256"
  checksum_id=$(jq -e -r --arg name "$checksum_asset" --arg tag "$tag" 'if .tag_name != $tag then error("release tag mismatch") else [.assets[]? | select(.name == $name)] as $matches | if ($matches|length) != 1 then error("asset count mismatch") elif (($matches[0].id|type) != "number" or ($matches[0].id|floor != $matches[0].id)) then error("asset id is not an integer") else $matches[0].id end end' "$release_json") || die "$name checksum asset 缺失、重复或 ID 无效。"
  case "$checksum_id" in ''|*[!0-9]*) die "$name checksum asset ID 无效。";; esac
  curl_auth "https://api.github.com/repos/$repo/releases/assets/$asset_id" -H 'Accept: application/octet-stream' -o "$archive" || die "无法下载 $name 归档。"
  curl_auth "https://api.github.com/repos/$repo/releases/assets/$checksum_id" -H 'Accept: application/octet-stream' -o "$checksum" || die "无法下载 $name checksum。"
  checksum_value=$(awk 'NF {count++; value=$1} END {if (count != 1) exit 1; print value}' "$checksum") || die "$name checksum 文件无效。"
  printf '%s\n' "$checksum_value" | grep -Eq '^[0-9A-Fa-f]{64}$' || die "$name checksum 文件无效。"
  checksum_value=$(printf '%s' "$checksum_value" | tr 'A-F' 'a-f')
  [ "$checksum_value" = "$expected" ] || die "$name checksum 不匹配 lock。"
  printf '%s  %s\n' "$checksum_value" "$archive" | sha256sum -c - >/dev/null || die "$name 归档校验失败。"
  zstd -t "$archive" >/dev/null || die "$name 不是有效 zstd 归档。"
  manifest=$(zstd -dc "$archive" | tar -xOf - manifest.json 2>/dev/null) || die "$name 缺少 manifest.json。"
  if ! printf '%s' "$manifest" | jq -e --arg c "$name" --arg v "$release_version" --arg p "$archive_platform" '(.schema_version==1 and .component==$c and .release_version==$v and .platform==$p and (.files|type=="object"))' >/dev/null; then die "$name manifest 元数据不匹配。"; fi
  archive_files=$(zstd -dc "$archive" | tar -tf - | awk '$0 != "manifest.json" {print}' | sort)
  manifest_files=$(printf '%s' "$manifest" | jq -r '.files | keys[]' | sort)
  if [ "$archive_files" != "$manifest_files" ]; then die "$name manifest 文件列表与归档不一致。"; fi
  if ! zstd -dc "$archive" | tar -tf - | awk 'BEGIN{bad=0} /^\// || /(^|\/)\.\.\// || /(^|\/)\.$/ || /\\/ {bad=1} END{exit bad}'; then die "$name 归档包含不安全路径。"; fi
  if ! zstd -dc "$archive" | tar -tvf - | awk 'BEGIN{bad=0} {if (substr($0,1,1) != "-") bad=1} END{exit bad}'; then die "$name 归档包含非 regular 条目。"; fi
  if ! printf '%s' "$manifest" | jq -e 'all(.files | to_entries[]; (.key|type=="string" and startswith("payload/") and (contains("..")|not) and (contains("\\")|not)) and (.value|test("^[0-9a-fA-F]{64}$")))' >/dev/null; then die "$name manifest 文件列表无效。"; fi
  files=$(printf '%s' "$manifest" | jq -r '.files | keys[]')
  for file in $files; do
    payload_file=$tmp/payload
    zstd -dc "$archive" | tar -xOf - "$file" > "$payload_file" 2>/dev/null || die "$name 缺少 manifest 声明文件：$file。"
    actual=$(sha256sum "$payload_file" | awk '{print $1}')
    declared=$(printf '%s' "$manifest" | jq -r --arg f "$file" '.files[$f]')
    [ "$actual" = "$declared" ] || die "$name payload digest 不匹配：$file。"
  done
  printf '%s\n' "$name: $tag / $asset validated"
done

[ "$dry_run" = true ] && { printf '%s\n' 'dry-run: validation complete; no Docker state changed.'; exit 0; }
if [ "$yes" != true ]; then printf '%s\n' '未提供 --yes，安全退出；请先使用 --dry-run。' >&2; exit 1; fi

for name in $component; do cp "$tmp/$name.tar.zst" "$tmp/$name.stage"; done
docker run --rm -v "$volume:/components" -v "$tmp:/stage:ro" --entrypoint /bin/sh alpine:3.22 -c 'set -eu; test -w /components; for f in /stage/*.stage; do sha256sum "$f" >/dev/null; done' || die 'Docker helper 预检失败。'
# Install the recovery trap before the stop attempt. Every variable used by it
# is initialized above, so an interrupted stop cannot trigger set -u failures.
rollback() {
  # POSIX trap invokes this function indirectly after a failed mutation.
  # shellcheck disable=SC2317
  if [ "$completed" = true ]; then return 0; fi
  # shellcheck disable=SC2317
  if [ "$stop_attempted" = true ] && [ "$app_was_running" = true ]; then
    # shellcheck disable=SC2317
    docker stop "$app" >/dev/null 2>&1 || true
    marker_state='unknown'
    if [ -n "$timestamp" ] && [ -n "$volume" ]; then
      # The marker check is deliberately read-only. Any helper failure is
      # uncertainty, so restoration remains disabled.
      # shellcheck disable=SC2317
      if marker_state=$(docker run --rm -v "$volume:/components:ro" --entrypoint /bin/sh alpine:3.22 -c 'if test -f "/components/.xymedia-component-backups/'"$timestamp"'/mutation-started"; then printf marker-present; else printf marker-absent; fi'); then :; else marker_state='unknown'; fi
    fi
    # The durable marker, rather than host booleans, is the source of truth.
    # shellcheck disable=SC2317
    if [ "$marker_state" = marker-present ]; then
      if [ "$mutation_started" = false ] || [ "$changed" = false ]; then printf '%s\n' '[xymedia] 警告：volume marker 表明已开始替换，按 marker 执行恢复。' >&2; fi
      # shellcheck disable=SC2317
      docker run --rm -v "$volume:/components" --entrypoint /bin/sh alpine:3.22 -c 'set -eu; for n in '"$component"'; do if test -f "/components/.xymedia-component-backups/'"$timestamp"'/$n.prior"; then cp "/components/.xymedia-component-backups/'"$timestamp"'/$n.tar.zst" "/components/$n.tar.zst"; elif test -f "/components/.xymedia-component-backups/'"$timestamp"'/$n.absent"; then rm -f "/components/$n.tar.zst"; fi; done' || true
    elif [ "$marker_state" = unknown ]; then
      printf '%s\n' '[xymedia] 警告：无法检查 mutation marker，跳过组件恢复。' >&2
    fi
    # shellcheck disable=SC2317
    docker start "$app" >/dev/null 2>&1 || true
  fi
}
trap 'rollback; cleanup' 0 HUP INT TERM
stop_attempted=true
app_was_running=true
docker stop "$app" >/dev/null || die '无法停止应用容器。'
timestamp=$(date +%Y%m%d%H%M%S)
for name in $component; do cp "$tmp/$name.tar.zst" "$tmp/$name.stage"; done
mutation_started=true
changed=true
docker run --rm -v "$volume:/components" -v "$tmp:/stage:ro" --entrypoint /bin/sh alpine:3.22 -c 'set -eu; backup=/components/.xymedia-component-backups/'"$timestamp"'; mkdir -p "$backup"; for f in /stage/*.stage; do n=${f##*/}; n=${n%.stage}; if test -f "/components/$n.tar.zst"; then cp "/components/$n.tar.zst" "$backup/$n.tar.zst"; : > "$backup/$n.prior"; else : > "$backup/$n.absent"; fi; done; : > "$backup/mutation-started"; for f in /stage/*.stage; do n=${f##*/}; n=${n%.stage}; cp "$f" "/components/.$n.tar.zst.tmp"; mv "/components/.$n.tar.zst.tmp" "/components/$n.tar.zst"; done' || die '组件写入失败。'
docker start "$app" >/dev/null || die '无法启动应用容器，已尝试回滚。'
for i in $(seq 1 180); do
  : "$i"
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}' "$app") || status=unknown
  if [ "$status" = healthy ] || [ "$status" = running ]; then completed=true; trap cleanup 0; trap - HUP INT TERM; exit 0; fi
  sleep 1
done
die '应用健康检查未在 180 秒内通过。'
