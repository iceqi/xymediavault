# XyMediaVault

XyMediaVault 是面向小雅 Alist、Emby、Jellyfin 和 TVBox 场景的媒体资源索引与虚拟文件系统服务。它从 HTTP Index 扫描目录及文件信息，在 SQLite 中维护统一索引，再通过 WebDAV、媒体库挂载和 TVBox 提供稳定的媒体视图。媒体服务器浏览目录时只查询本地索引，不再递归访问远程源站。

数据库保存目录结构、文件路径和可选元数据，不保存视频内容或完整播放 URL。STRM 文本在第一次读取时从远程源获取并缓存；NFO、海报、字幕等辅助文件仅保存索引路径，在客户端实际访问时按需从远程读取。

当前功能包含 Go 后端、SQLite 媒体索引、HTTP Index 多源故障切换、定时增量扫描、动态 STRM、只读 WebDAV、媒体库挂载、TVBox JSON CMS、Emby 容器管理和 Arco 管理后台。

## 快速启动

后端：

```bash
go run ./cmd/xymediavault server --config config.example.yaml
```

前端：

```bash
cd web/arco-admin
npm install
npm run dev
```

当前后端 `server` 命令会加载配置、初始化 SQLite 数据库，并启动管理后台/API、WebDAV 和 TVBox 服务。前端静态资源可用 Vite 开发服务器调试；Docker 镜像会构建前端资源并由应用容器直接提供管理后台。

## Docker 部署

默认 Docker 配置：

- API 端口：容器内 `8080`，默认映射到宿主机 `18080`
- WebDAV 端口：容器内 `8081`，默认映射到宿主机 `18081`
- TVBox 端口：容器内 `8082`，默认映射到宿主机 `18082`
- 数据目录：`./data:/app/data`
- 数据库：SQLite，文件为 `/app/data/xymediavault.db`
- 媒体库挂载：默认启用，需要宿主机提供 `/dev/fuse` 和 `SYS_ADMIN`

启动：

```bash
docker compose up -d --build
```

检查 Compose 配置：

```bash
docker compose config
```

如果宿主机只安装了旧版 Compose，也可以使用：

```bash
docker-compose config
```

不要提交运行生成的 `data/*.db`。MySQL/MariaDB 是后续支持目标，当前默认部署路径是 SQLite。

## DockerHub 发布

发布前先登录 DockerHub：

```bash
docker login
```

构建并推送镜像：

```bash
DOCKER_IMAGE=你的DockerHub用户名/xymediavault VERSION=1.0.0 sh scripts/publish-dockerhub.sh
```

发布脚本使用 Docker Buildx，默认同时构建 `linux/amd64`、`linux/arm64` 和 `linux/arm/v7`。DockerHub 会为同一标签生成多架构 manifest，用户安装时由 Docker 自动选择与服务器匹配的镜像。

如果 `VERSION` 不是 `latest`，脚本会同时推送：

```text
你的DockerHub用户名/xymediavault:1.0.0
你的DockerHub用户名/xymediavault:latest
```

镜像构建上下文已经通过 `.dockerignore` 排除了 `data/`、`mnt/` 和 `xiaoya/`，不会把本地数据库、媒体库挂载目录、115 Cookie、阿里/夸克 token 等敏感文件打包进镜像。

## 一键部署

