#!/usr/bin/env sh
set -eu

# XyMediaVault 一键部署脚本。
# 示例：
#   curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh
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

START_DIR="$(pwd -P)"
INSTALL_DIR="$(prompt_value "安装目录" "${1:-$START_DIR}")"
case "$INSTALL_DIR" in
  /*) ;;
  *) INSTALL_DIR="$START_DIR/$INSTALL_DIR" ;;
esac
FUSE_HOST_PATH="$INSTALL_DIR/mnt/xymediavault"
EMBY_HOST_PATH="$INSTALL_DIR/emby"
API_PORT="${API_PORT:-18080}"
TVBOX_PORT="${TVBOX_PORT:-18082}"
WEBDAV_PORT="${WEBDAV_PORT:-18081}"
XIAOYA_PORT="${XIAOYA_PORT:-5678}"

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

# Compose 默认从目录名生成项目名；纯中文目录会被规范化为空字符串。
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-xymediavault}"
export COMPOSE_PROJECT_NAME

DOCKER_INFO_ERROR="$(mktemp "${TMPDIR:-/tmp}/xymediavault-docker-info.XXXXXX")"
if ! docker info >/dev/null 2>"$DOCKER_INFO_ERROR"; then
  echo "无法连接 Docker 服务。" >&2
  echo "请确认 Docker 已启动，并使用有 Docker 套接字权限的账号执行安装命令。" >&2
  if [ -s "$DOCKER_INFO_ERROR" ]; then
    echo "Docker 返回的错误：" >&2
    sed 's/^/  /' "$DOCKER_INFO_ERROR" >&2
  fi
  rm -f "$DOCKER_INFO_ERROR"
  exit 1
fi
rm -f "$DOCKER_INFO_ERROR"

detect_docker_arch() {
  detected_arch="$(docker version --format '{{.Server.Arch}}' 2>/dev/null || true)"
  case "$detected_arch" in
    "" | "<no value>") detected_arch="$(docker info --format '{{.Architecture}}' 2>/dev/null || true)" ;;
  esac
  case "$detected_arch" in
    "" | "<no value>") detected_arch="$(uname -m 2>/dev/null || true)" ;;
  esac
  printf "%s\n" "$detected_arch" | awk 'NF { print tolower($1); exit }'
}

RAW_HOST_ARCH="$(detect_docker_arch)"
if [ -z "$RAW_HOST_ARCH" ]; then
  echo "Docker 服务可以访问，但无法识别运行架构。" >&2
  echo "请反馈以下命令输出：docker version、docker info、uname -m。" >&2
  exit 1
fi

case "$RAW_HOST_ARCH" in
  amd64 | x86_64 | linux/amd64)
    HOST_ARCH="amd64"
    TARGET_PLATFORM="linux/amd64"
    ;;
  arm64 | aarch64 | linux/arm64)
    HOST_ARCH="arm64"
    TARGET_PLATFORM="linux/arm64"
    ;;
  arm | armv7 | armv7l | armhf | linux/arm/v7)
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
  mount_fstype="$(findmnt -M "$1" -n -o FSTYPE 2>/dev/null || true)"
  case "$mount_fstype" in
    fuse | fuse.*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup_fuse_mount() {
  mount_path="$1"
  if ! fuse_mount_present "$mount_path"; then
    return 0
  fi

  echo "检测到旧媒体库挂载，正在卸载：$mount_path"
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

  echo "无法清理媒体库挂载：$mount_path，请执行 umount -l 后重试。" >&2
  return 1
}

prepare_emby_config_dir() {
  mkdir -p "$EMBY_HOST_PATH/config"
  if chown -R 2:2 "$EMBY_HOST_PATH/config" 2>/dev/null; then
    chmod -R u+rwX "$EMBY_HOST_PATH/config"
    return 0
  fi

  echo "当前文件系统不允许设置 Emby 配置目录所有者，改用兼容写权限：$EMBY_HOST_PATH/config"
  if ! chmod -R a+rwX "$EMBY_HOST_PATH/config"; then
    echo "无法为 Emby 配置目录设置写权限：$EMBY_HOST_PATH/config" >&2
    return 1
  fi
}

ensure_media_mount_compose_permissions() {
  compose_file="$1"
  if grep -q '/dev/fuse:/dev/fuse' "$compose_file"; then
    return 0
  fi
  temporary_compose="$(mktemp "${TMPDIR:-/tmp}/xymediavault-compose.XXXXXX")"
  if ! awk '
    BEGIN { in_service = 0; inserted = 0 }
    /^  xymediavault:[[:space:]]*$/ { in_service = 1 }
    in_service && !inserted && /^    volumes:[[:space:]]*$/ {
      print "    devices:"
      print "      - /dev/fuse:/dev/fuse"
      print "    cap_add:"
      print "      - SYS_ADMIN"
      print "    security_opt:"
      print "      - apparmor:unconfined"
      inserted = 1
    }
    { print }
    END { if (!inserted) exit 42 }
  ' "$compose_file" >"$temporary_compose"; then
    rm -f "$temporary_compose"
    echo "更新媒体库挂载权限失败。" >&2
    return 1
  fi
  mv "$temporary_compose" "$compose_file"
}

ensure_tvbox_compose_port() {
  compose_file="$1"
  if grep -Eq "8082[[:space:]\"']*$" "$compose_file"; then
    return 0
  fi

  temporary_compose="$(mktemp "${TMPDIR:-/tmp}/xymediavault-compose.XXXXXX")"
  if ! awk -v mapping="${TVBOX_PORT}:8082" '
    BEGIN { in_service = 0; in_ports = 0; inserted = 0 }
    in_ports && $0 !~ /^      - / {
      print "      - \"" mapping "\""
      in_ports = 0
      inserted = 1
    }
    {
      print
      if ($0 ~ /^  xymediavault:[[:space:]]*$/) {
        in_service = 1
      } else if (in_service && $0 ~ /^  [^ ]/) {
        in_service = 0
      }
      if (in_service && $0 ~ /^    ports:[[:space:]]*$/) {
        in_ports = 1
      }
    }
    END {
      if (in_ports) {
        print "      - \"" mapping "\""
        inserted = 1
      }
      if (!inserted) exit 42
    }
  ' "$compose_file" >"$temporary_compose"; then
    rm -f "$temporary_compose"
    echo "无法在 $compose_file 的 xymediavault.ports 中加入 TVBox 端口。" >&2
    return 1
  fi
  mv "$temporary_compose" "$compose_file"
}

ensure_tvbox_runtime_config() {
  config_file="$1"
  [ -f "$config_file" ] || return 0

  temporary_config="$(mktemp "${TMPDIR:-/tmp}/xymediavault-config.XXXXXX")"
  if ! awk -v public_port="$TVBOX_PORT" '
    BEGIN { in_tvbox = 0; found = 0; inserted = 0 }
    in_tvbox && $0 ~ /^[^[:space:]#]/ {
      if (!inserted) print "  public_port: " public_port
      in_tvbox = 0
      inserted = 1
    }
    {
      print
      if ($0 ~ /^tvbox:[[:space:]]*$/) {
        in_tvbox = 1
        found = 1
      } else if (in_tvbox && $0 ~ /^  public_port:[[:space:]]*/) {
        inserted = 1
      }
    }
    END {
      if (in_tvbox && !inserted) print "  public_port: " public_port
      if (!found) {
        print ""
        print "tvbox:"
        print "  enabled: true"
        print "  listen_addr: 0.0.0.0"
        print "  port: 8082"
        print "  public_port: " public_port
        print "  public_url: \"\""
        print "  token_key_file: /app/data/tvbox-token.key"
      }
    }
  ' "$config_file" >"$temporary_config"; then
    rm -f "$temporary_config"
    echo "更新 $config_file 的 TVBox 配置失败。" >&2
    return 1
  fi
  mv "$temporary_config" "$config_file"
}

