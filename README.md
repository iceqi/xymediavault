# XyMediaVault

XyMediaVault 是面向小雅 Alist、Emby、Jellyfin 和 TVBox 的媒体资源管理服务，提供媒体索引、WebDAV、媒体库挂载、TVBox 接口、小雅授权管理和 Emby 容器管理等能力。

> 本项目为闭源软件。请通过官方镜像和安装脚本部署，未经授权不提供源码再分发。

> **重要：当前版本使用镜像内置的 PostgreSQL 17，仅支持全新安装。**
> 检测到旧 SQLite `.db`、`.db-wal` 或 `.db-shm` 文件时，安装器和容器都会停止启动。
> 旧数据不会被删除，也不会自动迁移。请保留原安装目录，并在新的空目录部署 PostgreSQL 版本。

官方镜像支持 `linux/amd64` 和 `linux/arm64`。稳定部署使用
`iceqi/xymediavault:latest`；`iceqi/xymediavault:beta` 是显式选择的测试通道。

## 文档导航

- [快速开始](#快速开始)
- [镜像通道](#镜像通道)
- [手动部署](#手动部署)
- [更新](#更新)
- [首次使用](#首次使用)
- [数据备份与迁移](#数据备份与迁移)
- [高级排障：只读查看 PostgreSQL](#高级排障只读查看-postgresql)
- [常见问题](#常见问题)

## 主要功能

- 扫描媒体目录并建立本地索引，减少媒体服务器重复访问远程目录。
- 使用媒体视图组合和整理多个索引目录，并批量添加目录来源。
- 提供只读 WebDAV，供 Emby、Jellyfin、Infuse 等客户端挂载。
- 提供单一全局媒体库挂载，可在索引目录和媒体视图两种模式间切换。
- 提供 TVBox JSON CMS 服务、独立用户、设备令牌和目录权限。
- 托管小雅 Alist 的授权、状态、启停、重启和实时日志。
- 可选安装并管理 Emby，包括更新、启停、重启和实时日志。
- 支持多个同构索引源，源站不可用时自动切换。
- 支持定时更新媒体索引、STRM 播放地址和可选元数据补全。

官方镜像内置 TMM 与 Title。普通安装不需要下载或管理组件包。安装目录中的
`components/` 仅供高级用户在重启时覆盖组件；覆盖包必须与宿主架构匹配，并在
替换前校验 SHA-256：

```text
components/tmm.tar.zst
components/title.tar.zst
```

覆盖包只在重启时应用，不提供在线上传、下载或 reload 操作。当前 Release 资产使用
SHA-256 完整性校验，尚未配置签名公钥，不能将 checksum 等同于官方签名验证。

## 支持环境

- 已安装并启动 Docker。
- 已安装 Docker Compose V2 或 `docker-compose`。
- 支持 `linux/amd64`、`linux/arm64`。
- 安装脚本会自动检测媒体库挂载能力；使用本地挂载时，宿主机需要支持 FUSE、`/dev/fuse` 和共享挂载传播。
- 建议预留管理后台、WebDAV、TVBox 和小雅 Alist 所需端口。

下文统一使用 Compose V2 命令 `docker compose`。如果系统只安装了旧式独立命令，
可以将示例中的 `docker compose` 替换为 `docker-compose`；官方安装脚本会自动识别二者。

默认端口：

| 服务 | 默认端口 | 默认地址 |
| --- | ---: | --- |
| 管理后台 | 18080 | `http://服务器IP:18080` |
| WebDAV | 18081 | `http://服务器IP:18081/dav` |
| TVBox | 18082 | `http://服务器IP:18082` |
| 小雅 Alist | 5678 | `http://服务器IP:5678` |

## 快速开始

推荐先下载并检查安装脚本，再执行：

```bash
mkdir -p "$HOME/XyMediaVault"
cd "$HOME/XyMediaVault"
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh -o install.sh
sh install.sh
```

也可以使用一键命令。该命令会从网络下载并立即执行脚本，生产环境使用前应确认下载来源：

```bash
mkdir -p "$HOME/XyMediaVault"
cd "$HOME/XyMediaVault"
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh
```

安装器默认使用稳定镜像 `iceqi/xymediavault:latest`，并等待 PostgreSQL 和应用健康检查
通过后才输出访问地址。安装完成后访问：

```text
管理后台：http://服务器IP:18080
WebDAV：http://服务器IP:18081/dav
TVBox：http://服务器IP:18082
```

可以在服务器本机验证：

```bash
curl -fsS http://127.0.0.1:18080/api/health
docker compose ps
```

如果安装器等待超时，在安装目录执行：

```bash
docker compose logs --tail=200 xymediavault
```

## 镜像通道

| 标签 | 用途 | 建议 |
| --- | --- | --- |
| `iceqi/xymediavault:latest` | 稳定通道 | 新安装和生产环境默认使用 |
| `iceqi/xymediavault:beta` | 测试通道 | 提前验证新功能，切换前先备份 |

两个通道都提供 `linux/amd64` 和 `linux/arm64` 镜像，并内置 PostgreSQL 17、TMM
和 Title。应用内自更新在 bundled PostgreSQL 模式下关闭；更新必须通过安装脚本或
Docker Compose 替换镜像。

## 安装参数

不指定目录时，安装目录严格使用执行命令时的当前目录。脚本不会默认安装到 `/opt`，也不会读取环境中的 `INSTALL_DIR` 作为默认路径。

例如，希望安装到当前用户的 `XyMediaVault` 目录：

```bash
mkdir -p "$HOME/XyMediaVault"
cd "$HOME/XyMediaVault"
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh
```

### 指定安装目录

一键命令可以把目录作为第一个参数传给脚本：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh -s -- /指定目录
```

也可以先下载脚本：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh -o install.sh
sh install.sh /指定目录
```

相对目录会基于当前执行目录转换为绝对路径。

### 交互选项

脚本会交互询问以下内容，直接按回车使用显示的默认值：

- 安装目录
- Docker 镜像
- 服务器访问 IP 或域名
- 管理后台端口
- WebDAV 端口
- TVBox 服务端口
- 小雅 Alist、管理和代理端口
- 是否强制拉取最新镜像

脚本自动识别 Docker 服务器架构并拉取对应的 `iceqi/xymediavault:latest` 镜像，同时自动检测媒体库挂载能力。首次安装检测可用时会自动挂载，之后可在管理后台控制。

## 手动部署

不希望执行 `install.sh` 时，可以手动创建配置文件和 Compose 文件。下面示例使用
稳定镜像，包含管理后台、WebDAV、TVBox、小雅 Alist、Docker 容器管理和可选 FUSE
媒体库挂载所需的完整配置。

> 该完整示例挂载 Docker Socket，并包含 `/dev/fuse`、`SYS_ADMIN` 和
> `apparmor:unconfined`。它适合需要托管小雅/Emby 和本地媒体挂载的部署。
> 只使用索引、WebDAV 或 TVBox 时，请按后文删除 FUSE 权限；不需要容器管理时也应
> 移除 Docker Socket 挂载。

先创建安装目录：

```bash
mkdir -p "$HOME/XyMediaVault"/{data,xiaoya/data,emby/config,tmm/data,mnt/xymediavault}
cd "$HOME/XyMediaVault"
```

创建 `config.yaml`：

```yaml
server:
  host: 0.0.0.0
  port: 8080
  web_dir: /app/web/dist

database:
  driver: postgres
  host: /var/run/postgresql
  port: 5432
  name: xymedia
  user: xymedia_app
  password_file: /app/data/postgres-secrets/app-password
  sslmode: disable

virtual:
  enable_remote_file_mapping: false

webdav:
  enabled: true
  listen_addr: 0.0.0.0
  port: 8081
  public_port: 18081
  base_path: /dav
  read_only: true

tvbox:
  enabled: true
  listen_addr: 0.0.0.0
  port: 8082
  public_port: 18082
  # 换成其他设备可以访问的服务器 IP 或域名。
  public_url: http://192.168.1.10:18082
  token_key_file: /app/data/tvbox-token.key

cache:
  directory: /app/data/cache

fuse:
  # Compose 已包含 FUSE 权限，但建议首次登录后台确认路径后再启用挂载。
  auto_mount: false
  mount_path: /mnt/xymediavault

xiaoya:
  config_dir: /app/xiaoya
  container_name: xiaoya-alist
  internal_url: http://xiaoya-alist:80
  # 换成客户端可以访问的小雅地址。
  public_url: http://192.168.1.10:5678
  docker_socket: /var/run/docker.sock

log:
  level: info
```

创建 `docker-compose.yml`：

```yaml
name: xymediavault

services:
  xymediavault:
    image: iceqi/xymediavault:latest
    container_name: xymediavault
    restart: unless-stopped
    stop_grace_period: 15s
    depends_on:
      xiaoya-alist:
        condition: service_started
    environment:
      TZ: Asia/Shanghai
      XYMEDIA_COMPONENT_RUNTIME: local
      XYMEDIAVAULT_FUSE_HOST_PATH: ${PWD}/mnt/xymediavault
      XYMEDIAVAULT_XIAOYA_HOST_PATH: ${PWD}/xiaoya
      XYMEDIAVAULT_EMBY_HOST_PATH: ${PWD}/emby
    ports:
      - "18080:8080"
      - "18081:8081"
      - "18082:8082"
    volumes:
      - ./data:/app/data
      - ./config.yaml:/app/config.yaml:ro
      - ./xiaoya:/app/xiaoya
      - ./tmm:/app/tmm
      - ./components:/app/components
      - /var/run/docker.sock:/var/run/docker.sock
      - type: bind
        source: ./mnt/xymediavault
        target: /mnt/xymediavault
        bind:
          propagation: rshared
    devices:
      - /dev/fuse:/dev/fuse
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

  xiaoya-alist:
    image: xiaoyaliu/alist:latest
    container_name: xiaoya-alist
    restart: unless-stopped
    ports:
      - "5678:80"
      - "2345:2345"
      - "2346:2346"
    volumes:
      - ./xiaoya:/data
      - ./xiaoya/data:/www/data
```

将 `config.yaml` 中的 `192.168.1.10` 改为服务器实际 IP 或域名，然后检查并启动：

```bash
docker compose config
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 xymediavault
```

默认 Compose 文件拉取已经内置 TMM 与 Title 的发布镜像，不从本地源码构建。
开发者只有在 `components/tmm.tar.zst` 与对应架构的
`components/title.tar.zst` 已准备完成后，才应直接使用 `docker/Dockerfile`
构建镜像。

打开 `http://服务器IP:18080` 创建管理员账号。更新稳定镜像时执行：

```bash
docker compose pull
docker compose up -d
```

### 不使用 FUSE 挂载

如果宿主机没有 `/dev/fuse`、不允许 `SYS_ADMIN`，或只使用 WebDAV/TVBox，请从 `xymediavault` 服务中删除以下内容：

```yaml
    devices:
      - /dev/fuse:/dev/fuse
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
```

同时删除 `/mnt/xymediavault` 对应的 bind volume。WebDAV、TVBox、索引和媒体视图仍可正常使用，但本地媒体库挂载不可用。

`./tmm` 仅保存内置 TMM 的配置、许可证和运行数据，普通安装不需要单独拉取或管理 TMM/Title 容器。

> `docker.sock` 允许 XyMediaVault 安装和管理小雅、Emby，等同于授予容器较高的宿主机 Docker 权限。当前 bundled PostgreSQL 模式禁用应用内自更新；请按备份和替换镜像流程更新。

## 更新

安装和更新使用同一个脚本。在原安装目录执行一键安装命令，脚本检测到 `docker-compose.yml` 后会进入更新流程：

```bash
cd /你的/XyMediaVault/安装目录
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh
```

也可以在任意目录显式指定已有安装目录：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh -s -- /你的/XyMediaVault/安装目录
```

更新过程会保留 PostgreSQL 数据目录、系统配置、小雅授权文件和 Emby 配置。旧 SQLite 目录会被拒绝且不会删除或迁移。

手动 Compose 部署可以执行：

```bash
docker compose pull
docker compose up -d
curl -fsS http://127.0.0.1:18080/api/health
```

更新前建议完成冷备份。不要只复制运行中的 `data/postgres/` 子目录，也不要在容器运行时
删除或替换 PostgreSQL 数据文件。

## 首次使用

1. 打开 `http://服务器IP:18080`。
2. 注册并登录管理员账号。
3. 按首次设置窗口完成小雅普通 Token、Open Token 和转存目录配置。
4. 转存目录默认显示 `root`，可以按实际需要修改。
5. 配置完成后系统会重启小雅容器。
6. 进入“小雅资源”浏览远程目录，选择目录并加入媒体索引扫描队列。
7. 需要本地播放或元数据处理时，进入“本地索引”进行搜索、刮削和索引维护。

小雅和 Emby 页面使用 SSE 实时显示容器日志。页面打开后自动连接，断线后自动重连，不需要手动刷新。

## 媒体索引

媒体索引用于保存远程目录和文件信息，WebDAV、媒体库挂载和 TVBox 浏览目录时优先查询索引，避免反复递归请求远程站点。

基本操作：

1. 进入“小雅资源”。
2. 浏览远程目录。
3. 选择单个目录扫描，或在根目录执行“全部生成索引”。
4. 在“任务中心”查看扫描进度、事件、失败信息和重试状态。
5. 进入“本地索引”检查已经入库的目录和文件。

系统不会下载视频文件。STRM 内容在需要时读取并保存相对播放路径；NFO、海报、字幕等辅助文件按配置从远程源读取。

## 媒体视图

媒体视图用于把多个索引目录组织成面向媒体服务器的目录结构。“媒体视图”页面提供三栏工作区：左侧管理视图，中间管理目标目录，右侧搜索和多选索引目录并批量添加来源。同一视图可以递归合并多个来源。

对外提供媒体目录时可以选择：

- **索引目录模式**：直接使用完整的媒体索引目录树。
- **媒体视图模式**：使用一个已启用的媒体视图及其整理后的目录树。

## WebDAV

1. 在“WebDAV”页面创建账号。
2. 为账号配置允许访问的目录，默认可以授权 `/`。
3. 在客户端填写：

```text
地址：http://服务器IP:18081/dav
账号：后台创建的 WebDAV 用户名
密码：后台设置的 WebDAV 密码
```

每个 WebDAV 用户可以独立选择“索引目录模式”或“媒体视图模式”；后者需要选择一个已启用的媒体视图。播放服务、路径前缀权限和隐藏目录开关仍按用户独立生效，路径权限应用在所选模式提供的目录树之上。WebDAV 始终只读。

## 媒体库挂载

媒体库挂载使用单一全局配置，并在安装目录中提供：

```text
安装目录/mnt/xymediavault
```

全局挂载可以选择“索引目录模式”，或选择一个已启用视图的“媒体视图模式”。Emby、Jellyfin 或其他宿主机应用可以把该目录作为媒体库路径；托管的 Emby 也共享同一个全局媒体根目录，不会创建第二套挂载。

安装脚本会自动检测宿主机能否向容器提供 FUSE 设备、权限和共享挂载。检测不可用时不会加入相关高权限配置，XyMediaVault 仍可使用 WebDAV 和 TVBox；实际挂载由管理后台控制。

## TVBox

1. 进入“TVBox”。
2. 创建 TVBox 用户并选择播放服务。
3. 配置允许访问的目录，新用户默认允许 `/`。
4. 创建或重置设备令牌。
5. 一键复制后台生成的订阅地址到 TVBox 客户端。

常见地址格式：

```text
配置地址：http://服务器IP:18082/api/tvbox/config/设备令牌
CMS 地址：http://服务器IP:18082/api/tvbox/cms/设备令牌
```

不同用户可以绑定不同的播放服务，并独立控制搜索、播放和目录访问权限。

## 小雅 Alist

“小雅服务”页面支持：

- 阿里云盘普通 Token 和 Open Token 扫码授权
- 115、夸克 TV 等授权配置
- 转存目录设置
- 分享列表维护
- 容器启动、停止和重启
- SSE 实时容器日志
- 同步默认播放服务

小雅授权文件保存在安装目录的 `xiaoya` 目录中。迁移服务器时应一并备份该目录。

### 小雅 STRM 索引

“小雅资源”页面可以手动创建“扫描小雅 5678”任务。任务加入队列后异步运行，进度、专项统计、失败信息和重试状态统一显示在“任务中心”。

“系统设置”提供独立的每日小雅 STRM 扫描设置，可配置每天的执行时间及是否预缓存 NFO。每日任务与手动任务使用同一索引写入控制，避免两个扫描同时修改媒体索引。

## Emby

Emby 默认不安装，需要在“Emby 服务”页面主动安装。

安装时系统会：

1. 拉取官方 Emby 镜像。
2. 启用媒体库挂载。
3. 把媒体目录以只读方式提供给 Emby。
4. 保存 Emby 配置到安装目录的 `emby/config`。

后台支持安装、启动、停止、重启、更新和卸载。镜像拉取、容器创建、启动及运行日志会实时显示。卸载 Emby 容器不会删除 `emby/config`。

## 播放服务

播放服务用于把 STRM 相对路径转换成可以访问的播放地址。系统会创建默认播放服务，也可以在后台添加其他服务，并为 WebDAV 或 TVBox 用户选择不同的播放服务。

播放失败时优先检查：

- 播放服务地址能否从客户端访问。
- 小雅 Alist 是否正常运行。
- STRM 相对路径是否已经读取成功。
- 当前用户是否有对应目录的访问权限。

## 数据备份与迁移

重要数据位于安装目录：

```text
data/                       内置 PostgreSQL 17 数据和应用运行数据，必须整体备份
data/postgres-secrets/      数据库密码文件，敏感，不得分享或提交
xiaoya/                     小雅授权、Cookie、分享和相关配置，敏感
emby/config/                托管 Emby 配置
tmm/                        内置 TMM 的配置、许可证和运行数据
components/                 可选的本地组件覆盖归档
config.yaml                 XyMediaVault 服务配置
docker-compose.yml          容器部署配置
docker-compose.fuse.yml     安装器可能生成的可选 FUSE 高权限配置
```

### 完整冷备份

完整冷备份是当前正式支持的恢复方式。先停止 XyMediaVault，完整复制安装目录，再启动：

```bash
install_dir="$PWD"
backup_file="/var/backups/xymediavault-$(date +%Y%m%d-%H%M%S).tar.gz"
case "$backup_file" in "$install_dir"/*) echo "备份目标不能位于安装目录内" >&2; exit 1;; esac
mkdir -p "$(dirname "$backup_file")"
docker compose stop
backup_status=0
tar -C "$(dirname "$install_dir")" -czf "$backup_file" "$(basename "$install_dir")" || backup_status=$?
docker compose start
[ "$backup_status" -eq 0 ] || exit "$backup_status"
```

请在安装目录中执行，并把 `backup_file` 改为宿主机上明确位于安装目录之外、当前用户可写
的绝对路径。示例使用 `/var/backups`，普通用户没有权限时可改为独立备份盘或其他外部目录。
命令会拒绝把归档写进安装目录，避免递归打包。该流程会暂停 XyMediaVault、小雅和同一
Compose 项目中的其他服务，以保证整个安装目录处于一致状态；完成后会恢复这些服务。
备份包含数据库密码、媒体路径、用户信息和小雅授权，应按敏感数据保存。

恢复时停止目标容器，把完整备份恢复到空目录，并使用兼容的 PG17 镜像启动。不要把备份
覆盖到正在运行的 PostgreSQL 数据目录，也不要把旧 SQLite 数据目录与 PG17 数据目录混用。

### PostgreSQL 逻辑导出

运行中的实例也可以导出 PostgreSQL 逻辑备份：

```bash
docker compose exec -T xymediavault sh -c \
  'PGPASSWORD="$(cat /app/data/postgres-secrets/app-password)" pg_dump -h /var/run/postgresql -U xymedia_app xymedia' \
  > xymedia.sql
```

该文件只包含 XyMediaVault PostgreSQL 数据库，不包含：

- `xiaoya/` 中的授权、Cookie 和分享配置；
- `emby/config/`；
- `config.yaml` 和 Compose 文件；
- TMM、组件覆盖和其他应用运行文件。

因此逻辑导出不能替代完整安装目录冷备份。当前 README 不提供覆盖现有内置数据库的
逻辑恢复命令；未经验证直接 drop、覆盖或导入可能破坏 Schema 与应用状态。

### 高级排障：只读查看 PostgreSQL

PostgreSQL 默认不映射到宿主机。需要使用 DBeaver、DataGrip 或 pgAdmin 查看表时，在 `docker-compose.yml` 的 `xymediavault` 服务中增加：

```yaml
environment:
  XYMEDIA_OBSERVER_ENABLED: "true"
ports:
  - "127.0.0.1:15432:5432"
```

重建容器后，只读账号为 `xymedia_observer`，数据库为 `xymedia`，地址为 `127.0.0.1:15432`。自动生成的观察账号密码位于容器持久化目录 `data/postgres-secrets/observer-password`；该文件不得提交、分享或写入 Compose。也可以通过 `XYMEDIA_OBSERVER_PASSWORD_FILE` 指定容器内的 secret 文件。

观察账号仅有表和序列的读取权限。查看完成后移除端口映射并将 `XYMEDIA_OBSERVER_ENABLED` 改回 `false`，重建容器会撤销登录和读取权限。不要把 `5432` 绑定到 `0.0.0.0` 或暴露到公网。

## 维护者说明

用户应使用官方安装脚本和公开 Docker 镜像部署。镜像发布、候选摘要验证和渠道提升由
项目维护流程处理，不属于普通安装或更新步骤。

## 常见问题

### Docker 服务未启动

确认 Docker 可以正常访问：

```bash
docker info
docker compose version
```

执行安装脚本的用户必须有权限访问 Docker Socket。

### 检测到旧 SQLite 数据，安装被拒绝

当前 PG17 版本不提供 SQLite 数据迁移。请不要删除旧 `.db`、`.db-wal` 或 `.db-shm`
文件，也不要在原目录强制启动。保留旧安装目录，在新的空目录执行安装；如需继续访问
旧数据，应保留对应旧版本实例。

### 首次启动长时间未就绪

首次启动需要初始化 PostgreSQL 17、创建 Schema 并启动内置组件。先检查：

```bash
docker compose ps
docker compose logs --tail=200 xymediavault
```

正常启动日志应包含 PostgreSQL ready、Schema 版本和 API 监听信息。若日志出现
`Permission denied`，检查安装目录是否允许容器访问，并确认没有把旧 SQLite 目录挂到
`/app/data`。

### 更新时提示传输端点尚未连接

最新版安装脚本会自动停止应用并清理残留媒体库挂载。通常直接重新执行更新命令即可。

仍然失败时，在安装目录执行：

```bash
docker compose stop xymediavault
umount -l ./mnt/xymediavault
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh
```

### 端口被占用

重新执行安装脚本，在交互提示中为管理后台、WebDAV、TVBox 或小雅填写未占用端口。更新已有安装时，脚本会保留当前端口映射。

### WebDAV 能看到目录但文件无法读取

检查索引任务是否完成、索引源是否可用、远程辅助文件映射设置以及用户绑定的播放服务。任务和 IO 日志会记录详细失败原因。

### TMM 或 Title 临时失败

TMM、Title 或其上游服务短暂不可用时，单个元数据任务可能失败，主服务和已有索引仍可
继续使用。先在“任务中心”查看失败详情和后续重试结果，再检查：

```bash
docker compose logs --tail=200 xymediavault
```

若同一目录持续失败，请记录任务 ID、媒体路径、时间和错误消息后再排查，不要通过删除
PostgreSQL 数据目录来重试。

### 数据库清理后文件大小没有立即下降

PostgreSQL 由 autovacuum 自动回收可复用空间，删除记录后数据目录不一定立即缩小。后台“数据库整理”仅执行 `ANALYZE` 更新查询计划统计信息，不会执行会长时间锁表的 `VACUUM FULL`。需要物理缩容时，请先完成可恢复备份，并在维护窗口按 PostgreSQL 官方流程处理。

## 安全提示

- 不要公开 `xiaoya` 目录中的 Token、Cookie 和分享配置。
- 不要公开 `data/postgres-secrets/`、数据库备份、TVBox 设备令牌或 WebDAV 密码。
- PostgreSQL 默认不映射宿主端口；排障映射只能绑定 `127.0.0.1`，禁止暴露到公网。
- 挂载 `/var/run/docker.sock` 会授予容器较高的宿主机 Docker 管理权限。
- FUSE 需要 `/dev/fuse`、`SYS_ADMIN` 和共享挂载传播；不需要本地挂载时应移除这些权限。
- 建议通过防火墙或反向代理限制管理后台访问范围。
- 对公网开放时建议配置 HTTPS。

## 赞助支持

如果这个项目对你有帮助，可以通过以下方式支持后续维护。

| 微信 | 支付宝 |
| --- | --- |
| ![微信赞赏](assets/donation/wechat-pay.jpg) | ![支付宝赞赏](assets/donation/alipay.jpg) |

## 说明

XyMediaVault 仅用于管理用户有权访问的媒体资源。使用者应遵守所在地法律法规及相关服务条款。
