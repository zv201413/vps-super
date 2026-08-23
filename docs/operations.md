# ZVPS-Super 操作篇

**本篇只有步骤。** 为什么这么设计、坑怎么认、实测数字 → [原理与坑点](pitfalls.md)。
UDP 打洞的机制 → [nat-punching.md](nat-punching.md)。总入口 → [README](../README.md)。

镜像：`ghcr.io/zv201413/zvps:latest`

---

## 一、部署

### 1.1 最小启动（SSH + Web 终端）

```bash
docker run -d --name zvps \
  -e SSH_PWD="改成你的密码" \
  -p 2222:22 -p 7681:7681 \
  ghcr.io/zv201413/zvps:latest
```

- SSH：`ssh zv@<host> -p 2222`（默认用户 `zv`）
- Web 终端：`http://<host>:7681`

### 1.2 全功能启动（持久化 + 隧道 + 保活 + 流量）

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

### 1.3 平台面板部署（Koyeb / Railway / Render / Zeabur 等）

把上面的 `-e KEY="value"` 逐条填进环境变量面板，端口与持久卷按平台方式配置。

---

## 二、环境变量全表

### 2.1 核心 / SSH

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `SSH_USER` | `zv` | SSH 用户名，**同时决定持久化家目录**（见 §三）。设为 `root` 走 root 模式 |
| `SSH_PWD` | `pwd123` | SSH 登录密码。镜像公开，此默认值等同公开；22 端口在 CF 上不对外路由，但**若给它配了 TCP Proxy，务必用环境变量覆盖** |

### 2.2 保活 `KPAL`

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `KPAL` | （关） | 循环保活，格式 `范围:偏移:URL`。每轮随机等待 `RANDOM % 范围 + 偏移` 秒再请求一次 |

三段都可缺省：`300::URL`（偏移默认 60）、`:60:URL`（范围默认 300）、`URL`（300 / 60）。

### 2.3 流量统计 `GB`

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `GB` | （关） | 设任意非空值即开启：装 `vnstat`、数据库软链到持久目录、注入 `gb` 快捷命令 |

开启后终端敲 `gb` 看 eth0 的 RX/TX（MB + GB 双显）。

### 2.4 Cloudflare 隧道 `CF_TOKEN`

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `CF_TOKEN` | （关） | 填 Cloudflare Tunnel token 即自动激活 `cloudflared`，无需暴露公网端口 |

配合 `TTYD_P2=80:用户:密码` 可把 Web 终端经隧道发布到 80 端口（CF 控制台 Public Hostname 选 `HTTP`、URL 填 `localhost:80`）。

### 2.5 Web 终端 `TTYD`

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `TTYD_P1` | `7681`（无密码） | 第一个 Web 终端，格式 `端口:用户名:密码`（用户/密码可省略） |
| `TTYD_P2` | （关） | 第二个 Web 终端，格式同上（常配合 CF 隧道） |
| `TTYD` / `TTYD_PORT` | — | 旧变量，向后兼容；`TTYD_P1` 未设时才回退用它 |

> 🔒 始终给终端设密码：`TTYD_P1=7681:admin:你的密码`。

### 2.6 一次性注入 `KOMARI`

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `KOMARI`（或小写 `komari`，大写优先） | （关） | 启动时由 supervisor 执行一次该命令（`autorestart=false`，失败不重试），完成即退出 |

典型用途：拉监控 agent 的安装脚本。

```
KOMARI=wget -qO- https://raw.githubusercontent.com/zv201413/komari-agent_new/refs/heads/main/install.sh | bash -s -- -e <ENDPOINT> -t <TOKEN>
```

### 2.7 P2P 出站代理 `HYP2P`

| 变量 | 必填 | 说明 |
| :--- | :---: | :--- |
| `HYP2P` | ✅ | 总开关，格式 `<认证密码>:<混淆密码>:<进程伪装名>`。auth 留空=关闭；obfs 可空（不混淆）；进程名可空（默认 `hy2`，可设 `nginx` 等规避按进程名检测） |
| `HYP2P_RV` | ❌ | 牵线（rendezvous）服务器 URI。**留空 → 自动用官方公共 `realm.hy2.io`**；填则用自建 |

> ⚠️ **密码不能含冒号 `:`**（靠冒号分三段）。只用字母数字和 `-`，如 `koyeb-udp-p2p123`。

### 2.8 异地组网 `ET`

