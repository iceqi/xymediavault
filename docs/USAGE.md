# XyMediaVault v1.4.0 使用说明

完整的安装、升级、FUSE、备份和排障说明请阅读 [README](../README.md)。本公开仓库只提供安装入口、文档和 Release 资产，不包含应用源码。

## 安装入口

当前稳定版本是 `v1.4.0`。生产环境在交互式终端中使用公开安装入口，菜单提供：`1` 安装或升级应用、`2` 更新 Title/TMM 组件、`3` 仅生成 Compose 配置（不创建容器）、`4` 迁移组件存储到宿主机目录、`5` 全新重置安装、`6` 退出：

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  'https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/817a5e9a571cab4edec35d4735f2f1495ca977d1/scripts/install.sh' \
  | sh
```

以上是绑定提交 `817a5e9a571cab4edec35d4735f2f1495ca977d1` 的固定公共安装入口，用于绕过浮动 `/main/` 的缓存。

本仓库的 `scripts/install.sh` 是 HTTPS Release bootstrap 转发器，也提供交互式入口菜单。在可读写的交互式终端中不带参数运行时，可选择安装或升级应用、更新 Title/TMM 组件、仅生成 Compose 配置、迁移组件存储，或执行全新重置安装；没有 TTY、传入版本、设置 `XYMEDIA_RELEASE` 或 `XYMEDIA_COMMAND` 时直接执行默认的 `v1.4.0` bootstrap。选择 `3` 会复用精确的 `v1.4.0` Release bootstrap，仅生成或更新 Compose 配置，不调用 Docker、不创建或改变容器，也不创建或改变 FUSE 状态。当前已发布菜单的 reset pin 仍待新 helper 提交后更新；更新后的菜单会提示 Compose 项目名并执行两次确认，重置取消或失败时不会启动 bootstrap，成功后才以 `XYMEDIA_COMMAND=install` 启动 v1.4.0 全新安装。它只接受一个可选版本参数；版本必须是 `vX.Y.Z` 或 `vX.Y.Z-beta.N`。

安装和 Compose-only 菜单项会提示安装目录；路径含非 ASCII 字节时会先选择已验证的 UTF-8 locale，再启动 bootstrap。若当前 locale、`C.UTF-8`、`en_US.UTF-8` 和系统枚举的 UTF-8 locale 均不可用，会显示“系统缺少 UTF-8 locale，无法安全处理中文路径。”并在 bootstrap 前退出。

组件更新会先执行不改变 Docker 状态的预检，确认后才停止并重启应用容器。组件存储迁移会先执行不改变 Docker 状态的预检，只有用户确认后才执行 v1.4.0 布局迁移，原 named volume 会保留。公开 wrapper 的 bootstrap 下载默认使用 `https://gh-proxy.org/`；设置 `XYMEDIA_DOWNLOAD_PROXY=''` 可直连 GitHub，非空值必须是 HTTPS。菜单会显示外层 bootstrap 的下载和启动阶段；启动后，发布的 `v1.4.0` bootstrap 仍会自行校验并下载安装器，该内层步骤不保证显示字节进度。

## 安装模式

交互式运行会显示安装菜单，默认不启用 FUSE。非交互 `install` 必须明确设置 `XYMEDIA_FUSE_MODE`，可选 `none` 或 `host-media`：

```bash
XYMEDIA_COMMAND=install XYMEDIA_INSTALL_DIR=/opt/xymedia \
XYMEDIA_FUSE_MODE=none sh bootstrap.sh v1.4.0
```

使用宿主机媒体目录时，指定绝对路径并启用 `host-media` 模式：

```bash
XYMEDIA_COMMAND=install XYMEDIA_INSTALL_DIR=/opt/xymedia \
XYMEDIA_FUSE_MODE=host-media XYMEDIA_FUSE_HOST_PATH=/srv/media \
sh bootstrap.sh v1.4.0
```

`host-media` 模式需要 `/dev/fuse`、绝对路径的 `XYMEDIA_FUSE_HOST_PATH` 以及受信任宿主机上的相应 Docker 权限。仅生成配置而不操作运行环境：

```bash
XYMEDIA_COMMAND=compose-only XYMEDIA_INSTALL_DIR=/opt/xymedia \
sh bootstrap.sh v1.4.0
```

`compose-only` 默认使用 `none`，不需要提供 `XYMEDIA_FUSE_MODE`。该模式不调用 Docker，不创建或改变容器，也不创建或改变 FUSE 状态。

## 升级与维护

非交互升级必须显式使用 `XYMEDIA_COMMAND=upgrade`：

```bash
XYMEDIA_COMMAND=upgrade XYMEDIA_INSTALL_DIR=/opt/xymedia \
XYMEDIA_FUSE_MODE=none sh bootstrap.sh v1.4.0
```