ensure_webdav_runtime_config() {
  config_file="$1"
  [ -f "$config_file" ] || return 0

  temporary_config="$(mktemp "${TMPDIR:-/tmp}/xymediavault-config.XXXXXX")"
  if ! awk -v public_port="$WEBDAV_PORT" '
    BEGIN { in_webdav = 0; found = 0; inserted = 0 }
    in_webdav && $0 ~ /^[^[:space:]#]/ {
      if (!inserted) print "  public_port: " public_port
      in_webdav = 0
      inserted = 1
    }
    {
      if (in_webdav && $0 ~ /^  public_port:[[:space:]]*/) {
        print "  public_port: " public_port
        inserted = 1
        next
      }
      print
      if ($0 ~ /^webdav:[[:space:]]*$/) {
        in_webdav = 1
        found = 1
      }
    }
    END {
      if (in_webdav && !inserted) print "  public_port: " public_port
      if (!found) {
        print ""
        print "webdav:"
        print "  enabled: true"
        print "  listen_addr: 0.0.0.0"
        print "  port: 8081"
        print "  public_port: " public_port
        print "  base_path: /dav"
        print "  read_only: true"
      }
    }
  ' "$config_file" >"$temporary_config"; then
    rm -f "$temporary_config"
    echo "更新 $config_file 的 WebDAV 配置失败。" >&2
    return 1
  fi
  mv "$temporary_config" "$config_file"
}

