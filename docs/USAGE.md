# XyMediaVault 使用速查

完整安装、功能、备份和排障说明请阅读仓库根目录的 [README](../README.md)。

## 支持范围

- Docker 与 Docker Compose V2，或旧式 `docker-compose`。
- `linux/amd64`、`linux/arm64`。
- 镜像内置 PostgreSQL 17、TMM 和 Title。
- PostgreSQL 版本仅支持全新安装，不迁移旧 SQLite 数据。

检测到 `.db`、`.db-wal`、`.db-shm` 或 SQLite 配置时，安装器会停止操作，不会删除
旧数据。请保留旧安装目录，在新的空目录安装。

## 稳定版安装

推荐先下载脚本并检查：

```bash
mkdir -p "$HOME/XyMediaVault"
cd "$HOME/XyMediaVault"
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh -o install.sh
sh install.sh
```

无交互环境可以使用：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh |
  sh -s -- vault install --channel stable --non-interactive --dir /opt/xymediavault
```

稳定通道使用 `iceqi/xymediavault:latest`。需要测试通道时，把 `stable` 改为 `beta`；
切换前先完成完整备份。

## 常用命令

```bash
bash scripts/install.sh vault check --dir /opt/xymediavault
bash scripts/install.sh vault upgrade --channel stable --dir /opt/xymediavault --yes
bash scripts/install.sh vault switch --channel beta --dir /opt/xymediavault --yes
bash scripts/install.sh status --json
```

查看状态和日志：

```bash
cd /opt/xymediavault
docker compose ps
docker compose logs --tail=200 xymediavault
curl -fsS http://127.0.0.1:18080/api/health
```

旧环境可将 `docker compose` 替换为 `docker-compose`。

## 默认访问地址

```text
管理后台：http://服务器IP:18080
WebDAV：http://服务器IP:18081/dav
TVBox：http://服务器IP:18082
小雅 Alist：http://服务器IP:5678
```

## 数据安全

不要复制运行中的 `data/postgres/` 作为备份，也不要删除或覆盖其中的文件。正式支持的
恢复路径是停止整个 Compose 项目后，完整备份和恢复安装目录。具体命令和 PostgreSQL
逻辑导出范围见 [README 的数据备份与迁移章节](../README.md#数据备份与迁移)。

`data/postgres-secrets/`、`xiaoya/`、数据库导出、TVBox 令牌和 WebDAV 密码均属于
敏感数据。PostgreSQL 默认不映射宿主端口，不要将 `5432` 暴露到公网。
