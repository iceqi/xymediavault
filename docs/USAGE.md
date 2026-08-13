# XyMediaVault 使用文档

## 1. 安装前准备

支持以下 Linux 架构：

- `amd64/x86_64`
- `arm64/aarch64`
- `arm/v7`

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

建议提前放行需要使用的端口。默认管理后台为 `18080`，WebDAV 为 `18081`，TVBox 为 `18082`，小雅 Alist 为 `5678`，小雅管理和代理端口为 `2345`、`2346`。

## 2. 统一安装器

下载仓库或 release bundle 后执行：

```bash
git clone --branch beta https://github.com/iceqi/xymediavault.git
cd xymediavault
bash scripts/install.sh
```

必须下载完整 bundle；不要只下载 `install.sh`，因为入口依赖 `scripts/lib`。

无参数脚本只有在 stdin/stdout 都是 TTY 时进入菜单；pipe 环境显示帮助并返回 2。完整 bundle 必须包含 `scripts/lib`，不要只下载入口文件。

标准子命令：

```bash
bash scripts/install.sh vault install --channel stable --dir /opt/xymediavault --non-interactive
bash scripts/install.sh vault upgrade --channel stable --yes
bash scripts/install.sh title install --channel beta --yes
bash scripts/install.sh env
bash scripts/install.sh version
bash scripts/install.sh status --json
```

### 菜单与通道

| 参数 | 说明 | 建议值 |
| --- | --- | --- |
| 第一个位置参数 | 安装目录，即配置、数据库和小雅文件目录 | 执行脚本时的当前目录 |
| `IMAGE` | XyMediaVault Docker 镜像 | `iceqi/xymediavault:latest` |
| `PUBLIC_HOST` | 用户访问服务时使用的 IP 或域名 | 自动检测服务器 IP |
| `API_PORT` | 管理后台端口 | `18080` |
| `WEBDAV_PORT` | WebDAV 端口 | `18081` |
| `TVBOX_PORT` | TVBox 公共服务端口 | `18082` |
| `XIAOYA_PORT` | 小雅 Alist 端口 | `5678` |
| `XIAOYA_ADMIN_PORT` | 小雅管理端口 | `2345` |
| `XIAOYA_PROXY_PORT` | 小雅代理端口 | `2346` |
| `FORCE_PULL` | 是否忽略本地镜像并强制拉取 | `false` |

菜单数字固定为 1-10 和 0 退出。stable 使用 Vault `latest`、TMM `latest`、Title `stable`；beta 使用三个对应的 `beta` 标签。`.xymedia-channel` 保存安装通道，升级通过 pull 和容器状态检查判断结果，网络/registry 不可用时不声称“最新”。

环境变量只修改交互提示中的建议值，脚本仍会要求用户确认。例如：

```bash
PUBLIC_HOST=192.168.1.10 \
API_PORT=18080 \
WEBDAV_PORT=18081 \
TVBOX_PORT=18082 \
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

## 4. 媒体索引与扫描

系统从 HTTP Index 扫描目录和文件路径，并在 SQLite 中建立统一媒体索引。扫描完成后，媒体资源页、WebDAV、FUSE 和 TVBox 都从本地索引读取目录结构，不会因为客户端反复浏览而递归请求远程源站。

扫描只保存目录、文件名、文件类型、大小、修改时间和远程路径，不下载视频。存储边界如下：

- STRM 文本第一次打开时从远程读取，并缓存解析后的相对播放路径。
- NFO、海报和字幕只保存索引路径，打开时按需从可用源站读取。
- 完整播放 URL 不写入媒体数据库，由绑定的播放服务动态生成。
- 定时扫描会增量写入新增内容，并把远程已不存在的条目标记为不可用。

媒体资源页可以清空 STRM 内容缓存；该操作不会删除目录和文件索引，下次打开对应 STRM 时会重新读取。

## 5. WebDAV

默认地址：

```text
http://服务器IP:18081/dav
```

在管理后台创建 WebDAV 账号并设置目录权限。WebDAV 返回已扫描的统一媒体索引，可为账号配置允许访问的路径前缀和是否显示隐藏目录。目录为空时，请先确认索引源可用并在媒体资源页执行扫描。

## 6. FUSE

默认宿主机挂载目录：

```text
/opt/xymediavault/mnt/xymediavault
```

FUSE 依赖：

- `/dev/fuse`
- 容器 `SYS_ADMIN` capability
- `rshared` 挂载传播

安装脚本会自动验证 `/dev/fuse`、Docker 运行模式、`SYS_ADMIN`、AppArmor 和 `rshared` bind。检测通过时才生成安装器管理的 FUSE Compose 配置；检测不可用时不会授予相关高权限，管理后台、WebDAV 和 TVBox 仍可使用。实际挂载和卸载继续由管理后台控制。

## 7. 更新与 Title

使用统一子命令：

```bash
bash scripts/install.sh vault check
bash scripts/install.sh vault upgrade --channel stable --yes
bash scripts/install.sh title check
```

Vault 更新保留数据、配置、FUSE 目录和 TMM；切换通道会备份数据库并在健康检查失败时恢复旧 Compose。独立 Title 不抢占 Vault 的 `xymedia-title`，只使用 `xymedia-title-standalone`。Vault-owned Title 必须从 Vault 管理接口升级，独立脚本拒绝删除它。

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
/opt/xymediavault/emby/config/
/opt/xymediavault/tmm/data/
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

重新执行安装脚本，在交互步骤中修改对应的宿主机端口。不要修改容器内部的 `8080`、`8081` 和 `8082`。

### 中文目录提示 `project name must not be empty`

新版安装脚本会固定使用 `xymediavault` 作为 Compose 项目名，中文、空格或特殊字符目录均可正常安装。遇到该错误时，重新执行最新的一键安装命令即可。

### 更新时卡在 FUSE 挂载

安装脚本会先停止 XyMediaVault 并尝试清理旧挂载。如果仍然失败，可以执行：

```bash
umount -l /opt/xymediavault/mnt/xymediavault
```

确认目录不再是挂载点后，再重新运行安装脚本。

### WebDAV 看不到文件

WebDAV 只展示已扫描的统一索引。请先确认“索引源”中至少有一个源可用，在媒体资源页扫描目标目录，然后重新连接 WebDAV。

### 小雅无法使用

先检查小雅容器状态和日志，再确认普通 Token、Open Token 和转存目录 ID 均已保存。授权文件为空时，重新登录管理后台完成初始化扫码。
