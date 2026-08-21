# ZVPS-Super

> 基于 **Ubuntu 22.04** 的「环境变量驱动」多服务容器镜像。
> 设好变量 → 服务自动拉起、配置自动生成、数据自动持久化，由 **Supervisor** 统一保活。

专为 **免费容器平台**（Koyeb / Railway / Render / Zeabur / HuggingFace Spaces 等，无 Docker 访问权、常无公网入站端口）以及**自建 Docker / VPS** 设计。一个镜像同时提供：SSH、Web 终端、Cloudflare 隧道、循环保活、流量统计、一次性安装注入、**P2P 打洞的 Hysteria2 出站代理**，以及 **EasyTier 异地组网**。

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
| **easytier (ET)** | 异地组网：UDP 打洞 P2P，TCP/WS/WSS 兜底 | `ET` | ⬜ OFF | `11010-11012`（可改） |

镜像 `EXPOSE 22 7681 11010-11012`；其余服务要么走出站隧道/打洞（无需入站端口），要么按你设的端口自行映射。

---

## 🔧 环境变量速查

### 核心 / SSH

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `SSH_USER` | `zv` | SSH 用户名，**同时决定持久化家目录**（见 [持久化](#-持久化)）。设为 `root` 走 root 模式 |
| `SSH_PWD` | `105106` | SSH 登录密码 ⚠️ **务必改掉默认值** |

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

### 异地组网 · ET

| 变量 | 必填 | 说明 |
| :--- | :---: | :--- |
| `ET` | ✅ | 总开关，格式 `<监听端口>:<网络名>:<密钥>:<虚拟IP>`。**网络名与密钥必填**且同一组网所有节点必须一致；虚拟 IP 可省略（省略则 DHCP 自动分配）。监听端口非数字时回落 `11010` |
| `ET_PEERS` | ⚠️ | 对端节点 URI，**逗号分隔**。不填也能启动，但只能发现同局域网节点 —— **异地组网必填** |
| `ET_MODE` | ❌ | `auto`（默认，自动探测 TUN）/ `tun`（强制）/ `notun`（强制无 TUN） |
| `ET_ARGS` | ❌ | 追加原生 `easytier-core` 参数（逃生阀），如 `--latency-first --compression zstd` |

> ⚠️ **网络名与密钥不能含冒号 `:`**（`ET` 用冒号分四段）。

监听端口按 `<端口>` / `+1` / `+2` 分配三种协议，例如 `ET=11010:...` 得到 udp+tcp `11010`、ws `11011`、wss `11012`。

同时设了 `CF_TOKEN` 时，可以把 ws 端口经 Cloudflare 隧道发布出去，让**没有任何入站端口的容器**也能被连 —— 见 [④ Cloudflare 隧道当入口](#-用-cloudflare-隧道当入口两端都没公网端口时)。

详见 [异地组网详解](#-异地组网-et-详解)。

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

## 🕸️ 异地组网 (ET) 详解

用 [EasyTier](https://github.com/EasyTier/EasyTier) 把分散在各地的容器 / VPS / 本地机器拉进**同一个虚拟局域网**，彼此用虚拟 IP（如 `10.126.126.x`）直接访问，无需公网 IP。

### ① 协议兜底链

EasyTier 默认开启 **UDP 打洞**，打通即 P2P 直连（最低延迟）。打不通则经对端节点中继。要让它在 UDP 被封时能自动落到 TCP / WS，**把同一个节点用多种协议写进 `ET_PEERS`**：

```bash
ET_PEERS="udp://1.2.3.4:11010,tcp://1.2.3.4:11010,ws://1.2.3.4:11011"
```

| 协议 | 用途 | 特点 |
| :--- | :--- | :--- |
| `udp://` | **首选**，UDP 打洞 P2P 直连 | 延迟最低；对称 NAT 或封 UDP 时失效 |
| `tcp://` | UDP 不通时兜底 | 稳定，走中继时略高延迟 |
| `ws://` | TCP 也被限制时兜底 | 伪装成 HTTP 流量，穿透性最好 |
| `wss://` | 同上 + TLS | 证书由 EasyTier 自动生成，无需配置 |

本镜像的**监听侧四协议全开**，所以对端可用任意协议接入本节点。

> `ET_PEERS` 官方原生只认逗号分隔（空格会静默解析成 **0 条**）；本镜像放宽为逗号和空格都接受。

### ② TUN 自动降级（免费 PaaS 关键）

组网本需 TUN 设备，但免费 PaaS 通常给不了。启动时会自动探测**两个**条件——`/dev/net/tun` 存在（不存在则尝试 `mknod` 创建）**且** 进程持有 `NET_ADMIN` 能力（读 `/proc/self/status` 的 `CapEff` 第 12 位）。只看设备节点是不够的：多数 PaaS 恰好是「节点在、能力无」，此时建 TUN 仍会失败。

| 模式 | 触发条件 | 能力 |
| :--- | :--- | :--- |
| **TUN 模式** | 有 `/dev/net/tun` + `NET_ADMIN` | 完整三层互通，双向任意协议 |
| **无 TUN 模式** | 缺任一条件（自动降级） | 自动加 `--no-tun --use-smoltcp`；**其他节点仍可访问本容器内的服务** |

> ⚠️ **无 TUN 模式是单向的**：远端节点能访问容器内服务（实测可用），但**容器自己主动访问组网内其他节点不可用** —— 那需要 TUN 或 SOCKS5 出口（SOCKS5 暂未接入）。
>
> 自建 Docker 想要完整互通，加上：`--cap-add NET_ADMIN --device /dev/net/tun`。

### ③ 两节点组网示例

**节点 A —— 有公网 IP 的 VPS**（当中继/牵线，别的节点连它）：

```bash
docker run -d --name zvps-a \
  -e SSH_PWD="你的密码" \
  -e ET="11010:mynet:mysecret:10.126.126.1" \
  -p 11010:11010 -p 11010:11010/udp -p 11011:11011 -p 11012:11012 \
  --cap-add NET_ADMIN --device /dev/net/tun \
  --restart unless-stopped \
  ghcr.io/zv201413/zvps:latest
```

**节点 B —— 免费 PaaS 容器**（无入站端口，连 A）：

```bash
ET=11010:mynet:mysecret:10.126.126.2
ET_PEERS=udp://<A的公网IP>:11010,tcp://<A的公网IP>:11010,ws://<A的公网IP>:11011
```

两端 `mynet` / `mysecret` 必须一致。B 起来后，A 上可以直接 `ssh zv@10.126.126.2` 或访问 `http://10.126.126.2:7681`。

虚拟 IP 想让 EasyTier 自动分配就省掉第四段：`ET=11010:mynet:mysecret`（走 DHCP，从 `10.0.0.1` 起）。

### ④ 用 Cloudflare 隧道当入口（两端都没公网端口时）

当**两端都开不了入站端口**（SAP BTP 只放行 80/443、Koyeb / Render 同理），就没有任何一端能当 A。此时用已有的 `CF_TOKEN` 隧道把组网端口发布出去 —— **不需要额外端口、不需要改镜像**。

EasyTier 的 `wss` 就是为这个设计的：**容器内监听明文 `ws`，TLS 由 CF 边缘提供，对端用 `wss` 连**。两端协议不对称是正常的，官方 `--help` 里 `wss` 的说明正是「配置服务器 ws 被代理为 wss 时」。

**容器侧**（同时设 `CF_TOKEN` 和 `ET` 即可，启动横幅会把下面这些值直接打印出来）：

```bash
CF_TOKEN=你的隧道token
ET=11010:mynet:mysecret:10.126.126.1
```

**CF 面板**（Zero Trust → Networks → Tunnels → 你的隧道 → Public Hostname → Add）：

| 字段 | 填什么 |
| :--- | :--- |
| 子域 / 域 | 例如 `krttyd` / `zvtd.cc.cd`，路径留空 |
| 类型 | **HTTP** |
| Service URL | `localhost:11011` ← **ws 端口，是 `ET` 端口 +1，不是 11010** |

**对端**（任何机器，不用装 cloudflared）：

```bash
ET=11010:mynet:mysecret:10.126.126.2
ET_PEERS=wss://krttyd.zvtd.cc.cd:443
```

> ⚠️ **不要给这条主机名加 Cloudflare Access 应用**。Access 会要求浏览器 OAuth 登录，`Allow + Everyone` 也一样要走登录流程（只有 `Bypass` 才不拦），而 EasyTier 不是浏览器，握手会被跳转到登录页而失败。组网的准入靠的是**网络名 + 密钥**，本身就是凭证。

**两种隧道类型的取舍**：

| 类型 | Service 填 | 对端要求 | 评价 |
| :--- | :--- | :--- | :---: |
| **HTTP** | `localhost:11011`（ws 口） | 直接 `wss://域名:443` | ✅ 对端零依赖 |
| **TCP** | `tcp://localhost:11010` | 先跑 `cloudflared access tcp --hostname 域名 --url 127.0.0.1:21010`，再连 `tcp://127.0.0.1:21010` | ⚠️ 每台对端都要装 cloudflared 并常驻 |

> ⚠️ **走 TCP 类型时，`--url` 的本地端口不要用 11010**：本机 easytier 自己默认也监听 `0.0.0.0:11010`，会撞成 `Address in use` 而整个实例启动失败。换个端口（如 21010），或给本机 easytier 显式指定 `-l tcp://0.0.0.0:21011`。

**实测记录**：

- **TCP 类型 + `cloudflared access tcp`** —— 在真实环境跑通（SAP BTP 新加坡容器 ↔ 家庭宽带）。SAP 侧只设 `CF_TOKEN` + `ET`，容器无 TUN 自动降级 `--no-tun --use-smoltcp`；本机经 socks5 访问到容器内 ttyd，返回真实响应头 `server: ttyd/1.7.3`。`peer` 表 `tunnel=tcp`、`loss=0.0%`、路由 `DIRECT`，**延迟约 550 ms**（流量绕 Cloudflare 边缘 + 本地 cloudflared 中转两跳）。
- **HTTP 类型 + `wss`** —— 用 TLS 终止 + HTTP 头重建的反代精确模拟 CF 链路验证：握手穿过 HTTP 层重建后返回 `101 Switching Protocols`，B 端 `tunnel=wss` / A 端 `tunnel=ws`，路由 `DIRECT`，真实载荷到达容器内服务。EasyTier 的 `wss` 客户端不校验证书，CF 的有效证书自然无碍。

> **这是中转不是 P2P**：cloudflared 只传 TCP/HTTP，**UDP 打洞在这条路上完全用不上**，全部流量绕行 Cloudflare 边缘，延迟远高于直连（实测 550 ms）、带宽受 CF 限制。CF 免费版对代理非网页流量另有 ToS 约束（第 2.8 条），当常规链路跑大流量有风险。**只要有一端能开入站端口，就优先用 ③ 的直连方式**，把这条留作兜底。

> ⚠️ **`ET_*` 是 EasyTier 的原生环境变量命名空间**：`easytier-core` 自己会读 `ET_SOCKS5`、`ET_PEERS` 等同名变量。本镜像的参数都以命令行显式传入（优先级高于 env），但**残留的 `ET_*` 变量仍可能生效** —— 例如遗留一个 `ET_SOCKS5=12333`，容器就会额外开一个 socks5 出口。换方案时记得把用不到的 `ET_*` 变量删干净。

### ⑤ 旧镜像不想重建？运行时装

已经在跑的旧镜像（没有 `easytier` 二进制）不必重新部署，用 `KOMARI` 在启动时装一次即可 —— 镜像里 `curl` 和 `unzip` 都是现成的：

```bash
KOMARI=bash -c 'curl -fsSL https://github.com/EasyTier/EasyTier/releases/download/v2.6.4/easytier-linux-x86_64-v2.6.4.zip -o /tmp/et.zip && unzip -qo /tmp/et.zip -d /tmp/et && find /tmp/et -name "easytier-*" -exec install -m755 {} /usr/local/bin/ \; && nohup easytier-core --network-name mynet --network-secret mysecret -i 10.126.126.1 -l ws://0.0.0.0:11011 --no-tun --use-smoltcp >/var/log/et.log 2>&1 &'
```

跑起来后 CF 面板照上面 ④ 配 `localhost:11011` 即可。这是应急手段：没有 supervisor 保活、进程挂了不会拉起，长期还是换新镜像用 `ET` 变量。

### ⑥ 查看状态

```bash
easytier-cli peer     # 对端列表：隧道协议(udp/tcp/ws/wss)、p2p 还是中继、延迟、丢包
easytier-cli route    # 路由表：各节点虚拟 IP、下一跳、路径长度
tail -f /var/log/easytier.err.log
sctl status easytier  # supervisor 里的进程状态
```

`peer` 表的 `cost` 列是 `p2p` 说明打洞成功（直连）；显示中继节点名则说明走了中继。`tunnel` 列是实际使用的协议。

### ⚠️ 注意事项

- **必须自备对端节点**：官方公共节点 `public.easytier.cn` **已无 DNS A 记录**（实测解析失败），镜像因此不内置任何默认公共节点。用你自己的公网 VPS 当节点最可靠；**两端都没有公网端口时走 [④ Cloudflare 隧道](#-用-cloudflare-隧道当入口两端都没公网端口时)**，或自行寻找可用的社区公共节点填进 `ET_PEERS`。
- **网络名 / 密钥不能含冒号**：`ET` 靠冒号分四段。建议只用字母数字和 `-`。
- **NAT 类型决定能否 P2P**：一端对称 NAT（随机端口）且另一端非公网/全锥型时，UDP 打洞**可能失败**，此时自动走中继（功能正常，延迟和带宽受中继节点限制）。
- **密钥即入网凭证**：任何拿到网络名 + 密钥的人都能进你的组网，请当密码对待。

---

## 🛠️ 运维与管理

| 操作 | 命令 | 说明 |
| :--- | :--- | :--- |
| 查流量 | `gb` | 需先开 `GB=true`，显示 eth0 RX/TX（MB+GB） |
| 看进程 | `sctl status` | `sctl` = 内置 supervisorctl |
| 重启服务 | `sctl restart kpal` | 服务名见 `sctl status` |
| 重载配置 | `sctl update` | 修改 `boot/` 或 `supervisor/*.conf` 后执行 |
| 看组网 | `easytier-cli peer` | 需先开 `ET`，查看对端与隧道协议 |

镜像启动后会在 `TARGET_HOME` 生成 `init_env.sh` 与 `boot/` 下的服务配置；改动后 `sctl update` 生效，或设 `FORCE_UPDATE=true` 重启重建。

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