普通用户可以使用一键脚本部署。把 `IMAGE` 改成你发布到 DockerHub 的镜像名：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh
```

脚本会进入交互式安装，逐项询问并显示建议值：

```text
安装目录（默认使用执行脚本时的当前目录）
Docker 镜像
目标架构（自动检测 linux/amd64、linux/arm64 或 linux/arm/v7）
服务器访问 IP 或域名
管理后台端口
WebDAV 端口
TVBox 服务端口
小雅 Alist 端口
小雅管理端口
小雅代理端口
是否启用媒体库挂载
是否强制拉取镜像
```

直接按回车采用当前提示中的建议值，输入新值则覆盖该项。

如果希望先检查脚本内容，也可以下载后再执行：

```bash
wget -O install.sh https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh
sh install.sh
```

也可以通过环境变量修改交互提示中的建议值：

```bash
INSTALL_DIR=/opt/xymediavault \
PUBLIC_HOST=192.168.1.10 \
API_PORT=18080 \
WEBDAV_PORT=18081 \
TVBOX_PORT=18082 \
XIAOYA_PORT=5678 \
ENABLE_FUSE=true \
IMAGE=iceqi/xymediavault:latest \
sh install.sh
```

默认镜像是 `iceqi/xymediavault:latest`。如果本地已经存在该标签，脚本会直接复用，不再访问 DockerHub。需要强制拉取最新镜像时使用：

安装脚本读取 Docker daemon 的实际架构。目前支持 `linux/amd64`、`linux/arm64` 和 `linux/arm/v7`；本地同名镜像架构不匹配时会自动拉取正确架构，Compose 文件不需要手动设置 `platform`。

```bash
FORCE_PULL=true sh install.sh
```

安装和更新使用同一个脚本。脚本会检查安装目录中是否已有 `docker-compose.yml`：不存在时进入首次安装配置；存在时自动进入更新流程，保留原有配置，只停止 XyMediaVault、清理宿主机残留的媒体库挂载、拉取或构建新镜像并重建应用容器。

安装目录留空时使用执行脚本时的当前目录。如果希望安装到其他位置，可以在交互提示中输入目录，也可以通过 `INSTALL_DIR` 指定：

```bash
INSTALL_DIR=/opt/xymediavault sh install.sh
```

数据库迁移会在新容器启动时自动执行。不要直接在媒体库已挂载时使用 `docker-compose up --force-recreate`，否则旧挂载可能阻止 Docker 创建 bind mount。

脚本会自动创建：

```text
/opt/xymediavault/docker-compose.yml
/opt/xymediavault/config.yaml
/opt/xymediavault/data
/opt/xymediavault/xiaoya
/opt/xymediavault/mnt/xymediavault
/opt/xymediavault/emby/config
```

部署完成后默认访问：

```text
管理后台：http://服务器IP:18080
WebDAV：http://服务器IP:18081/dav
TVBox：http://服务器IP:18082
小雅 Alist：http://服务器IP:5678
```

## WebDAV 使用方式

1. 在管理后台或 API 中创建 WebDAV 用户。
2. 为用户添加路径前缀权限，例如 `/` 或 `/电影/`。
3. 媒体服务器使用 Basic Auth 挂载 WebDAV。

默认配置中 WebDAV 监听 `0.0.0.0:8081`，基础路径配置为 `/dav`。WebDAV 按只读虚拟媒体库设计，目录和文件列表来自本地索引；STRM、NFO、图片和字幕等内容在打开时通过远程源读取。

## TVBox 服务

TVBox 是独立于 WebDAV 的 JSON CMS 服务。它使用已经扫描到 XyMediaVault 数据库中的媒体索引，不会在 TVBox 客户端请求时递归访问远程目录，也不读取或依赖 STRM 文件内容。

配置步骤：

1. 登录管理后台，打开“TVBox 服务”。
2. 创建一个 TVBox 用户，并为用户选择播放服务。
3. 为用户配置允许访问的目录。新用户默认允许访问 `/`，也可以改成 `/电影/`、`/电视剧/` 等路径前缀。
4. 在“设备”中创建令牌。令牌只在生成时完整显示，重置或删除设备后旧订阅地址立即失效。
5. 将生成的订阅地址粘贴到 TVBox 客户端。

订阅地址格式：

```text
http://服务器IP:18082/api/tvbox/config/设备令牌
```

如果配置了 TVBox 外部访问地址，后台生成的地址会使用该地址；留空时使用当前请求的协议和主机地址。标准 JSON CMS 地址为：

```text
http://服务器IP:18082/api/tvbox/cms/设备令牌
```

TVBox 用户可以分别控制搜索和播放权限，也可以绑定不同的 `/playback` 播放服务。电影和剧集来自统一媒体索引，剧集会依据 NFO 元数据或目录、季号和集号结构聚合，不会把每一集散列成独立影片。播放地址由服务端根据用户绑定的播放服务和数据库中的相对路径动态生成，例如：

```text
http://播放服务地址/d/电影/示例.mkv
```

不会把完整播放地址写入媒体数据库。TVBox 查看详情时按需读取已索引的 `movie.nfo` 或 `tvshow.nfo`；存在本地海报索引时通过带设备令牌的图片代理按需返回，不在本地缓存图片。NFO 仅提供 TMDB ID 而缺少部分字段时，系统可以调用后台配置的 TMDB 服务补全；TMDB 图片域名会在返回时动态改写为 `https://tmdb.keeper.work`，无需修改数据库。TVBox 页面还提供分类、目录白名单、设备令牌和访问日志管理；访问日志支持按用户、操作和状态筛选，并可清空。

## 小雅 Alist 托管管理

Docker Compose 默认包含 `xiaoya-alist` 服务，并把宿主机 `./xiaoya` 同时挂载给小雅和 XyMediaVault：

```text
./xiaoya/115_cookie.txt
./xiaoya/ali2115.txt
./xiaoya/115_list.txt
./xiaoya/115share_list.txt
./xiaoya/quark_cookie.txt
./xiaoya/quark_tv_cookie.txt
./xiaoya/mytoken.txt
./xiaoya/myopentoken.txt
./xiaoya/temp_transfer_folder_id.txt
```

管理后台的“小雅管理”页面提供扫码授权、查看 `xiaoya-alist` 状态、启动/停止/重启容器和 SSE 实时日志，并把小雅地址同步为媒体源和默认播放服务。页面打开后会自动接收容器启动及运行日志，连接中断后自动重连，不需要手动刷新。当前扫码授权支持 115、阿里云盘、阿里云盘 Open 和夸克 TV；普通夸克仍是 Cookie 模式。容器控制依赖 `/var/run/docker.sock`，后端只允许操作固定容器名 `xiaoya-alist`。

