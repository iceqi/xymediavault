# XyMediaVault 使用文档

## 1. 安装前准备

确认 Docker 可用：

```bash
docker version
```

确认至少存在一种 Compose 命令：

```bash
docker compose version
```

旧环境也可以使用：

```bash
docker-compose version
```

建议提前放行需要使用的端口。默认管理后台为 `18080`，WebDAV 为 `18081`，小雅 Alist 为 `5678`，小雅管理和代理端口为 `2345`、`2346`。

## 2. 一键安装

直接执行一键安装：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | sh
```

如果希望先检查脚本内容，也可以下载后再执行：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh -o install.sh
sh install.sh
```

脚本必须在交互式终端中执行，因为所有部署参数都会逐项确认。安装目录留空时使用当前执行目录；也可以在提示中输入绝对路径或相对路径，或提前设置 `INSTALL_DIR`。

### 安装参数

| 参数 | 说明 | 建议值 |
| --- | --- | --- |
| `INSTALL_DIR` | 配置、数据库和小雅文件目录 | 执行脚本时的当前目录 |
| `IMAGE` | XyMediaVault Docker 镜像 | `iceqi/xymediavault:latest` |
| `PUBLIC_HOST` | 用户访问服务时使用的 IP 或域名 | 自动检测服务器 IP |
| `API_PORT` | 管理后台端口 | `18080` |
| `WEBDAV_PORT` | WebDAV 端口 | `18081` |
| `XIAOYA_PORT` | 小雅 Alist 端口 | `5678` |
| `XIAOYA_ADMIN_PORT` | 小雅管理端口 | `2345` |
| `XIAOYA_PROXY_PORT` | 小雅代理端口 | `2346` |
| `ENABLE_FUSE` | 是否启用 FUSE 虚拟目录 | `true` |
| `FUSE_DIRECTORY_MODE` | FUSE 目录模式 | `original` |
| `FORCE_PULL` | 是否忽略本地镜像并强制拉取 | `false` |

脚本会自动识别 Docker 的运行架构，目前支持 `linux/amd64`、`linux/arm64` 和 `linux/arm/v7`。Docker 会从同一个 `iceqi/xymediavault:latest` 标签选择正确镜像，不需要用户手动指定架构。

环境变量只修改交互提示中的建议值，脚本仍会要求用户确认。例如：

```bash
INSTALL_DIR=/opt/xymediavault \
PUBLIC_HOST=192.168.1.10 \
API_PORT=18080 \
WEBDAV_PORT=18081 \
ENABLE_FUSE=false \
sh install.sh
```

## 3. 首次登录与小雅初始化

安装完成后访问：

```text
http://服务器IP:18080
```

首次使用流程：

1. 创建管理员用户名和密码。
2. 使用阿里云盘 App 扫描初始化窗口中的普通 Token 二维码。
3. 扫描 Open Token 二维码。
4. 检查转存目录 ID。输入框默认是 `root`，也可以填写自己的目录 ID。
5. 保存后等待小雅容器自动重启。

如果初始化窗口再次出现，请检查以下文件是否为空：

```text
/opt/xymediavault/xiaoya/mytoken.txt
/opt/xymediavault/xiaoya/myopentoken.txt
/opt/xymediavault/xiaoya/temp_transfer_folder_id.txt
```

不要把这些文件内容发送给他人或提交到 Git 仓库。

## 4. 媒体资源与扫描整理

媒体资源页默认使用远程直通模式，可以直接浏览小雅远程目录。媒体文件可以从列表中直接打开播放。

扫描文件夹时可以选择是否：

- 写入基础缓存索引。
- 补充缺少的 NFO 或 TMDB 信息。
- 使用 AI 标准化无法准确识别的媒体标题。
- 使用指定的整理规则生成虚拟目录。

AI 或 TMDB 调用失败不会阻止基础扫描，原始媒体仍可通过远程直通模式使用。

## 5. WebDAV

默认地址：

```text
http://服务器IP:18081/dav
```

在管理后台创建 WebDAV 账号并设置目录权限。每个账号可以选择：

- 远程直通：只读取远程原始目录。
- 本地缓存：只读取已经扫描并缓存的目录。

缓存模式不会自动混入尚未扫描的远程目录。如果缓存模式目录为空，请先在媒体资源页扫描对应文件夹。

## 6. FUSE

默认宿主机挂载目录：

```text
/opt/xymediavault/mnt/xymediavault
```

FUSE 依赖：

- `/dev/fuse`
- 容器 `SYS_ADMIN` capability
- `rshared` 挂载传播

如果当前服务器或 NAS 不允许 FUSE，请在安装时选择关闭。关闭 FUSE 不影响管理后台和 WebDAV。

## 7. 更新

重新下载并执行最新脚本：

```bash
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/iceqi/xymediavault/main/scripts/install.sh | INSTALL_DIR=/opt/xymediavault sh
```

脚本检测到安装目录下存在 `docker-compose.yml` 后会进入更新流程。配置、数据库和小雅授权文件会被保留。

## 8. 日常维护

以下示例假设安装目录为 `/opt/xymediavault`，并使用 Docker Compose V2。

查看容器状态：

```bash
cd /opt/xymediavault
docker compose ps
```

查看 XyMediaVault 日志：

```bash
cd /opt/xymediavault
docker compose logs --tail=200 xymediavault
```

查看小雅日志：

```bash
cd /opt/xymediavault
docker compose logs --tail=200 xiaoya-alist
```

重启服务：

```bash
cd /opt/xymediavault
docker compose restart xymediavault
```

旧版环境请把上述 `docker compose` 替换为 `docker-compose`。

## 9. 备份

建议备份：

```text
/opt/xymediavault/config.yaml
/opt/xymediavault/docker-compose.yml
/opt/xymediavault/data/
/opt/xymediavault/xiaoya/
```

复制 SQLite 数据库前，建议先停止 XyMediaVault，避免只复制主数据库而遗漏 WAL 中尚未合并的数据：

```bash
cd /opt/xymediavault
docker compose stop xymediavault
```

备份完成后重新启动：

```bash
cd /opt/xymediavault
docker compose up -d xymediavault
```

## 10. 常见问题

### Docker 镜像拉取失败

确认服务器能够访问 DockerHub，然后执行：

```bash
docker pull iceqi/xymediavault:latest
```

### 端口被占用

重新执行安装脚本，在交互步骤中修改对应的宿主机端口。不要修改容器内部的 `8080` 和 `8081`。

### 中文目录提示 `project name must not be empty`

新版安装脚本会固定使用 `xymediavault` 作为 Compose 项目名，中文、空格或特殊字符目录均可正常安装。遇到该错误时，重新执行最新的一键安装命令即可。

### 更新时卡在 FUSE 挂载

安装脚本会先停止 XyMediaVault 并尝试清理旧挂载。如果仍然失败，可以执行：

```bash
umount -l /opt/xymediavault/mnt/xymediavault
```

确认目录不再是挂载点后，再重新运行安装脚本。

### WebDAV 缓存模式看不到文件

缓存模式只展示已扫描的缓存目录。先切换到媒体资源的远程直通模式，对目标文件夹执行扫描，然后重新连接 WebDAV。

### 小雅无法使用

先检查小雅容器状态和日志，再确认普通 Token、Open Token 和转存目录 ID 均已保存。授权文件为空时，重新登录管理后台完成初始化扫码。
