# ZVPS-Super

> 基于 **Ubuntu 22.04** 的「环境变量驱动」多服务容器镜像。
> 设好变量 → 服务自动拉起、配置自动生成、数据自动持久化，由 **Supervisor** 统一保活。

专为 **免费容器平台**（Koyeb / Railway / Render / Zeabur / HuggingFace Spaces 等，无 Docker 访问权、常无公网入站端口）以及**自建 Docker / VPS** 设计。一个镜像同时提供：SSH、Web 终端、Cloudflare 隧道、循环保活、流量统计、一次性安装注入，以及 **P2P 打洞的 Hysteria2 出站代理**。

---

## 📦 镜像地址

```
ghcr.io/zv201413/zvps:latest
```

> CI 每次推送自动构建并发布到 GHCR（见 [构建与发布](#-构建与发布)）。

---

## ⚡ 60 秒上手

### 最小启动（SSH + Web 终端）

```bash
docker run -d --name zvps \
  -e SSH_PWD="改成你的密码" \
  -p 2222:22 -p 7681:7681 \
  ghcr.io/zv201413/zvps:latest
```

- SSH：`ssh zv@<host> -p 2222`（默认用户 `zv`）
- Web 终端：`http://<host>:7681`

### 全功能启动（持久化 + 隧道 + 保活 + 流量）

```bash
docker run -d --name zvps \
  -e SSH_USER="zv" \
  -e SSH_PWD="改成你的密码" \
  -e GB=true \
  -e KPAL="300:60:https://你的监控地址" \
  -e CF_TOKEN="你的 cloudflare token" \
  -e TTYD_P1="7681:admin:终端密码" \
  -v /opt/zvps_data:/home/zv \
  -p 2222:22 -p 7681:7681 \
  --restart unless-stopped \
  ghcr.io/zv201413/zvps:latest
```

> 平台面板部署（Koyeb/Railway 等）：把上面的 `-e KEY="value"` 逐条填进环境变量面板即可，端口和持久卷按平台方式配置。

---

## 🧩 服务一览

| 服务 | 作用 | 由谁开启 | 默认 | 端口 |
| :--- | :--- | :--- | :---: | :---: |
| **sshd** | SSH 登录 | 始终开启 | ✅ ON | `22` |
| **ttyd** | 浏览器 Web 终端 | 始终开启（可配置） | ✅ ON | `7681` |
| **ttyd2** | 第二个 Web 终端 | `TTYD_P2` | ⬜ OFF | 自定义 |
| **cloudflared** | Cloudflare 隧道（免公网 IP 暴露服务） | `CF_TOKEN` | ⬜ OFF | 出站 |
| **kpal** | 循环 HTTP 保活（防平台休眠） | `KPAL` | ⬜ OFF | — |
| **komari** | 启动时执行一次任意命令 / 安装脚本 | `KOMARI` | ⬜ OFF | — |
| **hy2 (HYP2P)** | P2P 打洞的 Hysteria2 出站代理落地 | `HYP2P` | ⬜ OFF | 无入站（打洞） |

镜像 `EXPOSE 7681`；其余服务要么走出站隧道/打洞（无需入站端口），要么按你设的端口自行映射。

---

## 🔧 环境变量速查

### 核心 / SSH

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `SSH_USER` | `zv` | SSH 用户名，**同时决定持久化家目录**（见 [持久化](#-持久化)）。设为 `root` 走 root 模式 |
| `SSH_PWD` | `pwd123` | SSH 登录密码 ⚠️ **务必改掉默认值** |

### 保活 · KPAL

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `KPAL` | （关） | 循环保活，格式 `范围:偏移:URL`。每轮随机等待 `RANDOM % 范围 + 偏移` 秒再请求一次 |

格式可缺省：`300::URL`（偏移默认 60）、`:60:URL`（范围默认 300）、`URL`（范围 300 / 偏移 60）。

### 流量统计 · GB

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `GB` | （关） | 设任意非空值即开启：自动装 `vnstat`、把数据库软链到持久目录、注入 `gb` 快捷命令 |

开启后在终端输入 `gb` 查看 eth0 的 RX/TX（MB + GB 双显）。

### Cloudflare 隧道 · CF_TOKEN

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `CF_TOKEN` | （关） | 填入 Cloudflare Tunnel token 即自动激活 `cloudflared`，无需暴露公网端口 |

配合 `TTYD_P2=80:用户:密码` 可把 Web 终端经隧道发布到 80 端口（CF 控制台 Public Hostname 选 `HTTP`、URL 填 `localhost:80`）。

### Web 终端 · TTYD

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `TTYD_P1` | `7681`（无密码） | 第一个 Web 终端，格式 `端口:用户名:密码`（用户/密码可省略） |
| `TTYD_P2` | （关） | 第二个 Web 终端，格式同上（常用于配合 CF 隧道） |
| `TTYD` / `TTYD_PORT` | — | 旧变量，向后兼容；`TTYD_P1` 未设时回退使用 |

> 🔒 建议始终给终端设密码：`TTYD_P1=7681:admin:你的密码`。

### 一次性注入 · KOMARI

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `KOMARI`（或小写 `komari`，大写优先） | （关） | 容器启动时由 supervisor 执行一次该命令（`autorestart=false`，失败不重试），完成即退出 |

典型用途：拉起监控 agent 安装脚本。

```
KOMARI=wget -qO- https://raw.githubusercontent.com/zv201413/komari-agent_new/refs/heads/main/install.sh | bash -s -- -e <ENDPOINT> -t <TOKEN>
```

### P2P 出站代理 · HYP2P

| 变量 | 必填 | 说明 |
| :--- | :---: | :--- |
| `HYP2P` | ✅ | 总开关，格式 `<认证密码>:<混淆密码>:<进程伪装名>`。auth 留空=关闭；obfs 可空（不混淆）；进程名可空（默认 `hy2`，可设 `nginx` 等规避按进程名检测） |
| `HYP2P_RV` | ❌ | 牵线（rendezvous）服务器 URI。**留空 → 自动用官方公共 `realm.hy2.io`**；填则用自建 |

> ⚠️ **密码不能含冒号 `:`**（`HYP2P` 用冒号分三段）。请只用字母数字和 `-`，如 `koyeb-udp-p2p123`。

详见 [P2P 出站代理详解](#-p2p-出站代理-hyp2p-详解)。

### 维护 · FORCE_UPDATE

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `FORCE_UPDATE` | （关） | 设为 `true` 强制在下次启动时重建服务配置（平时变量未变不会重建，靠指纹比对自动触发） |

---

## 💾 持久化

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
| `supervisor/` | 你自己的服务配置投放目录（`*.conf`） |
| `p2p/` | HYP2P 的 `realm_name`、`cert_sha256`、`client.example.yaml` |
| `vnstat_data/` | vnstat 流量数据库（软链） |

无持久卷的平台（如 Koyeb）重启后这些会重新生成——对 HYP2P 影响见下。

---

## 🌐 P2P 出站代理 (HYP2P) 详解

让容器在 NAT 后（**无需公网入站端口**）通过 **UDP 打洞**变成一个 **Hysteria2 出站代理落地**：你在本地用 hy2 客户端经 P2P 直连进来，流量从容器 IP 出站，全程带 Salamander 混淆。适合 Koyeb / Render / Zeabur 等开不了入站端口的平台。

### ① 零配置（公共牵线）

只设 `HYP2P=认证密码:混淆密码:nginx`，不填 `HYP2P_RV`。容器自动用公共 `realm.hy2.io` 并**生成随机 realm 名**（持久化，重启不变）。部署后在 SSH / Web 终端里拿连接信息（路径中的 `/home/zv` 换成你的 `SSH_USER` 家目录）：

```bash
cat /home/zv/p2p/client.example.yaml   # 一份填好的本地 client 配置，直接用
cat /home/zv/p2p/realm_name            # 仅 realm 名
cat /home/zv/p2p/cert_sha256           # 证书指纹 (pinSHA256)
```

启动日志也会打印含 realm 名 / Server URI / pinSHA256 的横幅。

### ② 本地客户端怎么连（自签证书）

容器作为 hy2 server 用**自签证书**，指纹是容器内现生成的、事先不知道。`client.example.yaml` 已自动填好 `tls.insecure: true` + `tls.pinSHA256`（锁死指纹防 MITM），并监听本地 **SOCKS5 `127.0.0.1:1080`**、**HTTP `127.0.0.1:8080`**。把它拿到本地当 `client.yaml`，用官方 hysteria 客户端启动即可。

### ③ 自建牵线服务器

在一台**公网机器**上跑 [hysteria-realm-server](https://github.com/apernet/hysteria-realm-server)，把 `HYP2P_RV` 填成它的 URI：

```bash
git clone https://github.com/apernet/hysteria-realm-server.git && cd hysteria-realm-server
docker build -t hy-realm .
docker run -d --name hy-realm --restart unless-stopped -p 8443:8443 \
  -e HYSTERIA_REALM_TOKEN="你的token" -e HYSTERIA_REALM_LISTEN=":8443" hy-realm
# 放行防火墙 TCP 8443
```

> ⚠️ **`realm://` 还是 `realm+http://`？必看**：上面这样跑**没配 TLS**，`HYP2P_RV` 必须用 **`realm+http://你的token@IP:8443/名字`**；用 `realm://`（HTTPS）会握手失败！只有给牵线服务器配了 TLS（域名+证书 / Caddy 反代自动签）才用 `realm://`。公共 `realm.hy2.io` 是 HTTPS，故用 `realm://`（留空即自动）。

### ④ Windows 一键批处理

容器部署后，SSH 进去拿连接信息，按以下步骤在本地创建一键启动脚本。

**前提：** 将 [hysteria-windows-amd64.exe](https://github.com/apernet/hysteria/releases/latest/download/hysteria-windows-amd64.exe) 放到桌面 `hysteria\` 目录下。

**第一步：在容器 SSH 终端获取信息**
```bash
cat /home/zv/p2p/client.example.yaml   # 查看完整客户端配置
cat /home/zv/p2p/realm_name            # 只拿 realm 名
cat /home/zv/p2p/cert_sha256           # 只拿证书指纹
```

**第二步：创建 `桌面\hy2-隧道.bat`，替换三行变量为你的值：**

```batch
@echo off
title Hysteria2 P2P Tunnel

:: 改下面三行为你容器的值
set REALM=xxx       REM cat /home/zv/p2p/realm_name
set AUTH=xxx        REM HYP2P 认证密码
set PIN=xxx         REM cat /home/zv/p2p/cert_sha256

taskkill /f /im hysteria.exe >nul 2>&1
cd /d "%~dp0hysteria"

(
echo server: realm://public@realm.hy2.io/%REALM%
echo auth: %AUTH%
echo tls:
echo   insecure: true
echo   pinSHA256: %PIN%
echo socks5:
echo   listen: 127.0.0.1:25002
) > tunnel.yaml

echo Starting Hysteria2 P2P...
start /b hysteria.exe client -c tunnel.yaml > tunnel.log 2>&1
timeout /t 3 /nobreak >nul
echo SOCKS5: 127.0.0.1:25002
pause
```

**使用：** 双击运行 → 自动打洞建立 P2P 直连，浏览器/应用设 SOCKS5 `127.0.0.1:25002` 即可。再次双击同一脚本 = 停止隧道。

> ⚠️ **无持久卷平台（Koyeb 等）重启后**，realm 名和证书指纹会重新生成，需重新 `cat` 并更新 bat 中的三行变量。

### ⚠️ 两个硬前提

- **持久化**：realm 名与证书指纹存在 `$TARGET_HOME/p2p`。**Koyeb 等无持久盘平台**重启会重新生成 → 本地 client 需重抄。想稳定就挂持久卷，或显式设 `HYP2P_RV`（固定 realm 名）+ 本地只用 `insecure: true`（不 pin 指纹）。
- **NAT 类型**：UDP 打洞有硬限制 —— 只要**一端对称 NAT（随机端口）**且另一端非公网 IP/全锥型，就**可能打不通**。公共 `realm.hy2.io` 为免费 best-effort，可能宕机/被墙。若本地有 **IPv6**，强制客户端走 v6（只填 v6 STUN）可绕过 v4 CGNAT、显著提升成功率与稳定性。

---

## 🛠️ 运维与管理

| 操作 | 命令 | 说明 |
| :--- | :--- | :--- |
| 查流量 | `gb` | 需先开 `GB=true`，显示 eth0 RX/TX（MB+GB） |
| 机器体检 | `vps` | VPS 硬件与网络体检工具箱（见下） |
| 看进程 | `sctl status` | `sctl` = 内置 supervisorctl |
| 重启服务 | `sctl restart kpal` | 服务名见 `sctl status` |
| 重载配置 | `sctl update` | 修改 `boot/` 或 `supervisor/*.conf` 后执行 |

镜像启动后会在 `TARGET_HOME` 生成 `init_env.sh` 与 `boot/` 下的服务配置；改动后 `sctl update` 生效，或设 `FORCE_UPDATE=true` 重启重建。

### 机器体检 · vps

镜像内置了 VPS 硬件与网络体检工具箱，可直接在终端中运行：

```bash
vps          # 联网拉取最新版体检脚本并运行
vps -l       # 离线模式，运行上次缓存的体检脚本
vps -h       # 查看帮助说明
```

> ⚠️ **注意**：体检脚本为交互式菜单，**必须在真 TTY 环境下运行**（如 Web 终端或 SSH 交互终端，不可通过 `cf ssh <app> -T -c 'vps'` 无 TTY 方式调用）。

---

## 🏗️ 构建与发布

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

## 🤝 鸣谢

参考 `vevc/ubuntu` 的设计思路，针对持久化挂载、流量统计、灵活保活与 P2P 出站代理做了深度定制。