115 授权支持选择扫码渠道，并可开启“阿里转 115 加速”。开启后系统会根据当前 `115_cookie.txt` 自动生成 `ali2115.txt`；关闭后会清空 `ali2115.txt`。页面也支持可视化维护 `115share_list.txt`，每条分享挂载按“小雅路径 分享ID 分享目录ID 提取码”的四列格式写入。

## 媒体库挂载

Docker Compose 默认把宿主机目录 `./mnt/xymediavault` 映射到容器内 `/mnt/xymediavault`，并使用 `rshared` 传播方式。服务启动后，宿主机可以从 `./mnt/xymediavault` 看到同一套虚拟 STRM 目录。

默认配置：

```yaml
fuse:
  enabled: true
  mount_path: /mnt/xymediavault
```

容器部署需要 `/dev/fuse`、`SYS_ADMIN` 和宿主机支持共享挂载传播；这些已经写入 `docker-compose.yml`。如果宿主机内核或面板限制用户态文件系统挂载，服务启动时会报错，此时可以先把 `fuse.enabled` 改为 `false`，继续使用 WebDAV。

## Emby 管理

管理后台提供独立的“Emby 管理”页面。首次安装可设置宿主机访问端口，系统会拉取官方 `emby/embyserver:latest` 镜像，自动启用媒体库挂载，并创建固定名称的 `xymediavault-emby` 容器。

Emby 配置保存在安装目录的 `./emby/config`，媒体库以 `/media:ro` 只读挂载到 Emby。后台支持启动、停止、重启、更新、SSE 实时日志和卸载；卸载只删除容器，不删除配置目录。安装或更新时，镜像拉取、容器创建和启动进度会直接推送到日志区域，容器运行日志随后持续输出，连接中断后自动重连。Emby 由 XyMediaVault 通过 Docker Socket 独立管理，不需要也不应额外使用 `docker-compose.emby.yml`。

## 媒体索引与源站说明

媒体源表示一个 HTTP Index 访问入口；系统内置多条同构镜像，也允许在“索引源”页面添加自定义入口。扫描和文件读取按优先级访问启用源，遇到超时、网络错误或 5xx 会切换到下一个源；失败源会被短暂熔断。源站之间是同一目录结构的镜像，不参与媒体身份绑定，媒体索引也不会绑定 `source_id`。

小雅 Alist 只作为播放服务使用。系统从 IndexOf 建立目录和文件索引；播放时使用用户绑定的小雅播放服务与 STRM 中解析出的 `/d/...` 相对路径动态生成地址。

扫描器将远程目录、文件名、文件类型、大小、修改时间和源路径写入统一索引。后续 WebDAV、媒体库挂载、TVBox 和媒体资源页都从 SQLite 查询目录，不会因客户端反复浏览而递归扫描源站。定时扫描发现新增内容时增量写入；远程已删除的条目会在索引中标记为不可用。

系统不下载视频，也不批量缓存 NFO 或图片。只有 STRM 文本在第一次实际打开时读取并缓存其相对播放路径，后续直接使用缓存；可以在媒体资源页清空 STRM 缓存，清空操作不会删除媒体索引。

## 远程辅助文件映射说明

`jpg`、`png`、`webp`、`nfo` 和字幕等辅助文件会随目录扫描写入文件索引。开启远程辅助文件映射后，WebDAV 或媒体库挂载客户端打开辅助文件时会从当前可用的 HTTP Index 源实时读取内容，不落盘缓存。

配置项：

```yaml
virtual:
  enable_remote_file_mapping: true
```

运行时开关由系统设置 `enable_remote_file_mapping` 控制。关闭时，WebDAV 读取辅助文件会返回不存在；开启后，系统通过当前可用的媒体源实时拉取远程辅助文件，不落盘缓存。

## 可选元数据增强与存储边界

整理任务支持可选 AI 标题修正，也可以选择启用 TMDB 补全。两项都不是运行服务的必需条件：未配置对应服务、调用失败或没有匹配结果时，系统保留可推断的原始标题和路径，并记录任务结果。

存储边界如下：

- SQLite 保存目录索引、文件索引、STRM 相对路径缓存和已获取的可选媒体元数据，不保存完整播放 URL。
- 建立索引不会下载或复制视频内容。
- NFO、图片和字幕仅保存远程路径，访问时按需读取，不落盘缓存。
- WebDAV 和媒体库挂载提供数据库驱动的虚拟访问视图，不创建本地媒体副本。运行数据、配置和 SQLite 数据库位于部署目录的数据卷中。

## 验证命令

```bash
go test -count=1 ./...
cd web/arco-admin && npm test && npm run build
docker compose config
```