| 变量 | 必填 | 说明 |
| :--- | :---: | :--- |
| `ET` | ✅ | 总开关，格式 `<监听端口>:<网络名>:<密钥>:<虚拟IP>`。**网络名与密钥必填**且同组网所有节点一致；虚拟 IP 可省略（省则 DHCP），**也可只写最后一段**（`:2` = `10.126.126.2`）。监听端口非数字时回落 `11010` |
| `ET_PEERS` | ⚠️ | 对端节点 URI，**逗号分隔**。不填也能启动，但只能发现同局域网节点 —— **异地组网必填** |
| `ET_MODE` | ❌ | `auto`（默认，自动探测 TUN）/ `tun`（强制）/ `notun`（强制无 TUN） |
| `ET_SUBNET` | ❌ | 默认 `10.126.126`。虚拟 IP 只写最后一段时用它补前三段 |
| `ET_ARGS` | ❌ | 追加原生 `easytier-core` 参数（逃生阀），如 `--latency-first --compression zstd` |
| `PUNCH` | ❌ | UDP 打洞守护，**两侧角色不同**：Port-Restricted/Cone 侧填 `auto`（做扫射），Symmetric 侧填 `dial`（只把 `udp://` 对端跟到它广播的当前 IP）。也可写死 `<对端公网IP>`；均可带 `:<端口>:<间隔秒>` |
| `ET_ANNOUNCE_IP` | ❌ | 默认 `1`。自测本节点 UDP 出口 IP 并写进 hostname 前缀广播给对端 —— 对端的 `auto` / `dial` 都靠它工作。设 `0` 关闭 |
| `ET_MAPPED` | ❌ | 默认 `auto`（用自测到的出口地址生成 `--mapped-listeners`，仅在设了 `PUNCH` 时才加）。也可写死 `<IP:端口>`，或设 `0` 关闭 |

> ⚠️ **网络名与密钥不能含冒号 `:`**（靠冒号分四段）。

监听端口按 `<端口>` / `+1` / `+2` 分三种协议：`ET=11010:...` → udp+tcp `11010`、ws `11011`、wss `11012`。

### 2.9 维护 `FORCE_UPDATE`

| 变量 | 默认 | 说明 |
| :--- | :--- | :--- |
| `FORCE_UPDATE` | （关） | `true` 强制下次启动重建服务配置（平时变量未变不重建，靠指纹比对） |

---

## 三、持久化怎么挂

容器的可写状态都落在 **`TARGET_HOME`**，**它由 `SSH_USER` 决定**：

| `SSH_USER` | `TARGET_HOME` | 卷要挂到 |
| :--- | :--- | :--- |
| `zv`（默认） | `/home/zv` | `/home/zv` |
| 自定义 `foo` | `/home/foo` | `/home/foo` |
| `root` | `/root` | `/root` |

> ⚠️ **挂载路径必须与 `SSH_USER` 一致**，否则数据不落持久卷。

`TARGET_HOME` 下会生成 / 持久化：

| 路径 | 内容 |
| :--- | :--- |
| `init_env.sh` | 流量统计初始化脚本（开 `GB` 时生成） |
| `boot/` | 自动生成的 supervisor 服务配置 |
| `supervisor/` | 你自己的服务配置投放目录（`*.conf`） |
| `p2p/` | HYP2P 的 `realm_name`、`cert_sha256`、`client.example.yaml` |
| `vnstat_data/` | vnstat 流量数据库（软链） |

无持久卷的平台（如 Koyeb）重启后这些重新生成 —— 对 HYP2P 的后果见[原理与坑点 §四](pitfalls.md)。

---

## 四、开 P2P 出站代理（HYP2P）

容器在 NAT 后**无需公网入站端口**，靠 UDP 打洞变成一个 Hysteria2 出站代理落地：本地 hy2 客户端经 P2P 直连进来，流量从容器 IP 出站，全程带 Salamander 混淆。

### 4.1 零配置（公共牵线）

只设 `HYP2P=认证密码:混淆密码:nginx`，不填 `HYP2P_RV`。容器自动用公共 `realm.hy2.io` 并生成随机 realm 名（持久化，重启不变）。部署后在终端里取连接信息（`/home/zv` 换成你的 `SSH_USER` 家目录）：

```bash
cat /home/zv/p2p/client.example.yaml   # 一份填好的本地 client 配置, 直接用
cat /home/zv/p2p/realm_name            # 仅 realm 名
cat /home/zv/p2p/cert_sha256           # 证书指纹 (pinSHA256)
```

