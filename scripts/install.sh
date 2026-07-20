#!/usr/bin/env sh
set -eu

# XyMediaVault 一键部署脚本。
# 示例：
#   curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh -o install.sh
#   sh scripts/install.sh
# 所有部署参数都会在安装时逐项询问，环境变量只用于修改提示中的建议值。

prompt_value() {
  prompt_text="$1"
  suggested_value="$2"

  printf "%s（默认：%s，直接回车使用默认）: " "$prompt_text" "$suggested_value" >/dev/tty
  if ! IFS= read -r input_value </dev/tty; then
    input_value=""
  fi
  if [ -n "$input_value" ]; then
    printf "%s" "$input_value"
  else
    printf "%s" "$suggested_value"
  fi
}

prompt_bool() {
  prompt_text="$1"
  suggested_value="$2"

  while true; do
    if [ "$suggested_value" = "true" ]; then
      prompt_hint="Y/n"
      default_text="是"
    else
      prompt_hint="y/N"
      default_text="否"
    fi
    printf "%s（默认：%s，%s）: " "$prompt_text" "$default_text" "$prompt_hint" >/dev/tty
    if ! IFS= read -r input_value </dev/tty; then
      input_value=""
    fi
    case "$input_value" in
      "")
        printf "%s" "$suggested_value"
        return
        ;;
      y | Y | yes | YES | Yes)
        printf "true"
        return
        ;;
      n | N | no | NO | No)
        printf "false"
        return
        ;;
      *)
        echo "请输入 y 或 n。" >/dev/tty
        ;;
    esac
  done
}

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
  echo "当前环境没有可用的交互终端，请在终端中执行：sh install.sh" >&2
  exit 1
fi

echo "XyMediaVault 交互式安装/更新"
echo

