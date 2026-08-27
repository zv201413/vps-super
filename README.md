# ZVPS-Super

> 基于 **Ubuntu 22.04** 的「环境变量驱动」多服务容器镜像。
> 设好变量 → 服务自动拉起、配置自动生成、数据自动持久化，由 **Supervisor** 统一保活。

专为 **免费容器平台**（Koyeb / Railway / Render / Zeabur / HuggingFace Spaces 等，无 Docker 访问权、常无公网入站端口）以及**自建 Docker / VPS** 设计。一个镜像同时提供：SSH、Web 终端、Cloudflare 隧道、循环保活、流量统计、一次性安装注入，以及 **P2P 打洞的 Hysteria2 出站代理**。

镜像地址：`ghcr.io/zv201413/zvps:latest`（GitHub Actions 自动构建）

---

## 核心服务矩阵

| 服务 | 作用 | 触发变量 | 默认状态 | 端口 / 特性 |
| :--- | :--- | :--- | :---: | :--- |
| **sshd** | SSH 远程登录 | 始终开启 | ✅ ON | `22`（内部） |
| **ttyd** | 浏览器 Web 终端 | 始终开启 | ✅ ON | 默认 `7681`（镜像唯一 EXPOSE 端口） |
| **ttyd2** | 第二个 Web 终端 | `TTYD_P2` | ⬜ OFF | 自定义端口（常配合 CF 隧道） |
| **cloudflared** | Cloudflare 隧道 | `CF_TOKEN` | ⬜ OFF | 出站隧道，免公网 IP 暴露服务 |
| **kpal** | 循环 HTTP 保活 | `KPAL` | ⬜ OFF | 随机间隔请求，防容器休眠 |
| **komari** | 启动时一次性脚本/命令注入 | `KOMARI` | ⬜ OFF | 自动执行第三方 agent 安装脚本 |
| **hy2 (HYP2P)** | P2P 打洞 Hysteria2 出站代理 | `HYP2P` | ⬜ OFF | 无需公网入站端口，UDP 打洞直连 |

