# XyMediaVault

XyMediaVault（小雅资源管理中心）是面向小雅 Alist、Emby、Jellyfin 和 NAS 用户的媒体资源管理服务。它提供远程目录浏览、媒体扫描整理、动态 STRM、WebDAV、FUSE、小雅授权管理和多源故障切换。

Docker 镜像：[`iceqi/xymediavault:latest`](https://hub.docker.com/r/iceqi/xymediavault)

## 一键安装

### 环境要求

- Linux 服务器或 NAS，支持 `amd64/x86_64`、`arm64/aarch64`、`arm/v7`
- Docker
- Docker Compose V2，或独立的 `docker-compose`
- 使用 FUSE 时，宿主机需要提供 `/dev/fuse` 并允许共享挂载

### 执行安装

在服务器终端中运行：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh
```

安装脚本会逐项询问安装目录、访问地址、端口、FUSE 和镜像拉取方式。安装目录直接按回车时，默认使用执行脚本时的当前目录；输入其他目录则安装到指定位置。

默认配置：

| 项目 | 默认值 |
| --- | --- |
| 安装目录 | 执行脚本时的当前目录 |
| Docker 镜像 | `iceqi/xymediavault:latest` |
| 管理后台 | `http://服务器IP:18080` |
| WebDAV | `http://服务器IP:18081/dav` |
| 小雅 Alist | `http://服务器IP:5678` |
| 小雅管理端口 | `2345` |
| 小雅代理端口 | `2346` |

安装脚本会读取 Docker daemon 的实际架构，目前自动支持：

- `linux/amd64`
- `linux/arm64`
- `linux/arm/v7`

Docker 会从 `iceqi/xymediavault:latest` 的多架构 manifest 中自动拉取匹配镜像，不需要手动修改镜像名称或在 Compose 中设置 `platform`。如果本地同名镜像的架构不匹配，脚本会重新拉取正确架构。

## 更新

安装和更新使用同一个脚本。再次运行一键安装命令并选择更新，脚本会：

1. 检测现有安装目录。
2. 停止 XyMediaVault 容器并清理残留 FUSE 挂载。
3. 拉取 `iceqi/xymediavault:latest`。
4. 保留现有配置和数据并重建容器。
5. 在服务启动时自动执行数据库迁移。

在安装目录以外的位置执行更新时，可以通过 `INSTALL_DIR` 指定已有安装目录：

```bash
INSTALL_DIR=/你的安装目录 sh install.sh
```

## 首次使用

1. 打开 `http://服务器IP:18080`。
2. 首次登录时创建管理员账号。
3. 按初始化窗口使用阿里云盘 App 完成普通 Token 和 Open Token 扫码授权。
4. 确认转存目录 ID，默认输入值为 `root`。
5. 配置完成后，系统会自动重启小雅容器。
6. 在“媒体资源”页面浏览远程目录，并按需要创建扫描整理任务。

没有执行扫描、刮削或整理任务时，仍然可以使用远程直通模式浏览和播放媒体资源。

## WebDAV 与 FUSE

- `original`：远程直通，只展示远程原始目录。
- `organized`：只展示已经扫描并缓存的整理目录，不与远程目录混合。
- WebDAV 账号可以单独选择目录模式。
- FUSE 模式需要宿主机支持 `/dev/fuse`、`SYS_ADMIN` 和 `rshared` 挂载传播。

详细的安装参数、日常维护、备份和故障排查请阅读：[使用文档](docs/USAGE.md)。

## 数据与安全

运行数据保存在用户选择的安装目录。以下以 `/opt/xymediavault` 为例：

```text
/opt/xymediavault/config.yaml
/opt/xymediavault/docker-compose.yml
/opt/xymediavault/data/
/opt/xymediavault/xiaoya/
/opt/xymediavault/mnt/xymediavault/
```

请不要公开 `data/`、`xiaoya/`、数据库、Cookie、Token 或授权文件。公开仓库仅包含安装脚本和文档，不包含任何本地运行数据。

## 支持项目

如果这个项目对你有帮助，可以通过微信或支付宝支持后续维护。

<table>
  <tr>
    <th>微信</th>
    <th>支付宝</th>
  </tr>
  <tr>
    <td><img src="assets/donation/wechat-pay.jpg" alt="微信打赏二维码" width="260"></td>
    <td><img src="assets/donation/alipay.jpg" alt="支付宝打赏二维码" width="260"></td>
  </tr>
</table>