替换前，安装器会安全卸载已识别的受管理 FUSE 挂载。维护脚本必须从 [v1.4.0 Release](https://github.com/iceqi/xymediavault/releases/tag/v1.4.0) 获取：`remount-fuse.sh` 用于重新挂载，`upgrade-from-bundled.sh` 用于 bundled PostgreSQL 升级，`uninstall.sh` 用于卸载。

## 支持与数据安全

- 支持 `linux/amd64` 和 `linux/arm64`，需要 Docker Compose V2。
- 默认地址：管理后台 `18080`、WebDAV `18081/dav`、TVBox `18082`、小雅 Alist `5678`。
- 不要执行 `docker compose down -v`，除非要永久删除数据库和全部状态。
- PostgreSQL 默认不映射宿主机 `5432`，不要将其暴露到公网。
- FUSE 出现 `transport endpoint is not connected` 时，使用固定 Release 的 `remount-fuse.sh`。

## 组件维护

使用公开仓库中的 `scripts/update-components.sh` 更新已安装实例的 Title 或 TMM，不需要重新编译或发布 XyMediaVault 应用：

```bash
sh scripts/update-components.sh --install-dir /opt/xymedia --component title --dry-run
sh scripts/update-components.sh --install-dir /opt/xymedia --component tmm --yes
sh scripts/update-components.sh --install-dir /opt/xymedia --component all --yes
```

默认通过 `https://gh-proxy.org/` 获取公开 [iceqi/xymedia-components Releases](https://github.com/iceqi/xymedia-components/releases) 的固定资产；设置 `XYMEDIA_DOWNLOAD_PROXY=` 可直连 GitHub。非空代理必须为 HTTPS，且仅用于固定 Release URL，不查询 API 或 `latest`，也不能覆盖仓库或 tag。当前精确锁定 Title `title-component-sha-ab7f33d6ede5`（[Release](https://github.com/iceqi/xymedia-components/releases/tag/title-component-sha-ab7f33d6ede5)）和 TMM `tmm-component-sha-a0206a51fd9e`（[Release](https://github.com/iceqi/xymedia-components/releases/tag/tmm-component-sha-a0206a51fd9e)），包括各架构资产及 SHA-256。首次操作应先运行 `--dry-run`，真正写入必须显式提供 `--yes`。

脚本会先显示下载阶段并验证归档，再停止应用；Title 大归档的预检会持续输出阶段信息，并在一次受控解压后批量验证约 5032 个 payload 文件。任何校验失败都不会改变 Docker 状态。它要求 `.env` 中的 `XYMEDIA_APP_CONTAINER`（缺省 `xymedia-app`）、本地 `alpine:3.22`，并支持带精确 Compose 标签的旧 named volume或迁移后的 canonical bind mount `$XYMEDIA_INSTALL_DIR/components`；不创建 components 目录。备份位于所选存储的 `.xymedia-component-backups/时间戳/`。应用容器健康检查失败时会尝试恢复选中归档并重启，但脚本无法替代组件业务健康检查，请再检查管理后台。

## 迁移组件存储

组件从 named volume 迁移到宿主机目录必须显式执行，并先进行 dry-run：

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/iceqi/xymediavault/9fa0ed12a8547895f44ecea036bf5558053798c2/scripts/migrate-components-storage.sh \
  -o migrate-components-storage.sh
sh migrate-components-storage.sh --install-dir /opt/xymedia --dry-run
sh migrate-components-storage.sh --install-dir /opt/xymedia --yes
```

脚本只接受当前 Compose 项目管理的 `components` volume，目标固定为安装目录下的 `components`，目标目录为应用可读写的 `0755`，并保留旧 volume、备份和 compose 顶层 `components:` 定义。复制、递归校验或候选 Compose 校验失败时应用保持运行；切换后必须为 `healthy`，否则恢复原 named volume 配置。已迁移实例可继续使用上面的组件更新命令。

Release 资产包括 `bootstrap.sh`、`install.sh`、`compose.yaml`、`compose.fuse.yaml`、`config.yaml`、`manifest-v1.json`、`SHA256SUMS`、`upgrade-from-bundled.sh`、`remount-fuse.sh`、`uninstall.sh`、`recovery.md` 和 `verify-release.sh`。没有 manifest 的 `.sig` 或 `.pem` 资产。安装器验证 SHA256SUMS、manifest 资产哈希及精确 manifest 标签绑定，但不验证 manifest Cosign provenance，也不把 SHA-256 校验称为发布者验证。
交互菜单仅在可读写 TTY 中清屏并显示；组件更新和迁移目录提示留空时使用当前工作目录，无法安全规范化时回退 `/opt/xymedia`。长操作显示编号阶段，非交互和日志使用逐行输出，不保证精确下载百分比。

全新重置 helper 独立使用 `sh scripts/reset-fresh-install.sh --install-dir /opt/xymedia --project xymedia`，不要求 `.env` 或 `compose.yaml` 存在。项目名必须匹配 ASCII `^[a-z0-9][a-z0-9_-]{0,62}$`；菜单后续版本会在安装目录提示后传入项目名，留空默认值为 `xymedia`。helper 只使用精确 Docker 标签 `com.docker.compose.project=$PROJECT` 发现容器、named volume 和网络，列出全部候选后要求输入 `RESET $PROJECT` 和 `y/Y` 两次确认，再逐项复核标签并停止、非 force 删除容器，删除卷和网络。它不使用 Compose YAML、`docker compose`、`down -v`、prune、名称通配或未由标签发现的资源；没有资源时仍执行相同确认流程。Docker 删除成功后才逐项移动现有 `.env`、Compose、配置及 Release 控制文件到备份目录；`media`、`xiaoya`、`components` 和其他宿主机数据始终保留。取消或失败不会启动 bootstrap。该流程可用于安装失败后 Compose 文件已回滚或删除的目录，且 Docker 数据删除不可逆。