启动日志也会打印含 realm 名 / Server URI / pinSHA256 的横幅。

### 4.2 本地客户端怎么连

`client.example.yaml` 已自动填好 `tls.insecure: true` + `tls.pinSHA256`（锁死指纹防 MITM），并监听本地 SOCKS5 `127.0.0.1:1080`、HTTP `127.0.0.1:8080`。拿到本地当 `client.yaml`，用官方 hysteria 客户端启动即可。

### 4.3 自建牵线服务器

在一台**公网机器**上跑 [hysteria-realm-server](https://github.com/apernet/hysteria-realm-server)，把 `HYP2P_RV` 填成它的 URI：

```bash
git clone https://github.com/apernet/hysteria-realm-server.git && cd hysteria-realm-server
docker build -t hy-realm .
docker run -d --name hy-realm --restart unless-stopped -p 8443:8443 \
  -e HYSTERIA_REALM_TOKEN="你的token" -e HYSTERIA_REALM_LISTEN=":8443" hy-realm
# 放行防火墙 TCP 8443
```

这样跑**没配 TLS**，`HYP2P_RV` 必须写 `realm+http://你的token@IP:8443/名字`。
用错 scheme 会握手失败 —— 判据见[原理与坑点 §五](pitfalls.md)。

### 4.4 Windows 一键批处理

**前提**：把 [hysteria-windows-amd64.exe](https://github.com/apernet/hysteria/releases/latest/download/hysteria-windows-amd64.exe) 放到桌面 `hysteria\` 目录下。

先按 §4.1 在容器里 `cat` 出 realm 名、认证密码、证书指纹，然后创建 `桌面\hy2-隧道.bat`，替换开头三行：

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

**用法**：双击 → 自动打洞建 P2P 直连，浏览器/应用设 SOCKS5 `127.0.0.1:25002`。再次双击同一脚本 = 停止隧道。

> ⚠️ 无持久卷平台（Koyeb 等）重启后 realm 名与证书指纹会重新生成，需重新 `cat` 并更新 bat 里那三行。

---

## 五、开异地组网（ET）

用 [EasyTier](https://github.com/EasyTier/EasyTier) 把各地的容器 / VPS / 本地机器拉进同一个虚拟局域网，彼此用虚拟 IP（如 `10.126.126.x`）直接访问。

### 5.1 两节点组网（有一端能开入站端口 —— 首选）

**节点 A —— 有公网 IP 的 VPS**（当中继/牵线）：

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

两端 `mynet` / `mysecret` 必须一致。B 起来后 A 上可直接 `ssh zv@10.126.126.2` 或访问 `http://10.126.126.2:7681`。

虚拟 IP 想自动分配就省掉第四段（走 DHCP，从 `10.0.0.1` 起）；只写最后一段也行（`…:2` = `10.126.126.2`，换网段设 `ET_SUBNET`）。

**为什么 `ET_PEERS` 要把同一节点写三种协议** → [原理与坑点 §二](pitfalls.md)。

### 5.2 两端都没有入站端口：CF 隧道当入口（兜底）

**这条是中转不是 P2P，实测延迟约 550 ms，先读[原理与坑点 §六](pitfalls.md)再决定用不用。**

**容器侧**（同时设 `CF_TOKEN` 与 `ET`，启动横幅会把下面的值打印出来）：

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

两种隧道类型的取舍：

| 类型 | Service 填 | 对端要求 | 评价 |
| :--- | :--- | :--- | :---: |
| **HTTP** | `localhost:11011`（ws 口） | 直接 `wss://域名:443` | ✅ 对端零依赖 |
| **TCP** | `tcp://localhost:11010` | 先跑 `cloudflared access tcp --hostname 域名 --url 127.0.0.1:21010`，再连 `tcp://127.0.0.1:21010` | ⚠️ 每台对端都要装 cloudflared 并常驻 |

> ⚠️ 走 TCP 类型时 `--url` 的本地端口**不要用 11010**（会撞本机 easytier）—— 判据见[原理与坑点 §六](pitfalls.md)。
> ⚠️ **不要给这条主机名加 Cloudflare Access 应用**，理由同上。

### 5.3 旧镜像不想重建：运行时装

已在跑的旧镜像（没有 `easytier` 二进制）不必重新部署，用 `KOMARI` 在启动时装一次（镜像里 `curl` 和 `unzip` 都现成）：

```bash
KOMARI=bash -c 'curl -fsSL https://github.com/EasyTier/EasyTier/releases/download/v2.6.4/easytier-linux-x86_64-v2.6.4.zip -o /tmp/et.zip && unzip -qo /tmp/et.zip -d /tmp/et && find /tmp/et -name "easytier-*" -exec install -m755 {} /usr/local/bin/ \; && nohup easytier-core --network-name mynet --network-secret mysecret -i 10.126.126.1 -l ws://0.0.0.0:11011 --no-tun --use-smoltcp >/var/log/et.log 2>&1 &'
```

跑起来后 CF 面板照 §5.2 配 `localhost:11011`。这是应急手段：没有 supervisor 保活，进程挂了不会拉起。

### 5.4 UDP 打洞（PUNCH）

**什么时候开**：`easytier-cli peer` 里 `tunnel` 只有 `tcp` 不出 `udp`，且两端 `nat_type` 一个 `Symmetric` 一个 `PortRestricted`。

**怎么配** —— 两侧各加一个变量，角色不同：

| 本侧 `nat_type` | 加什么 | 它干的活 |
| :--- | :--- | :--- |
| `PortRestricted` / Cone | `PUNCH=auto` | 全端口扫射预授权（会短暂重启 EasyTier） |
| `Symmetric` | `PUNCH=dial` | 把 `udp://` 对端跟到对方当前出口 IP（不重启） |

写全是 `PUNCH=auto:<端口>:<间隔秒>`，间隔默认 60；`auto` 的端口默认取 `ET` 监听端口，`dial` 的端口填**对端**的 UDP 端口。两侧都别关 `ET_ANNOUNCE_IP`（默认开）。

```bash
easytier-cli peer                   # tunnel 出现 udp 就是通了
tail -f /var/log/punchd.out.log     # 守护日志
```

打不通、日志读不懂、想知道为什么不能写死对端 IP → [nat-punching.md](nat-punching.md)。

### 5.5 查看状态

```bash
easytier-cli peer     # 对端列表: 隧道协议(udp/tcp/ws/wss)、p2p 还是中继、延迟、丢包
easytier-cli route    # 路由表: 各节点虚拟 IP、下一跳、路径长度
tail -f /var/log/easytier.err.log
sctl status easytier  # supervisor 里的进程状态
```

`cost` 列是 `p2p` 说明打洞成功（直连）；显示中继节点名则走了中继。`tunnel` 列是实际使用的协议。

---

## 六、日常运维

| 操作 | 命令 | 说明 |
| :--- | :--- | :--- |
| 查流量 | `gb` | 需先开 `GB=true`，显示 eth0 RX/TX（MB+GB） |
| 机器体检 | `vps` | 见 §6.1 |
| 看进程 | `sctl status` | `sctl` = 内置 supervisorctl |
| 重启服务 | `sctl restart kpal` | 服务名见 `sctl status` |
| 重载配置 | `sctl update` | 改了 `boot/` 或 `supervisor/*.conf` 后执行 |
| 看组网 | `easytier-cli peer` | 需先开 `ET` |

启动后会在 `TARGET_HOME` 生成 `init_env.sh` 与 `boot/` 下的服务配置；改动后 `sctl update` 生效，或设 `FORCE_UPDATE=true` 重启重建。

### 6.1 机器体检 `vps`

镜像里已装好，不必先手跑一遍那条 `bash <(curl -sL …)`。

```bash
vps          # 拉最新版并跑
vps -l       # 不联网, 跑 /tmp 里上次缓存那份
vps -h       # 说明
```

**必须是真 tty**（它是菜单式脚本）：`cf ssh <app>` 进去再敲，别 `cf ssh <app> -T -c 'vps'`。
无 tty 时 `vps` 会直接拒绝并给提示。三个坑的细节见[原理与坑点 §九](pitfalls.md)。

`vps` 与 docker-ocr-mesh 里的**同一份，改动请两边同步**（同 `sweep.py` / `punchd.sh` 的约定）。

---

## 七、构建与发布

- **基础镜像**：`ubuntu:22.04`
- **进程管理**：Supervisor（基础配置 `supervisord.conf`，各服务配置由 `entrypoint.sh` 按环境变量动态生成并 `include`）
- **CI**：`.github/workflows/build-image.yml`，推送即构建并发布到 GHCR
  - `ghcr.io/<owner>/zvps:latest`
  - `ghcr.io/<owner>/zvps:<版本号>`

本地自构建：

```bash
git clone https://github.com/zv201413/zvps-super.git && cd zvps-super
docker build -t zvps:local .
```
