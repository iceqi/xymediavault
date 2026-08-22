# XyMediaVault

XyMediaVault 是面向小雅 Alist、Emby、Jellyfin、Infuse 和 TVBox 的媒体资源管理服务，提供媒体索引、只读 WebDAV、媒体视图、TVBox CMS、小雅授权与组件运行管理。

> 本项目为闭源软件。此仓库只发布安装脚本、部署说明和签名 Release 资产，不包含应用源码。

## 快速安装

### 正式版

```bash
curl -fsSL \
  https://gh-proxy.org/https://github.com/iceqi/xymediavault/releases/download/v1.3.0/bootstrap.sh \
  | XYMEDIA_INSTALL_DIR=/opt/xymedia \
    XYMEDIA_SKIP_SIGNATURE_VERIFY=1 \
    sh -s -- v1.3.0
```

将 `/opt/xymedia` 替换为希望使用的安装目录，例如：

```text
/vol1/1000/xy-media
```

### Beta 版

```bash
curl -fsSL \
  https://gh-proxy.org/https://github.com/iceqi/xymediavault/releases/download/v1.3.0-beta.1/bootstrap.sh \
  | XYMEDIA_INSTALL_DIR=/opt/xymedia \
    XYMEDIA_SKIP_SIGNATURE_VERIFY=1 \
    sh -s -- v1.3.0-beta.1
```

安装器默认通过 `https://gh-proxy.org/` 下载 GitHub Release 资产，但仍会校验 SHA-256。设置 `XYMEDIA_DOWNLOAD_PROXY=` 可改为直连 GitHub。

`XYMEDIA_SKIP_SIGNATURE_VERIFY=1` 仅建议用于暂未安装 Cosign 的测试环境。生产环境应安装 Cosign 并移除该变量，以验证 Release 的 OIDC 签名。

## 默认端口

| 服务 | 端口 | 地址 |
| --- | ---: | --- |
| 管理后台 | 18080 | `http://服务器IP:18080` |
| WebDAV | 18081 | `http://服务器IP:18081/dav` |
| TVBox | 18082 | `http://服务器IP:18082` |
| 小雅 Alist | 5678 | `http://服务器IP:5678` |

安装后检查：

```bash
cd /opt/xymedia
docker compose --env-file .env -f compose.yaml ps
curl -fsS http://127.0.0.1:18080/api/health
```

## 安装内容

正式 Compose 包含：

- PostgreSQL 17 独立数据库；
- XyMediaVault 应用；
- 独立 updater；
- 小雅兼容代理；
- 修复版 Xiaoya Alist；
- TMM 与 Title 本地组件运行时。

镜像支持：

```text
linux/amd64
linux/arm64
```

镜像使用签名 manifest 中记录的 OCI digest，不依赖浮动 `latest`。

## 升级

对已有独立 PostgreSQL 版本安装目录，执行新的 Release 安装命令即可。安装器会自动进入升级模式，并保留：

- PostgreSQL 数据卷；
- 数据库密码；
- 应用状态；
- 小雅数据；
- 更新备份。

例如升级到正式版 1.3.0：

```bash
curl -fsSL \
  https://gh-proxy.org/https://github.com/iceqi/xymediavault/releases/download/v1.3.0/bootstrap.sh \
  | XYMEDIA_INSTALL_DIR=/opt/xymedia \
    XYMEDIA_SKIP_SIGNATURE_VERIFY=1 \
    sh -s -- v1.3.0
```

旧 bundled PostgreSQL 版本不能直接覆盖安装，请使用 Release 中的 `upgrade-from-bundled.sh`，并先备份原数据卷。

## FUSE 挂载

默认安装不授予 FUSE 高权限。只使用管理后台、WebDAV 和 TVBox 时，不需要启用 FUSE。

需要全局媒体库挂载时：

```bash
cd /opt/xymedia
docker compose \
  --env-file .env \
  -f compose.yaml \
  -f compose.fuse.yaml \
  up -d app
```

该 override 会授予：

```text
/dev/fuse
CAP_SYS_ADMIN
apparmor:unconfined
```

仅应在受信任宿主机启用。

## 1.3 路径变化

1.3 起媒体投影按年份分桶：

```text
/电影/<年份>/<作品>/
/电视剧/<年份>/<作品>/
```

缺少年份的内容位于 `未知年份`。Emby、WebDAV 或脚本中保存的旧路径需要重新扫描或更新引用。

## 数据与备份

安装目录保存：

```text
.env
compose.yaml
compose.fuse.yaml
config.yaml
secrets/
releases/
media/
xiaoya/
```

Docker 命名卷保存 PostgreSQL、应用状态、组件、更新状态和备份。不要执行：

```bash
docker compose down -v
```

除非明确要永久删除数据库和所有状态。

## 卸载

默认卸载保留数据卷和安装目录：

```bash
cd /opt/xymedia
sh uninstall.sh
```

删除数据必须显式使用 `--purge-data` 并完成二次确认。

## 常见问题

### GHCR 返回 unauthorized

确认四个容器包已经设置为 Public，或先登录 GHCR：

```bash
docker login ghcr.io
```

### 缺少 Cosign

测试环境可以暂时设置：

```bash
XYMEDIA_SKIP_SIGNATURE_VERIFY=1
```

正式环境建议安装 Cosign，不跳过签名验证。

### PostgreSQL password authentication failed

通常是复用了旧数据库卷，但更换了 `secrets/postgres-password`。不要删除数据卷，应同步 PostgreSQL 角色密码与当前 secret，或在确认无数据时全新安装。

### Xiaoya 出现 emby.js SyntaxError

请升级到 1.3.0 或更高版本。正式镜像会在 Nginx 读取配置前修复上游动态生成的非法 JavaScript。

### App 长时间 health: starting

检查：

```bash
docker logs --tail 200 xymedia-app
docker inspect xymedia-app --format '{{json .State.Health}}'
df -h /
```

Title 首次解压需要额外磁盘空间。建议安装盘至少保留 20GB 可用空间。

## Release 验证

每个正式 Release 包含：

```text
bootstrap.sh
install.sh
compose.yaml
compose.fuse.yaml
config.yaml
manifest-v1.json
manifest-v1.json.sig
manifest-v1.pem
SHA256SUMS
upgrade-from-bundled.sh
uninstall.sh
recovery.md
```

Release 资产和多架构镜像在发布流程中经过测试、SHA-256 校验和 Cosign OIDC 签名。

## 相关文档

- [GitHub Releases](https://github.com/iceqi/xymediavault/releases)
- [使用说明](docs/USAGE.md)
- [安装脚本](scripts/)
