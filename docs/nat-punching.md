# UDP 打洞（PUNCH）原理与坑点

回到 [README](../README.md#-udp-打洞punch)。操作步骤在那里，这里只讲**为什么**。

## 什么时候需要它

EasyTier 自己会打洞。只有一种情况它打不通，才需要 `PUNCH`：

**两端 NAT 是 Symmetric ↔ Port-Restricted Cone**（免费 PaaS 容器互连时很常见）。

用 `easytier-cli peer` 看 `nat_type` 列就知道自己是哪种。

## 死锁在哪

- **Symmetric 侧**的映射端口随目标变化。它从 STUN 学到的公网端口对 STUN 服务器有效，对本链路无效 —— 于是它在控制通道里告诉对端的端点是错的。
- **Port-Restricted 侧**的入站要求先有出站到**精确的** `<对端IP:对端端口>`。而那个端口正是上面拿不到的值。

两边互相等对方先给出一个谁都拿不到的数字。

## 破法：全端口预授权

Port-Restricted 侧朝对端 `1024–65535` **每个端口各发一包**，把所有可能的映射端口一次性授权掉。之后 Symmetric 侧无论用哪个端口发过来，都落在已授权的条目上。

代价极低：实测 64512 个端口容器上 **0.9 秒**扫完。这是 `sweep.py` 干的事。

## 为什么能「接力」

关键机制：**NAT 放行条目记的是 `<内部IP:内部端口 → 外部IP:外部端口>` 四元组，与哪个进程占用该端口无关。**

```
sweep.py 绑 PORT → 扫射 → 立即退出 → EasyTier 绑同一个 PORT
                                        ↑
                        它收发用的四元组正好落在已有条目上
```

EasyTier 一收到对端的包就学到对端真实映射端点，之后双向流量自己保活，不必再扫。`sweep.py` 扫完**立刻退出、不留 sleep** 就是为了这个：空窗越短，衔接越稳。

## 为什么必须外挂守护，不能让 EasyTier 自己来

1. **它只对「仅能经中继到达」的 peer 触发打洞。** 而 TCP 直连一旦建立就已经算 `p2p` —— 于是它认为事情已经办好，根本不去打洞。
2. **`easytier-core --help` 里没有强制打洞的开关。** `--enable-kcp-proxy` / `--enable-quic-proxy` 反而**依赖**已经存在的 UDP 隧道，不能用来创造它。

所以只能外挂 `punchd.sh`。

## 为什么必须停 EasyTier 几秒

扫射的出站包源端口必须是 EasyTier 那个端口（NAT 条目才对得上），而它正被 EasyTier 占着。

试过用 raw socket 造包绕开占用（零停机），**不通**：容器没有 `CAP_NET_RAW`（实测 Railway `CapEff=00000000800405fb`，第 13 位为 0），`SOCK_RAW` 直接 `PermissionError`。

所以接力方案是必需的，代价是每次接力 EasyTier 断几秒。故只在缺 UDP 时才动，并带退避。

## 守护的工作循环

```
周期检查 tunnel_proto
  ├─ 一个对端都没有 → 连 TCP 都没通, 对端多半不在线。扫射白费(也学不到 IP), 等
  ├─ 含 udp        → 好, 什么都不做
  └─ 缺 udp        → 授权接力:
                        停 EasyTier → sleep 1 (等端口真正释放)
                      → sweep.py 扫射对端 2 轮
                      → 起 EasyTier → sleep 25 (给握手时间) → 复查
```

`sleep 1` 不是凑数：不等端口释放，`sweep.py` 会 `bind` 失败。

**退避**：连续 3 次没成，等 `INTERVAL × 5`。「一直不成」通常意味着对端侧也没配好，此时反复重启 EasyTier 会把已经好用的 TCP 通道也拖垮。退避期间 TCP 照常可用。

**判据怎么取**：走 `easytier-cli -o json` 按字段名 `tunnel_proto` 取，不刮表格。三点实测依据：

- `-o json` 是**全局**选项，必须放在子命令**前面**，写成 `peer -o json` 会报错
- 自身那行的 `cost` 是 `Local`、`tunnel_proto` 是 `-`，必须跳过
- 表格列与 JSON 字段并不一一对应（JSON 多一个 `id`），按列号取值既脆又易错

守护是长期无人值守跑的，判据一错就会永远认为「缺 UDP」而无限接力。

## 对端 IP 会变 —— 打洞「时好时坏」的真凶

**2026-08-23 实测**：SAP CF 容器重启后出口 IP 从 `20.195.24.178` 变成 `52.139.216.172`（容器内网 IP 也从 `10.148.116.250` 变成 `10.153.217.129`，即换了 Diego cell）。

这一条解释了长期观察到的「打洞时好时坏」：手工扫射当场就通（那一刻 IP 是对的），之后每次重启都不通（写死的 IP 已经指向别人，UDP 永远回不来）。

### 为什么不能从 EasyTier 里查对端 IP

查过了，没有：

- `easytier-cli -o json peer` 的字段只有 `cidr / ipv4 / hostname / cost / lat_ms / loss_rate / rx_bytes / tx_bytes / tunnel_proto / nat_type / id / version` —— **没有对端公网端点**
- `easytier-cli route` 也没有

对端公网地址只存在于 EasyTier 内部控制通道里，不外露。

### 破法：把出口 IP 塞进 hostname 广播

每个节点启动时自测自己的 UDP 出口 IP，写进 EasyTier 的 `--hostname` 后缀：

```
sap-ip-52-139-216-172
        └─ 出口 IP，点换成连字符
```

对端 `punchd.sh` 从 peer 列表里读回来，扫射目标就永远是当前值。这就是 `PUNCH=auto`。

选 hostname 当载体是因为它**不需要新端口、不需要凭据、不需要额外进程** —— TCP 兜底链一通它就通，而 TCP 兜底链本来就是先建立的那条。

用连字符而不是点：EasyTier 的 magic dns 会把 hostname 当域名标签（`<hostname>.et.net`），含点会被切碎。

## 出口 IP 怎么自测：STUN 而不是 curl

`etaddr.py` 用 STUN，不用 `curl ifconfig.me`，两个理由：

1. **curl 走 TCP，拿到的是 TCP 出口 IP。** 打洞要的是 UDP 出口 IP。多数平台两者相同，但那是巧合不是保证。
2. **curl 拿不到端口映射**，只能假设「映射端口 == 本地端口」。该假设在 Cone NAT 下成立，在 Symmetric 下必然错。

STUN 从**待用的那个端口**发出去问，拿回来的正是这条链路真实的映射。还能顺带判出映射类型：用同一个 socket 问两台不同的 STUN 服务器 —— **IP 与端口都相同 → Cone**（端口可以公布给任意对端），**端口不同 → Symmetric**（端口对第三方无意义，只有 IP 可信）。

这个判定用在 `--mapped-listeners` 上：Cone 侧公布 STUN 报的端口，Symmetric 侧退回本地端口。

> `etaddr.py` 故意**不设** `SO_REUSEADDR`：UDP 上它会允许与已在监听的 EasyTier 共绑同一端口，结果入站包被内核派给自测 socket，把 EasyTier 的流量吃掉。宁可 bind 失败退到临时端口（此时映射类型标 `unknown`，端口不可信，只用 IP）。

STUN 全挂时退化到 HTTP 取 IP（`api.ipify.org` → `ifconfig.me` → `icanhazip.com`），端口按本地端口填，类型标 `unknown`。

## 哪一侧要配

**只有 Port-Restricted / Cone 那一侧**配 `PUNCH` —— 预授权必须由它发起。推荐 `PUNCH=auto`。

Symmetric 侧不用配 `PUNCH`：它的出站不受限，靠 `ET_PEERS` 里的 `udp://` 持续尝试即可。

但**两侧都要保持 `ET_ANNOUNCE_IP=1`（默认值）**，否则设了 `PUNCH=auto` 的那侧学不到该扫谁，日志里会一直是：

```
[punchd] 对端未公布出口 IP (hostname 无 -ip- 后缀) → 无法自动扫射
```

看到这行就是对端还在跑旧镜像。临时办法是改回 `PUNCH=<对端IP>` 写死，但对端一重启就又失效。

## 打通之后能跑多快

**2026-08-23 实测**（Railway 中继 ↔ SAP CF，延迟 167ms）：

| 方向 | 不打洞（走平台 HTTP 入口） | 打洞后（UDP 直连） |
| :--- | :--- | :--- |
| 上行 SAP → 中继 | 9 KB/s | **190 KB/s** |
| 下行 中继 → SAP（重启后高速窗口内） | — | **6.4 MB/s** |

上行提升约 21 倍。两个测量注意点：

- **上行必须在服务端计时。** 客户端 `curl` 自报的上传速率不能当证据：同一次上传 curl 自报 34,952 B/s，服务端只收到 9,099 B/s，差额是本地 socket 缓冲加平台网关缓冲。
- **下行可以在接收端量**：接收端量的正是自己真收到的字节。

窗口外一上量就被平台限速掐住（实测下行 240 秒零字节），而此时隧道本身 `loss` 只有 2.0%、延迟稳定 —— 那是平台限速，不是打洞质量问题，别拿它当打洞失败的证据。
