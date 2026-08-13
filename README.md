# XyMediaVault Beta

XyMediaVault 是面向小雅 Alist、Emby、Jellyfin 和 TVBox 的媒体资源管理服务，提供媒体索引、WebDAV、媒体库挂载、TVBox 接口、小雅授权管理和 Emby 容器管理等能力。

> 本项目为闭源软件。请通过官方镜像和安装脚本部署，未经授权不提供源码再分发。

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

## 支持环境

- 已安装并启动 Docker。
- 已安装 Docker Compose V2 或 `docker-compose`。
- 支持 `linux/amd64`、`linux/arm64`、`linux/arm/v7`。
- 安装脚本会自动检测媒体库挂载能力；使用本地挂载时，宿主机需要支持 FUSE、`/dev/fuse` 和共享挂载传播。
- 建议预留管理后台、WebDAV、TVBox 和小雅 Alist 所需端口。

默认端口：

| 服务 | 默认端口 | 默认地址 |
| --- | ---: | --- |
| 管理后台 | 18080 | `http://服务器IP:18080` |
| WebDAV | 18081 | `http://服务器IP:18081/dav` |
| TVBox | 18082 | `http://服务器IP:18082` |
| 小雅 Alist | 5678 | `http://服务器IP:5678` |

## 一键安装

先进入希望保存 XyMediaVault 数据的目录，再执行：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/beta/scripts/install.sh | sh
```

这是 beta 测试安装命令，默认使用 `iceqi/xymediavault:beta`，不会覆盖 `latest`。如需显式指定镜像，环境变量必须传给脚本：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/beta/scripts/install.sh | env IMAGE=iceqi/xymediavault:beta sh
```

不指定目录时，安装目录严格使用执行命令时的当前目录。脚本不会默认安装到 `/opt`，也不会读取环境中的 `INSTALL_DIR` 作为默认路径。

例如，希望安装到当前用户的 `XyMediaVault` 目录：

```bash
mkdir -p "$HOME/XyMediaVault"
cd "$HOME/XyMediaVault"
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/beta/scripts/install.sh | sh
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

### 安装选项

脚本会交互询问以下内容，直接按回车使用显示的默认值：

- 安装目录
- Docker 镜像
- 服务器访问 IP 或域名
- 管理后台端口
- WebDAV 端口
- TVBox 服务端口
- 小雅 Alist、管理和代理端口
- 是否强制拉取最新镜像

脚本自动识别 Docker 服务器架构并拉取对应的 `iceqi/xymediavault:beta` 镜像，同时自动检测媒体库挂载能力。首次安装检测可用时会自动挂载，之后可在管理后台控制。主服务默认管理 `iceqi/xymedia-tmm:beta`，稳定镜像和 `latest` 不会被 beta 安装覆盖。

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

更新过程会保留数据库、系统配置、小雅授权文件、Emby 配置和 TMM 数据。更新前会停止 XyMediaVault，并检查媒体库目录是否存在残留 FUSE 挂载；检测到挂载时会先卸载，再重建主容器并自动重新挂载。TMM 使用由应用管理的独立 bridge 网络，更新主容器时不会删除或重建 TMM 容器。

## 首次使用

1. 打开 `http://服务器IP:18080`。
2. 注册并登录管理员账号。
3. 按首次设置窗口完成小雅普通 Token、Open Token 和转存目录配置。
4. 转存目录默认显示 `root`，可以按实际需要修改。
5. 配置完成后系统会重启小雅容器。
6. 在“索引源”确认内置源可用，或添加自定义同构索引源。
7. 在“媒体资源”选择目录并创建媒体索引任务。

小雅和 Emby 页面使用 SSE 实时显示容器日志。页面打开后自动连接，断线后自动重连，不需要手动刷新。

## 媒体索引

媒体索引用于保存远程目录和文件信息，WebDAV、媒体库挂载和 TVBox 浏览目录时优先查询索引，避免反复递归请求远程站点。

基本操作：

1. 进入“媒体资源”。
2. 使用直通视图浏览远程目录。
3. 选择单个目录扫描，或在根目录执行“全部生成索引”。
4. 在“任务中心”查看扫描进度、事件、失败信息和重试状态。
5. 切换到媒体索引视图检查已经入库的目录和文件。

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

1. 进入“TVBox 服务”。
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

“小雅管理”页面支持：

- 阿里云盘普通 Token 和 Open Token 扫码授权
- 115、夸克 TV 等授权配置
- 转存目录设置
- 分享列表维护
- 容器启动、停止和重启
- SSE 实时容器日志
- 同步默认播放服务

小雅授权文件保存在安装目录的 `xiaoya` 目录中。迁移服务器时应一并备份该目录。

### 小雅 STRM 索引

“媒体资源”页面可以手动创建“扫描小雅 STRM 索引”任务，并可选择同时预缓存 NFO。任务异步运行，进度、专项统计、失败信息和重试状态统一显示在“任务中心”。

“系统设置”提供独立的每日小雅 STRM 扫描设置，可配置每天的执行时间及是否预缓存 NFO。每日任务与手动任务使用同一索引写入控制，避免两个扫描同时修改媒体索引。

## Emby

Emby 默认不安装，需要在“Emby 管理”页面主动安装。

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

## 数据与备份

重要数据位于安装目录：

```text
data/                 XyMediaVault 数据库和运行数据
xiaoya/               小雅授权、Cookie 和分享配置
emby/config/          Emby 配置
tmm/data/             TMM 配置、许可证信息、缓存和元数据状态
config.yaml           服务配置
docker-compose.yml    容器部署配置
```

备份前建议停止 XyMediaVault：

```bash
docker compose stop xymediavault
```

完整复制上述文件和目录后再启动：

```bash
docker compose start xymediavault
```

不要只复制正在写入的 SQLite 主文件而忽略同目录中的 `-wal` 和 `-shm` 文件。

## 常见问题

### Docker 服务未启动

确认 Docker 可以正常访问：

```bash
docker info
docker compose version
```

执行安装脚本的用户必须有权限访问 Docker Socket。

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

### 数据库清理后文件大小没有立即下降

删除记录不会自动缩小 SQLite 文件。请通过后台提供的数据库整理功能执行压缩，并避免在扫描任务运行时操作。

## 安全提示

- 不要公开 `xiaoya` 目录中的 Token、Cookie 和分享配置。
- 不要公开数据库、TVBox 设备令牌或 WebDAV 密码。
- 建议通过防火墙或反向代理限制管理后台访问范围。
- 对公网开放时建议配置 HTTPS。

## 赞助支持

如果这个项目对你有帮助，可以通过以下方式支持后续维护。

| 微信 | 支付宝 |
| --- | --- |
| ![微信赞赏](assets/donation/wechat-pay.jpg) | ![支付宝赞赏](assets/donation/alipay.jpg) |

## 说明

XyMediaVault 仅用于管理用户有权访问的媒体资源。使用者应遵守所在地法律法规及相关服务条款。