> 镜像仅 `EXPOSE 7681`，以避免 PaaS 平台将路由误绑定到 22 端口（原理详见 [原理与避坑清单 · EXPOSE 机制](docs/pitfalls.md#一镜像为什么只-expose-7681)）。

---

## 快速上手

### 1. 最小启动（SSH + Web 终端）

```bash
docker run -d --name zvps \
  -e SSH_PWD="改成你的密码" \
  -p 2222:22 -p 7681:7681 \
  ghcr.io/zv201413/zvps:latest
```

- **SSH**：`ssh zv@<host> -p 2222`（默认用户名 `zv`）
- **Web 终端**：`http://<host>:7681`

### 2. 典型组合启动（持久化 + 隧道 + 保活 + 流量统计）

```bash
docker run -d --name zvps \
  -e SSH_USER="zv" \
  -e SSH_PWD="改成你的密码" \
  -e TTYD_P1="7681:admin:终端密码" \
  -e CF_TOKEN="你的_cloudflare_tunnel_token" \
  -e KPAL="300:60:https://你的监控地址" \
  -e GB=true \
  -v /opt/zvps_data:/home/zv \
  -p 2222:22 -p 7681:7681 \
  --restart unless-stopped \
  ghcr.io/zv201413/zvps:latest
```

> **平台面板部署（Koyeb / Railway / Render / Zeabur 等）**：只需在环境变量面板填入对应 KEY/VALUE 即可，端口与持久卷按平台方式配置。

---

## 常用环境变量速查

### 管理与基础
| 变量 | 默认 | 格式 / 说明 |
| :--- | :--- | :--- |
| `SSH_USER` | `zv` | SSH 用户名，**决定持久化家目录**（`/home/<用户>`；设 `root` 为 `/root`） |
| `SSH_PWD` | `pwd123` | SSH 登录密码（公网暴露务必覆盖） |
| `TTYD_P1` | `7681` | 主终端，格式 `[端口]:[用户]:[密码]`（推荐 `7681:admin:密码`） |
| `TTYD_P2` | （关） | 次终端，格式同上（常配合 CF 隧道发布到 80 端口） |

### P2P 出站代理 `HYP2P`
| 变量 | 默认 | 格式 / 说明 |
| :--- | :--- | :--- |
| `HYP2P` | （关） | `<认证密码>:<混淆密码>:[进程伪装名]`（密码不可含冒号） |
| `HYP2P_RV` | 官方公共 | 牵线服务器 URI（留空自动使用公共 `realm.hy2.io`） |

### 扩展功能
| 变量 | 默认 | 格式 / 说明 |
| :--- | :--- | :--- |
| `CF_TOKEN` | （关） | Cloudflare Tunnel Token，免公网端口暴露服务 |
| `KPAL` | （关） | `[范围]:[偏移]:URL`，每轮等待 `RANDOM % 范围 + 偏移` 秒后请求一次 |
| `KOMARI` | （关） | 启动时执行一次的自定义命令 / 安装脚本（如第三方探针安装命令） |
| `GB` | （关） | 设为任意非空值开启流量统计（终端输入 `gb` 查看） |
| `FORCE_UPDATE` | （关） | 设为 `true` 强制在下次启动时重建服务配置（平时变量未变不重建，靠指纹比对） |

---

## 持久化挂载规范

容器的可写状态都落在 **`TARGET_HOME`** 下，**它由 `SSH_USER` 决定**：

| `SSH_USER` | `TARGET_HOME` | 挂载卷要挂到 |
| :--- | :--- | :--- |
| `zv`（默认） | `/home/zv` | `/home/zv` |
| 自定义 `foo` | `/home/foo` | `/home/foo` |
| `root` | `/root` | `/root` |

> ⚠️ **挂载路径必须与 `SSH_USER` 一致**，否则数据不落到持久卷。

`TARGET_HOME` 下会生成 / 持久化：

| 路径 | 内容 |
| :--- | :--- |
| `init_env.sh` | 流量统计初始化脚本（开 `GB` 时生成） |
| `boot/` | 自动生成的 supervisor 服务配置 |
| `supervisor/` | 自定义服务配置投放目录（`*.conf`） |
| `p2p/` | HYP2P 的 `realm_name`、`cert_sha256`、`client.example.yaml` |
| `vnstat_data/` | vnstat 流量数据库（软链） |

> 无持久盘平台（如 Koyeb）重启后凭据重新生成的影响与应对方案，见 [原理与避坑清单 · 持久化前提](docs/pitfalls.md#二hyp2p-的两个硬前提)。

---

## P2P 出站代理 (HYP2P) 操作流程

让容器在 NAT 后（**无需公网入站端口**）通过 **UDP 打洞**变成一个 **Hysteria2 出站代理落地**：本地使用 hy2 客户端经 P2P 直连进入，流量由容器 IP 出站（带 Salamander 混淆）。

### 1. 零配置启用（官方公共牵线）

设置环境变量 `HYP2P=认证密码:混淆密码:nginx`，留空 `HYP2P_RV`。
部署后在终端获取连接信息（路径中的 `/home/zv` 对应你的 `SSH_USER` 家目录）：

```bash
cat /home/zv/p2p/client.example.yaml   # 完整客户端配置文件，直接可用
cat /home/zv/p2p/realm_name            # 仅 realm 名
cat /home/zv/p2p/cert_sha256           # 证书指纹 (pinSHA256)
```

### 2. 客户端连接配置

将容器生成的 `client.example.yaml` 复制到本地，使用官方 [Hysteria 客户端](https://github.com/apernet/hysteria/releases) 启动即可。本地默认监听：
- **SOCKS5 代理**：`127.0.0.1:1080`
- **HTTP 代理**：`127.0.0.1:8080`

> 📖 **进阶配置与脚本**：
> - 自建牵线服务器操作、Windows 一键批处理脚本及客户端配置，详见 **[HYP2P 进阶与客户端配置 (docs/hyp2p-client.md)](docs/hyp2p-client.md)**。
> - NAT 打洞限制与 IPv6 优化、Scheme 选型判据见 [原理与避坑清单](docs/pitfalls.md#二hyp2p-的两个硬前提)。

---

## 日常运维与体检

| 操作 | 命令 | 说明 |
| :--- | :--- | :--- |
| 机器体检 | `vps` | 运行内置 VPS 硬件与网络体检工具箱 |
| 查流量 | `gb` | 需先开 `GB=true`，显示 eth0 RX/TX（MB+GB） |
| 看进程 | `sctl status` | `sctl` = 内置 supervisorctl |
| 重启服务 | `sctl restart <服务名>` | 服务名见 `sctl status` |
| 重载配置 | `sctl update` | 修改 `boot/` 或 `supervisor/*.conf` 后执行 |

### 机器体检 · `vps`

镜像内置了 VPS 硬件与网络体检工具箱，可直接在终端中运行：

```bash
vps          # 联网拉取最新版体检脚本并运行
vps -l       # 离线模式，运行上次缓存的体检脚本
vps -h       # 查看帮助说明
```

> ⚠️ **注意**：体检脚本为交互式菜单，**必须在真 TTY 环境下运行**（如 Web 终端或 SSH 交互终端）。无 TTY 死循环防范与软链设计详见 [原理与避坑清单 · vps 探针实踩记录](docs/pitfalls.md#四vps-探针的三个坑)。

---

## 深入文档

- **[HYP2P 进阶与客户端配置 (docs/hyp2p-client.md)](docs/hyp2p-client.md)** —— 自建牵线服务器 (hysteria-realm-server) 部署、Windows 一键批处理脚本模板与使用。
- **[原理与避坑清单 (docs/pitfalls.md)](docs/pitfalls.md)** —— 涵盖 EXPOSE 端口路由机制、HYP2P 持久化与 NAT 限制、Realm 协议 Scheme 判据、`vps` 探针无 TTY 死循环防范等底层原理与实踩记录。

---

## 构建与发布

- **基础镜像**：`ubuntu:22.04`
- **进程管理**：Supervisor（基础配置 `supervisord.conf`，各服务配置由 `entrypoint.sh` 按环境变量动态生成并 `include`）
- **CI**：`.github/workflows/build-image.yml`，推送即构建并发布到 GHCR：
  - `ghcr.io/<owner>/zvps:latest`
  - `ghcr.io/<owner>/zvps:<版本号>`

本地自构建：

```bash
git clone https://github.com/zv201413/zvps-super.git && cd zvps-super
docker build -t zvps:local .
```

---

## 鸣谢

参考 `vevc/ubuntu` 的设计思路，针对持久化挂载、流量统计、灵活保活与 P2P 出站代理做了深度定制。