detect_compose_host_port() {
  compose_file="$1"
  container_port="$2"
  sed -nE "s/^[[:space:]]*-[[:space:]]*\"?([0-9]+):${container_port}\"?[[:space:]]*$/\1/p" "$compose_file" | tail -n 1
}

print_access_info() {
  echo "管理页面：http://${PUBLIC_HOST}:${API_PORT}"
  echo "WebDAV：http://${PUBLIC_HOST}:${WEBDAV_PORT}/dav"
  echo "TVBox：http://${PUBLIC_HOST}:${TVBOX_PORT}"
  echo "小雅 Alist：http://${PUBLIC_HOST}:${XIAOYA_PORT}"
  echo "安装目录：${INSTALL_DIR}"
  echo "媒体库挂载目录：${FUSE_HOST_PATH}"
}

DETECTED_HOST="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
if [ -z "$DETECTED_HOST" ]; then
  DETECTED_HOST="127.0.0.1"
fi
PUBLIC_HOST="${PUBLIC_HOST:-$DETECTED_HOST}"

if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
  echo "检测到已有 XyMediaVault 安装：$INSTALL_DIR"
  CONTINUE_UPDATE="$(prompt_bool "更新现有安装" "true")"
  if [ "$CONTINUE_UPDATE" != "true" ]; then
    echo "已取消更新。"
    exit 0
  fi

	mkdir -p "$FUSE_HOST_PATH" "$EMBY_HOST_PATH/config"
	prepare_emby_config_dir
	cd "$INSTALL_DIR"
  detected_api_port="$(detect_compose_host_port docker-compose.yml 8080 || true)"
  detected_webdav_port="$(detect_compose_host_port docker-compose.yml 8081 || true)"
  detected_tvbox_port="$(detect_compose_host_port docker-compose.yml 8082 || true)"
  detected_xiaoya_port="$(detect_compose_host_port docker-compose.yml 80 || true)"
  [ -z "$detected_api_port" ] || API_PORT="$detected_api_port"
  [ -z "$detected_webdav_port" ] || WEBDAV_PORT="$detected_webdav_port"
  [ -z "$detected_tvbox_port" ] || TVBOX_PORT="$detected_tvbox_port"
  [ -z "$detected_xiaoya_port" ] || XIAOYA_PORT="$detected_xiaoya_port"

  echo "停止旧 XyMediaVault 容器..."
  $COMPOSE stop xymediavault >/dev/null 2>&1 || true
  cleanup_fuse_mount "$FUSE_HOST_PATH"
  cleanup_fuse_mount "/mnt/xymediavault"
  mkdir -p "$FUSE_HOST_PATH"

  # 使用安装目录下的宿主机挂载点，并将其绝对路径传给后台页面展示。
  temporary_compose="$(mktemp "${TMPDIR:-/tmp}/xymediavault-compose.XXXXXX")"
  if ! awk \
    -v fuse_host_path="$FUSE_HOST_PATH" \
    -v xiaoya_host_path="$INSTALL_DIR/xiaoya" \
    -v emby_host_path="$EMBY_HOST_PATH" '
    function yaml_quote(value) {
      gsub(/\\/, "\\\\", value)
      gsub(/"/, "\\\"", value)
      return "\"" value "\""
    }
    function print_runtime_environment() {
      print "      TZ: \"Asia/Shanghai\""
      print "      XYMEDIAVAULT_FUSE_HOST_PATH: " yaml_quote(fuse_host_path)
      print "      XYMEDIAVAULT_XIAOYA_HOST_PATH: " yaml_quote(xiaoya_host_path)
      print "      XYMEDIAVAULT_EMBY_HOST_PATH: " yaml_quote(emby_host_path)
    }
    {
      lines[NR] = $0
    }
    END {
      service_start = 0
      service_end = NR + 1
      environment_line = 0
      container_line = 0

      for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /^  xymediavault:[[:space:]]*$/) {
          service_start = i
          continue
        }
        if (service_start && i > service_start && lines[i] ~ /^  [^[:space:]][^:]*:[[:space:]]*$/) {
          service_end = i
          break
        }
      }
      if (!service_start) exit 42

      for (i = service_start + 1; i < service_end; i++) {
        if (lines[i] ~ /^    container_name:[[:space:]]*/) container_line = i
        if (lines[i] ~ /^    environment:[[:space:]]*$/) environment_line = i
      }

      for (i = 1; i <= NR; i++) {
        line = lines[i]
        if (i > service_start && i < service_end &&
            line ~ /^[[:space:]]*-[[:space:]]*\/mnt\/xymediavault:\/mnt\/xymediavault:rshared[[:space:]]*$/) {
          sub(/\/mnt\/xymediavault:\/mnt\/xymediavault:rshared/, "./mnt/xymediavault:/mnt/xymediavault:rshared", line)
        }

        in_runtime_environment = environment_line && i > environment_line && i < service_end
        if (in_runtime_environment && line ~ /^    [^[:space:]]/) in_runtime_environment = 0
        if (in_runtime_environment && line ~ /^      (TZ|XYMEDIAVAULT_FUSE_HOST_PATH|XYMEDIAVAULT_XIAOYA_HOST_PATH|XYMEDIAVAULT_EMBY_HOST_PATH):/) {
          continue
        }

        print line
        if (environment_line && i == environment_line) {
          print_runtime_environment()
        } else if (!environment_line && ((container_line && i == container_line) || (!container_line && i == service_start))) {
          print "    environment:"
          print_runtime_environment()
        }
      }
    }
  ' docker-compose.yml >"$temporary_compose"; then
    rm -f "$temporary_compose"
    echo "更新 docker-compose.yml 的宿主机路径失败。" >&2
    exit 1
  fi
  mv "$temporary_compose" docker-compose.yml
  ensure_tvbox_compose_port docker-compose.yml
  ensure_media_mount_compose_permissions docker-compose.yml
  ensure_tvbox_runtime_config config.yaml
  ensure_webdav_runtime_config config.yaml

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
  print_access_info
  exit 0
