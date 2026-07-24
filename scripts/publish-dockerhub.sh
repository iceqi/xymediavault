#!/usr/bin/env sh
set -eu

# 发布脚本用于把当前源码构建成 DockerHub 镜像并推送。
# 使用前先执行：docker login
# 示例：
#   DOCKER_IMAGE=你的DockerHub用户名/xymediavault VERSION=1.0.0 sh scripts/publish-dockerhub.sh

DOCKER_IMAGE="${DOCKER_IMAGE:-}"
VERSION="${VERSION:-latest}"
DOCKERFILE="${DOCKERFILE:-docker/Dockerfile}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v7}"
BUILDER="${BUILDER:-xymediavault-multiarch-v2}"
BUILDKIT_CONFIG="${BUILDKIT_CONFIG:-docker/buildkitd.toml}"
BUILDX_HTTP_PROXY="${BUILDX_HTTP_PROXY:-${HTTP_PROXY:-${http_proxy:-}}}"
BUILDX_HTTPS_PROXY="${BUILDX_HTTPS_PROXY:-${HTTPS_PROXY:-${https_proxy:-}}}"

if [ -z "$DOCKER_IMAGE" ]; then
  echo "请设置 DOCKER_IMAGE，例如：DOCKER_IMAGE=iceqi/xymediavault VERSION=1.0.0 sh scripts/publish-dockerhub.sh" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "未找到 docker 命令，请先安装 Docker。" >&2
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo "未找到 Docker Buildx，请先安装或启用 buildx，用于构建多架构镜像。" >&2
  exit 1
fi

if [ ! -f "$BUILDKIT_CONFIG" ]; then
  echo "未找到 BuildKit 配置：$BUILDKIT_CONFIG" >&2
  exit 1
fi

# Docker-container builder 不会自动继承 Docker daemon 的代理，优先读取显式环境变量，
# 在 systemd 主机上再尝试复用 docker.service 的代理配置。
if [ -z "$BUILDX_HTTPS_PROXY" ] && command -v systemctl >/dev/null 2>&1; then
  docker_service_env="$(systemctl show docker --property=Environment --value 2>/dev/null || true)"
  BUILDX_HTTP_PROXY="$(printf '%s' "$docker_service_env" | sed -n 's/.*HTTP_PROXY=\([^ ]*\).*/\1/p')"
  BUILDX_HTTPS_PROXY="$(printf '%s' "$docker_service_env" | sed -n 's/.*HTTPS_PROXY=\([^ ]*\).*/\1/p')"
  BUILDX_HTTP_PROXY="${BUILDX_HTTP_PROXY#\"}"
  BUILDX_HTTP_PROXY="${BUILDX_HTTP_PROXY%\"}"
  BUILDX_HTTPS_PROXY="${BUILDX_HTTPS_PROXY#\"}"
  BUILDX_HTTPS_PROXY="${BUILDX_HTTPS_PROXY%\"}"
fi

if [ -z "$BUILDX_HTTP_PROXY" ]; then
  BUILDX_HTTP_PROXY="$BUILDX_HTTPS_PROXY"
fi
if [ -z "$BUILDX_HTTPS_PROXY" ]; then
  BUILDX_HTTPS_PROXY="$BUILDX_HTTP_PROXY"
fi

# BuildKit daemon 负责上传镜像层，Buildx 客户端负责获取 DockerHub OAuth token；
# 两边都必须使用同一代理，否则会出现层已上传但 token 请求仍然直连超时。
if [ -n "$BUILDX_HTTPS_PROXY" ]; then
  export HTTP_PROXY="$BUILDX_HTTP_PROXY"
  export HTTPS_PROXY="$BUILDX_HTTPS_PROXY"
  export http_proxy="$BUILDX_HTTP_PROXY"
  export https_proxy="$BUILDX_HTTPS_PROXY"
fi

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  echo "创建 Buildx builder：$BUILDER"
  if [ -n "$BUILDX_HTTPS_PROXY" ]; then
    docker buildx create \
      --name "$BUILDER" \
      --config "$BUILDKIT_CONFIG" \
      --driver-opt "env.HTTP_PROXY=$BUILDX_HTTP_PROXY" \
      --driver-opt "env.HTTPS_PROXY=$BUILDX_HTTPS_PROXY" \
      --use
  else
    docker buildx create --name "$BUILDER" --config "$BUILDKIT_CONFIG" --use
  fi
fi

docker buildx inspect "$BUILDER" --bootstrap >/dev/null

echo "构建镜像：$DOCKER_IMAGE:$VERSION"
echo "目标平台：$PLATFORMS"
set -- -t "$DOCKER_IMAGE:$VERSION"
if [ "$VERSION" != "latest" ]; then
  echo "同步 latest 标签：$DOCKER_IMAGE:latest"
  set -- "$@" -t "$DOCKER_IMAGE:latest"
fi

docker buildx build \
  --builder "$BUILDER" \
  --platform "$PLATFORMS" \
  -f "$DOCKERFILE" \
  "$@" \
  --push \
  .

echo "发布完成。"