START_DIR="$(pwd)"
INSTALL_DIR="$(prompt_value "安装目录" "${INSTALL_DIR:-$START_DIR}")"
case "$INSTALL_DIR" in
  /*) ;;
  *) INSTALL_DIR="$START_DIR/$INSTALL_DIR" ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  echo "未找到 docker 命令，请先安装 Docker。" >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "未找到 docker compose 或 docker-compose，请先安装 Docker Compose。" >&2
  exit 1
fi

RAW_HOST_ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || true)"
if [ -z "$RAW_HOST_ARCH" ]; then
  echo "无法读取 Docker 运行架构，请确认 Docker 服务已经启动。" >&2
  exit 1
fi

case "$RAW_HOST_ARCH" in
  amd64 | x86_64)
    HOST_ARCH="amd64"
    TARGET_PLATFORM="linux/amd64"
    ;;
  arm64 | aarch64)
    HOST_ARCH="arm64"
    TARGET_PLATFORM="linux/arm64"
    ;;
  arm | armv7 | armv7l)
    HOST_ARCH="arm"
    TARGET_PLATFORM="linux/arm/v7"
    ;;
  *)
    echo "当前架构暂不支持：$RAW_HOST_ARCH；支持的平台为 linux/amd64、linux/arm64、linux/arm/v7。" >&2
    exit 1
    ;;
esac

image_is_for_host() {
  image_arch="$(docker image inspect --format '{{.Architecture}}' "$1" 2>/dev/null || true)"
  [ "$image_arch" = "$HOST_ARCH" ]
}

echo "检测到 Docker 目标架构：$TARGET_PLATFORM"
echo

fuse_mount_present() {
  [ "$(findmnt -T "$1" -n -o FSTYPE 2>/dev/null || true)" = "fuse.xymediavault" ]
}

cleanup_fuse_mount() {
  mount_path="$1"
  if ! fuse_mount_present "$mount_path"; then
    return 0
  fi

  echo "检测到旧 FUSE 挂载，正在卸载：$mount_path"
  if command -v fusermount3 >/dev/null 2>&1; then
    fusermount3 -uz "$mount_path" 2>/dev/null || true
  fi
  if command -v fusermount >/dev/null 2>&1; then
    fusermount -uz "$mount_path" 2>/dev/null || true
  fi
  umount -l "$mount_path" 2>/dev/null || true

  attempt=1
  while [ "$attempt" -le 10 ]; do
    if ! fuse_mount_present "$mount_path"; then
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done

  echo "无法清理 FUSE 挂载：$mount_path，请执行 umount -l 后重试。" >&2
  return 1
}

if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
  echo "检测到已有 XyMediaVault 安装：$INSTALL_DIR"
  CONTINUE_UPDATE="$(prompt_bool "更新现有安装" "true")"
  if [ "$CONTINUE_UPDATE" != "true" ]; then
    echo "已取消更新。"
    exit 0
  fi

  mkdir -p "$INSTALL_DIR/mnt/xymediavault"
  cd "$INSTALL_DIR"

  echo "停止旧 XyMediaVault 容器..."
  $COMPOSE stop xymediavault >/dev/null 2>&1 || true
  cleanup_fuse_mount "$INSTALL_DIR/mnt/xymediavault"
  mkdir -p "$INSTALL_DIR/mnt/xymediavault"

  if grep -q '^[[:space:]]*build:' docker-compose.yml; then
    echo "检测到本地构建模式，重新构建 XyMediaVault 镜像..."
    $COMPOSE build xymediavault
  else
    echo "拉取最新 XyMediaVault 镜像..."
    $COMPOSE pull xymediavault
  fi

  echo "重建 XyMediaVault 容器..."
  $COMPOSE up -d --no-deps --force-recreate xymediavault

  echo
  echo "更新完成。"
  echo "安装目录：$INSTALL_DIR"
  exit 0
fi

echo "未检测到已有安装，进入首次安装配置。"
echo "每一项都提供默认值，不输入内容直接按回车即可使用默认值。"
echo

DETECTED_HOST="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
if [ -z "$DETECTED_HOST" ]; then
  DETECTED_HOST="127.0.0.1"
fi

IMAGE="$(prompt_value "Docker 镜像" "${IMAGE:-iceqi/xymediavault:latest}")"
PUBLIC_HOST="$(prompt_value "服务器访问 IP 或域名" "${PUBLIC_HOST:-$DETECTED_HOST}")"
API_PORT="$(prompt_value "管理后台端口" "${API_PORT:-18080}")"
WEBDAV_PORT="$(prompt_value "WebDAV 端口" "${WEBDAV_PORT:-18081}")"
XIAOYA_PORT="$(prompt_value "小雅 Alist 端口" "${XIAOYA_PORT:-5678}")"
XIAOYA_ADMIN_PORT="$(prompt_value "小雅管理端口" "${XIAOYA_ADMIN_PORT:-2345}")"
XIAOYA_PROXY_PORT="$(prompt_value "小雅代理端口" "${XIAOYA_PROXY_PORT:-2346}")"
ENABLE_FUSE="$(prompt_bool "启用 FUSE 虚拟目录" "${ENABLE_FUSE:-true}")"
FUSE_DIRECTORY_MODE="$(prompt_value "FUSE 目录模式 original/organized" "${FUSE_DIRECTORY_MODE:-original}")"
FORCE_PULL="$(prompt_bool "强制从远端拉取镜像" "${FORCE_PULL:-false}")"

echo
echo "安装参数确认："
echo "  Docker 镜像：$IMAGE"
echo "  目标架构：$TARGET_PLATFORM"
echo "  安装目录：$INSTALL_DIR"
echo "  服务器访问地址：$PUBLIC_HOST"
echo "  管理后台端口：$API_PORT"
echo "  WebDAV 端口：$WEBDAV_PORT"
echo "  小雅 Alist 端口：$XIAOYA_PORT"
echo "  小雅管理端口：$XIAOYA_ADMIN_PORT"
echo "  小雅代理端口：$XIAOYA_PROXY_PORT"
echo "  FUSE：$ENABLE_FUSE"
echo "  FUSE 目录模式：$FUSE_DIRECTORY_MODE"
echo "  强制拉取：$FORCE_PULL"
echo

CONTINUE_INSTALL="$(prompt_bool "确认使用以上参数继续安装" "true")"
if [ "$CONTINUE_INSTALL" != "true" ]; then
  echo "已取消安装。"
  exit 0
fi

mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/xiaoya/data" "$INSTALL_DIR/mnt/xymediavault"
cd "$INSTALL_DIR"

# 旧版本异常退出可能留下 FUSE 坏挂载，确认清理完成后再交给 Docker 做 bind mount。
cleanup_fuse_mount "$INSTALL_DIR/mnt/xymediavault"
mkdir -p "$INSTALL_DIR/mnt/xymediavault"

WRITE_CONFIG="true"
if [ -f config.yaml ]; then
  WRITE_CONFIG="$(prompt_bool "检测到已有 config.yaml，是否覆盖" "false")"
fi

if [ "$WRITE_CONFIG" = "true" ]; then
  cat > config.yaml <<CONFIG
server:
  host: 0.0.0.0
  port: 8080
  web_dir: /app/web/dist

database:
  driver: sqlite
  dsn: /app/data/xymediavault.db

virtual:
  enable_remote_file_mapping: false

webdav:
  enabled: true
  listen_addr: 0.0.0.0
  port: 8081
  base_path: /dav
  read_only: true
  directory_mode: original

fuse:
  enabled: ${ENABLE_FUSE}
  mount_path: /mnt/xymediavault
  directory_mode: ${FUSE_DIRECTORY_MODE}

xiaoya:
  config_dir: /app/xiaoya
  container_name: xiaoya-alist
  internal_url: http://xiaoya-alist:80
  public_url: http://${PUBLIC_HOST}:${XIAOYA_PORT}
  docker_socket: /var/run/docker.sock

log:
  level: info
CONFIG
else
  echo "保留已有配置：$INSTALL_DIR/config.yaml"
fi

FUSE_BLOCK=""
if [ "$ENABLE_FUSE" = "true" ]; then
  FUSE_BLOCK='
    devices:
      - /dev/fuse:/dev/fuse
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined'
fi

cat > docker-compose.yml <<COMPOSE
services:
  xymediavault:
    image: ${IMAGE}
    container_name: xymediavault
    ports:
      - "${API_PORT}:8080"
      - "${WEBDAV_PORT}:8081"
    depends_on:
      - xiaoya-alist${FUSE_BLOCK}
    volumes:
      - ./data:/app/data
      - ./mnt/xymediavault:/mnt/xymediavault:rshared
      - ./xiaoya:/app/xiaoya
      - /var/run/docker.sock:/var/run/docker.sock
      - ./config.yaml:/app/config.yaml:ro
    stop_grace_period: 15s
    restart: unless-stopped

  xiaoya-alist:
    image: xiaoyaliu/alist:latest
    container_name: xiaoya-alist
    ports:
      - "${XIAOYA_PORT}:80"
      - "${XIAOYA_ADMIN_PORT}:2345"
      - "${XIAOYA_PROXY_PORT}:2346"
    volumes:
      - ./xiaoya:/data
      - ./xiaoya/data:/www/data
    restart: unless-stopped
COMPOSE

echo "准备启动服务..."

# 本地已有同架构标签时直接复用；架构不匹配时重新拉取 DockerHub 的对应镜像。
if [ "$FORCE_PULL" = "true" ]; then
  echo "强制拉取镜像：$IMAGE"
  $COMPOSE pull
else
  if image_is_for_host "$IMAGE"; then
    echo "检测到本地镜像：$IMAGE（$TARGET_PLATFORM），跳过 XyMediaVault 拉取。"
  else
    echo "本地没有匹配 $TARGET_PLATFORM 的镜像，开始拉取：$IMAGE"
    $COMPOSE pull xymediavault
  fi

  if image_is_for_host xiaoyaliu/alist:latest; then
    echo "检测到本地镜像：xiaoyaliu/alist:latest（$TARGET_PLATFORM），跳过小雅拉取。"
  else
    echo "本地没有匹配 $TARGET_PLATFORM 的小雅镜像，开始拉取。"
    $COMPOSE pull xiaoya-alist
  fi
fi

$COMPOSE up -d

echo
echo "部署完成。"
echo "管理后台：http://${PUBLIC_HOST}:${API_PORT}"
echo "WebDAV：http://${PUBLIC_HOST}:${WEBDAV_PORT}/dav"
echo "小雅 Alist：http://${PUBLIC_HOST}:${XIAOYA_PORT}"
echo "安装目录：${INSTALL_DIR}"
if [ "$ENABLE_FUSE" = "true" ]; then
  echo "FUSE 宿主机目录：${INSTALL_DIR}/mnt/xymediavault"
fi
