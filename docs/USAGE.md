# XyMediaVault v1.4.0 使用说明

完整的安装、升级、FUSE、备份和排障说明请阅读 [README](../README.md)。本公开仓库只提供安装入口、文档和 Release 资产，不包含应用源码。

## 安装入口

当前稳定版本是 `v1.4.0`。生产环境使用固定 Release bootstrap：

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  'https://gh-proxy.org/https://github.com/iceqi/xymediavault/releases/download/v1.4.0/bootstrap.sh' \
  | sh -s -- v1.4.0
```

本仓库的 `scripts/install.sh` 只是 HTTPS Release bootstrap 转发器，不实现部署；默认版本为 `v1.4.0`。它只接受一个可选版本参数，并支持 `XYMEDIA_RELEASE`。版本必须是 `vX.Y.Z` 或 `vX.Y.Z-beta.N`。

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

默认精确锁定 Title `component-sha-007ed892afaf` 和 TMM `component-sha-61e9e46df421`，并锁定各架构资产及 SHA-256。这些私有 GitHub Release 必须先设置 `GH_TOKEN` 或 `GITHUB_TOKEN`；脚本不会打印 token。首次操作应先运行 `--dry-run`，真正写入必须显式提供 `--yes`。

脚本会先下载并验证两个归档，再停止应用。它要求 `.env` 中的 `XYMEDIA_APP_CONTAINER`（缺省 `xymedia-app`）、`/app/components` named volume、本地 `alpine:3.22`，并仅重启该应用容器；不支持 bind/anonymous volume。备份位于 volume 的 `.xymedia-component-backups/时间戳/`。应用容器健康检查失败时会尝试恢复选中归档并重启，但脚本无法替代组件业务健康检查，请再检查管理后台。

Release 资产包括 `bootstrap.sh`、`install.sh`、`compose.yaml`、`compose.fuse.yaml`、`config.yaml`、`manifest-v1.json`、`SHA256SUMS`、`upgrade-from-bundled.sh`、`remount-fuse.sh`、`uninstall.sh`、`recovery.md` 和 `verify-release.sh`。没有 manifest 的 `.sig` 或 `.pem` 资产。安装器验证 SHA256SUMS、manifest 资产哈希及精确 manifest 标签绑定，但不验证 manifest Cosign provenance，也不把 SHA-256 校验称为发布者验证。