fi

echo "未检测到已有安装，进入首次安装配置。"
echo "每一项都提供默认值，不输入内容直接按回车即可使用默认值。"
echo

IMAGE="$(prompt_value "Docker 镜像" "${IMAGE:-iceqi/xymediavault:latest}")"
PUBLIC_HOST="$(prompt_value "服务器访问 IP 或域名" "${PUBLIC_HOST:-$DETECTED_HOST}")"
API_PORT="$(prompt_value "管理后台端口" "${API_PORT:-18080}")"
WEBDAV_PORT="$(prompt_value "WebDAV 端口" "${WEBDAV_PORT:-18081}")"
TVBOX_PORT="$(prompt_value "TVBox 服务端口" "${TVBOX_PORT:-18082}")"
XIAOYA_PORT="$(prompt_value "小雅 Alist 端口" "${XIAOYA_PORT:-5678}")"
XIAOYA_ADMIN_PORT="$(prompt_value "小雅管理端口" "${XIAOYA_ADMIN_PORT:-2345}")"
XIAOYA_PROXY_PORT="$(prompt_value "小雅代理端口" "${XIAOYA_PROXY_PORT:-2346}")"
ENABLE_FUSE="$(prompt_bool "启用媒体库挂载" "${ENABLE_FUSE:-true}")"
FORCE_PULL="$(prompt_bool "强制从远端拉取镜像" "${FORCE_PULL:-false}")"

