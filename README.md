# XyMediaVault

XyMediaVault 面向小雅 Alist、Emby、Jellyfin、Infuse 和 TVBox，提供媒体索引、只读 WebDAV、媒体视图、TVBox CMS、小雅授权与组件运行管理。

本仓库是公开的安装与文档仓库，不包含应用源码。当前稳定 Release 为 `v1.4.0`；私有源仓库负责应用开发与发布，`iceqi/xymediavault` 负责用户安装入口和公开 Release 资产。

## v1.4.0 快速安装

生产环境在交互式终端中使用公开安装入口，菜单提供：`1` 安装或升级应用、`2` 更新 Title/TMM 组件、`3` 仅生成 Compose 配置（不创建容器）、`4` 迁移组件存储到宿主机目录、`5` 全新重置安装、`6` 退出：

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  'https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh' \
  | sh
```

该入口默认转发到 `v1.4.0`，支持一个明确的 `vX.Y.Z` 或 `vX.Y.Z-beta.N` 参数。显式传入版本、设置 `XYMEDIA_RELEASE`、设置 `XYMEDIA_COMMAND` 或没有可用 TTY 时，会跳过外层菜单并进入固定 Release bootstrap：

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh \
  | sh -s -- v1.4.0
```

菜单需要可读写的交互式终端；通过管道运行且没有 TTY 时会直接执行默认的 `v1.4.0` bootstrap。选择 `3` 会复用精确的 `v1.4.0` Release bootstrap，仅生成或更新 Compose 配置，不调用 Docker、不创建或修改容器，也不创建或修改 FUSE 状态。组件更新会先执行不改变 Docker 状态的预检，确认后才停止并重启应用容器。选择 `4` 会下载固定提交中的迁移脚本，只有预检成功并明确确认后才执行 v1.4.0 布局迁移；原 named volume 会保留。选择 `5` 会下载固定提交中的重置脚本，由该脚本完成两次确认并删除精确 Compose 项目的 Docker 数据；只有重置成功后才启动精确的 v1.4.0 全新安装。

安装器会下载固定 Release 的 `bootstrap.sh`，再由 Release 安装器完成配置和部署。默认安装不启用 FUSE。交互式安装会显示菜单；非交互式 `install` 必须明确设置 `XYMEDIA_FUSE_MODE`，可选 `none` 或 `host-media`。

### 非交互式安装

```bash
XYMEDIA_COMMAND=install \
XYMEDIA_INSTALL_DIR=/opt/xymedia \
XYMEDIA_FUSE_MODE=none \
sh bootstrap.sh v1.4.0
```

需要把指定的宿主机目录作为媒体库挂载源时，必须显式提供目录：

```bash
XYMEDIA_COMMAND=install \
XYMEDIA_INSTALL_DIR=/opt/xymedia \
XYMEDIA_FUSE_MODE=host-media \
XYMEDIA_FUSE_HOST_PATH=/srv/media \
sh bootstrap.sh v1.4.0
```

`host-media` 模式需要宿主机存在 `/dev/fuse`，`XYMEDIA_FUSE_HOST_PATH` 必须是绝对路径，并会授予应用容器 FUSE 所需的设备和权限。只使用管理后台、WebDAV 或 TVBox 时请选择 `none`。FUSE 仅应在受信任的宿主机启用。

### 仅生成 Compose 配置

```bash
XYMEDIA_COMMAND=compose-only \
XYMEDIA_INSTALL_DIR=/opt/xymedia \
sh bootstrap.sh v1.4.0
```

`compose-only` 默认使用 `none`，不需要提供 `XYMEDIA_FUSE_MODE`。它只生成或更新安装配置，不调用 Docker，不创建或改变容器，也不创建或改变 FUSE 状态。完成检查和人工确认后，再执行常规安装命令。

菜单中的安装和 Compose-only 流程会提示安装目录。路径含非 ASCII 字节时，入口会选择已验证的 UTF-8 locale 后再启动 v1.4.0 bootstrap；如果系统没有 UTF-8 locale，会在启动前拒绝执行。路径不含非 ASCII 字节时保持原有行为。

## 升级

升级必须显式使用 `XYMEDIA_COMMAND=upgrade`，尤其是在非交互环境：

```bash
XYMEDIA_COMMAND=upgrade \
XYMEDIA_INSTALL_DIR=/opt/xymedia \
XYMEDIA_FUSE_MODE=none \
sh bootstrap.sh v1.4.0
```

升级会保留 PostgreSQL 数据卷、数据库密码、应用状态、小雅数据和更新备份；替换前会安全卸载安装器识别的、由 XyMediaVault 管理的 FUSE 挂载。无法识别的用户挂载不会被安装器擅自卸载，请先按 [恢复说明](https://github.com/iceqi/xymediavault/releases/download/v1.4.0/recovery.md) 处理。

需要维护已安装实例时，请直接使用同一 Release 的固定资产：

- [remount-fuse.sh](https://github.com/iceqi/xymediavault/releases/download/v1.4.0/remount-fuse.sh)：重新挂载受管理的 FUSE；
- [upgrade-from-bundled.sh](https://github.com/iceqi/xymediavault/releases/download/v1.4.0/upgrade-from-bundled.sh)：按说明迁移 bundled PostgreSQL；
- [uninstall.sh](https://github.com/iceqi/xymediavault/releases/download/v1.4.0/uninstall.sh)：卸载并按提示选择是否清理数据。

## 默认端口与检查

| 服务 | 端口 | 地址 |
| --- | ---: | --- |
| 管理后台 | 18080 | `http://服务器IP:18080` |
| WebDAV | 18081 | `http://服务器IP:18081/dav` |
| TVBox | 18082 | `http://服务器IP:18082` |
| 小雅 Alist | 5678 | `http://服务器IP:5678` |

```bash
cd /opt/xymedia
curl -fsS http://127.0.0.1:18080/api/health
```

不要执行 `docker compose down -v`，除非明确要永久删除数据库和全部状态。

## v1.4.0 Release 资产

固定 Release 包含以下公开资产：

```text
bootstrap.sh
install.sh
compose.yaml
compose.fuse.yaml
config.yaml
manifest-v1.json
SHA256SUMS
upgrade-from-bundled.sh
remount-fuse.sh
uninstall.sh
recovery.md
verify-release.sh
```

安装器会使用 `SHA256SUMS` 和 manifest 中的资产哈希，并检查 manifest 绑定的 Release 标签是否为请求的精确版本。该流程不验证 manifest 的 Cosign provenance；`SHA256SUMS` 也不代表发布者身份验证。不要设置已废弃的 `XYMEDIA_SKIP_SIGNATURE_VERIFY`，它会被公开转发器拒绝。

下载可通过 `XYMEDIA_DOWNLOAD_PROXY` 配置代理；组件 Release 资产默认使用 `https://gh-proxy.org/`，设置为空值可直连 GitHub。非空代理必须是 HTTPS，且只会用于本脚本内置的固定 GitHub Release 资产，不支持通过环境变量改变仓库或 tag。生产环境仍应使用 HTTPS。

## 相关链接

- [v1.4.0 Release](https://github.com/iceqi/xymediavault/releases/tag/v1.4.0)
- [使用说明](docs/USAGE.md)
- [安装脚本](scripts/install.sh)

## 更新 Title/TMM 组件

已安装的 v1.4.0 实例可以在不发布新应用版本的情况下替换组件归档。脚本只使用内置的精确 tag、资产名和 SHA-256，不查询 `latest` 或其他浮动版本；默认支持 `linux/amd64` 和 `linux/arm64`。

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/iceqi/xymediavault/df4e1ec94fd05e7921c617f32cce83a0224e0fee/scripts/update-components.sh \
  -o update-components.sh
sh update-components.sh --install-dir /opt/xymedia --component title --dry-run
sh update-components.sh --install-dir /opt/xymedia --component title --yes
```

`--component` 可选 `title`、`tmm` 或 `all`。脚本从公开的 [xymedia-components Releases](https://github.com/iceqi/xymedia-components/releases) 获取固定资产，不查询 API 或 `latest`。当前锁定 Title `title-component-sha-ab7f33d6ede5`（[Release](https://github.com/iceqi/xymedia-components/releases/tag/title-component-sha-ab7f33d6ede5)）和 TMM `tmm-component-sha-a0206a51fd9e`（[Release](https://github.com/iceqi/xymedia-components/releases/tag/tmm-component-sha-a0206a51fd9e)）。需要变更锁时，使用经过人工审阅的绝对路径 JSON `--lock-file`，不要通过仓库或 tag 环境变量覆盖。默认使用 `https://gh-proxy.org/`，设置 `XYMEDIA_DOWNLOAD_PROXY=` 可直连 GitHub；非空值必须为 HTTPS，且仅用于这些固定 Release 资产。

更新前会显示归档和 checksum 下载进度，并完成归档 checksum、zstd/tar 路径、manifest 和 payload 校验；大型 Title 归档会在预检阶段耗时，但只解压一次后批量校验，不会重复扫描归档。`all` 在两者都通过前不会停止应用。脚本只接受 `.env` 中的 `XYMEDIA_APP_CONTAINER`（默认 `xymedia-app`），要求 `/app/components` 是 named Docker volume，并只停止/启动应用容器。替换前的组件归档保存在该 volume 的 `.xymedia-component-backups/` 下。脚本要求本地已有 `alpine:3.22`，不会在维护窗口自动拉取镜像。

脚本不能可靠判断组件自身的业务健康状态；完成后请检查管理后台。更新器同时支持带精确 Compose 标签的旧 named volume 和迁移后的 `$XYMEDIA_INSTALL_DIR/components` canonical bind mount；不会创建 components 目录。anonymous volume、外部 bind、非支持架构或没有本地 helper 镜像时会拒绝执行。

## 迁移组件存储

v1.4.0 的组件默认位于 Docker named volume。需要宿主机可见目录时，先下载公开迁移脚本并执行 dry-run，再显式确认迁移：

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/iceqi/xymediavault/9fa0ed12a8547895f44ecea036bf5558053798c2/scripts/migrate-components-storage.sh \
  -o migrate-components-storage.sh
sh migrate-components-storage.sh --install-dir /opt/xymedia --dry-run
sh migrate-components-storage.sh --install-dir /opt/xymedia --yes
```

迁移只接受 Compose 管理且标签精确匹配的 `components` volume，目标固定为 `/opt/xymedia/components`（即安装目录下的 `components`）；目标目录使用应用可读写的 `0755`，备份目录使用 `0700`。保留原 named volume、迁移备份和顶层 `components:` 定义，不执行删除。迁移前会验证候选 Compose 配置，失败或复制校验失败时不会停止应用；切换后的应用必须达到 `healthy`，否则会恢复原配置并启动旧 named volume。迁移完成后继续使用组件更新脚本即可。
交互菜单仅在可读写 TTY 中清屏并显示；组件更新和迁移目录提示留空时使用当前工作目录，无法安全规范化时回退 `/opt/xymedia`。长操作显示编号阶段，TTY 使用更新中的一行，非交互和日志使用逐行输出，不保证精确下载百分比。

菜单 `5` 会下载并执行固定 SHA `b42c25467de718575f68230edfb7947f467db915` 的 `scripts/reset-fresh-install.sh`。它要求 `RESET <project>` 与 `y/Y` 两次确认，只处理 `.env` 中精确 `COMPOSE_PROJECT_NAME` 标签对应的容器、named volume 和网络；删除前会备份受控 Release 文件，不删除 `media`、`xiaoya`、`components` 或其他宿主机数据。取消或失败都不会启动 bootstrap；成功后才自动启动精确的 v1.4.0 全新安装。Docker 数据删除不可逆，应用数据删除后无法回滚；宿主机媒体、xiaoya 和 components 保留。