echo
echo "安装参数确认："
echo "  Docker 镜像：$IMAGE"
echo "  目标架构：$TARGET_PLATFORM"
echo "  安装目录：$INSTALL_DIR"
echo "  服务器访问地址：$PUBLIC_HOST"
echo "  管理后台端口：$API_PORT"
echo "  WebDAV 端口：$WEBDAV_PORT"
echo "  TVBox 服务端口：$TVBOX_PORT"
echo "  小雅 Alist 端口：$XIAOYA_PORT"
echo "  小雅管理端口：$XIAOYA_ADMIN_PORT"
echo "  小雅代理端口：$XIAOYA_PROXY_PORT"
echo "  媒体库挂载：$ENABLE_FUSE"
echo "  强制拉取：$FORCE_PULL"
echo

CONTINUE_INSTALL="$(prompt_bool "确认使用以上参数继续安装" "true")"
if [ "$CONTINUE_INSTALL" != "true" ]; then
  echo "已取消安装。"
  exit 0
fi

mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/xiaoya/data" "$FUSE_HOST_PATH" "$EMBY_HOST_PATH/config"
prepare_emby_config_dir
cd "$INSTALL_DIR"

# 旧版本异常退出可能留下媒体库坏挂载，确认清理完成后再交给 Docker 做 bind mount。
cleanup_fuse_mount "$FUSE_HOST_PATH"
mkdir -p "$FUSE_HOST_PATH"

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
  public_port: ${WEBDAV_PORT}
  base_path: /dav
  read_only: true

tvbox:
  enabled: true
  listen_addr: 0.0.0.0
  port: 8082
  public_port: ${TVBOX_PORT}
  public_url: http://${PUBLIC_HOST}:${TVBOX_PORT}
  token_key_file: /app/data/tvbox-token.key

fuse:
  enabled: ${ENABLE_FUSE}
  mount_path: /mnt/xymediavault

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

cat > docker-compose.yml <<COMPOSE
services:
  xymediavault:
    image: ${IMAGE}
    container_name: xymediavault
    environment:
      TZ: "Asia/Shanghai"
      XYMEDIAVAULT_FUSE_HOST_PATH: "${FUSE_HOST_PATH}"
      XYMEDIAVAULT_XIAOYA_HOST_PATH: "${INSTALL_DIR}/xiaoya"
      XYMEDIAVAULT_EMBY_HOST_PATH: "${EMBY_HOST_PATH}"
    ports:
      - "${API_PORT}:8080"
      - "${WEBDAV_PORT}:8081"
      - "${TVBOX_PORT}:8082"
    depends_on:
      - xiaoya-alist
    devices:
      - /dev/fuse:/dev/fuse
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    volumes:
      - ./data:/app/data
      - ${FUSE_HOST_PATH}:/mnt/xymediavault:rshared
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
print_access_info
