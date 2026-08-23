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

每个节点启动时自测自己的 UDP 出口 IP，写进 EasyTier 的 `--hostname` **前缀**：

```
ip-52-139-216-172-sap
   └─ 出口 IP，点换成连字符
```

对端 `punchd.sh` 从 peer 列表里读回来，扫射目标就永远是当前值。这就是 `PUNCH=auto`。

选 hostname 当载体是因为它**不需要新端口、不需要凭据、不需要额外进程** —— TCP 兜底链一通它就通，而 TCP 兜底链本来就是先建立的那条。

**两条格式细节都是被坑出来的**：

- **用连字符而不是点**：EasyTier 的 magic dns 会把 hostname 当域名标签（`<hostname>.et.net`），含点会被切碎。
- **IP 放最前面**：EasyTier 把 hostname **硬截断到 32 字符**（实测）。IP 原本放后缀，基名一长就把 IP 尾巴截掉 —— SAP 的基名是 `localhost.localdomain`（21 字符），实际广播出去的是 `localhost-localdomai-ip-20-195-9`，末段 `169` 没了，对端解析不出来，日志一直报「对端未公布出口 IP」。改成 IP 在前，截断只会吃掉基名，而基名纯粹是给人看的。

解析端同时认前缀式和旧的后缀式，升级过程中新旧节点混跑不会停摆。

## 出口 IP 怎么自测：STUN 而不是 curl

`etaddr.py` 用 STUN，不用 `curl ifconfig.me`，两个理由：

1. **curl 走 TCP，拿到的是 TCP 出口 IP。** 打洞要的是 UDP 出口 IP。多数平台两者相同，但那是巧合不是保证。
2. **curl 拿不到端口映射**，只能假设「映射端口 == 本地端口」。该假设在 Cone NAT 下成立，在 Symmetric 下必然错。

STUN 从**待用的那个端口**发出去问，拿回来的正是这条链路真实的映射。还能顺带判出映射类型：用同一个 socket 问两台不同的 STUN 服务器 —— **IP 与端口都相同 → Cone**（端口可以公布给任意对端），**端口不同 → Symmetric**（端口对第三方无意义，只有 IP 可信）。

这个判定用在 `--mapped-listeners` 上：Cone 侧公布 STUN 报的端口，Symmetric 侧退回本地端口。

> `etaddr.py` 故意**不设** `SO_REUSEADDR`：UDP 上它会允许与已在监听的 EasyTier 共绑同一端口，结果入站包被内核派给自测 socket，把 EasyTier 的流量吃掉。宁可 bind 失败退到临时端口（此时映射类型标 `unknown`，端口不可信，只用 IP）。

STUN 全挂时退化到 HTTP 取 IP（`api.ipify.org` → `ifconfig.me` → `icanhazip.com`），端口按本地端口填，类型标 `unknown`。

## 哪一侧要配

两侧都要配，但角色相反：

| 本侧 NAT | 配 | 做什么 | 停机 |
| :--- | :--- | :--- | :---: |
| Port-Restricted / Cone | `PUNCH=auto` | 全端口扫射预授权 | 每次接力断 3～5 秒 |
| Symmetric | `PUNCH=dial` | 把 `udp://` 对端跟到对方广播的当前 IP | 无 |

**为什么 Symmetric 侧也得有守护**（2026-08-23 实测）：对端换 IP 后，`ET_PEERS` 里那条 `udp://` 就是个死地址，easytier 每 3 秒朝它重试到天荒地老 ——

```
INFO connector::manual: reconnect: udp://208.77.246.136:5432
WARN tunnel::udp: udp send syn ret=16
INFO connector::manual: ... done, ret: Err(connect timeout after 1.99993109s)
```

—— 而对端的**新**地址没有任何人去拨。`--mapped-listeners` 不会救它：EasyTier 只对「仅能经中继到达」的 peer 触发打洞，TCP 一通就已算 `p2p`，于是它认为无事可做。所以 `dial` 用 `easytier-cli connector add` 把 `udp://` 改到当前广播值，并摘掉指向旧 IP 的死连接（只动 `udp://`，`tcp/ws/wss` 兜底链不碰）。

`dial` 的端口参数是**对端**的 UDP 端口，不是本地端口 —— 两端端口不同时（如 SAP `11010` ↔ Railway `5432`）必须显式写：`PUNCH=dial:5432`。

**两侧都要保持 `ET_ANNOUNCE_IP=1`（默认值）**，它是双方唯一能知道对方当前出口 IP 的通道。关掉后设了 `auto` 的那侧日志里会一直是：

```
[punchd] 对端未公布出口 IP (hostname 里没有 ip-a-b-c-d) → 无法自动扫射
```

看到这行就是对端还在跑旧镜像或关了广播。临时办法是改回 `PUNCH=<对端IP>` 写死，但对端一重启就又失效。

## 日志长什么样

扫射侧（`auto`）：

```
[punchd 03:13:07] 缺 UDP (tunnel=tcp ), 第 1 次授权接力 → 52.139.216.172
[punchd 52.139.216.172]   第1 轮: 64512 端口 / 1.35s
[punchd 52.139.216.172]   第2 轮: 64512 端口 / 0.89s
[punchd 52.139.216.172]   已释放 11010, 立即交给 EasyTier
[punchd 03:13:15] 接力完成, EasyTier 已重启
[punchd 03:13:35] UDP 已恢复 (tunnel=tcp,udp)
```

拨号侧（`dial`），不重启 EasyTier：

```
[punchd 05:41:02] 摘掉死连接 udp://208.77.246.136:5432 (已无对端广播该 IP)
[punchd 05:41:02] 开始拨 udp://208.77.246.135:5432 (对端广播的当前出口)
[punchd 05:42:02] UDP 已建立 (tunnel=tcp,udp)
```

已经在拨的目标不会重复 `add`，所以稳定后日志是安静的。

## 打通之后能跑多快

**2026-08-23 实测 A**（Railway 中继 ↔ SAP CF，两端都在新加坡，隧道延迟 **1.86 ms**、loss 0.0%）：

| 方向 | 结果 |
| :--- | :--- |
| 上行 SAP → 中继 | **627 KB/s**（20 MB / 33.4 s，服务端计时，md5 一致） |
| 下行 中继 → SAP | 2 KB/s —— 平台入站限速，不在重启后的高速窗口内 |

同一条隧道两个方向差 300 倍，所以**别拿下行数字判断打洞质量**。

**2026-08-23 实测 B**（跨区，延迟 167 ms）：

| 方向 | 不打洞（走平台 HTTP 入口） | 打洞后（UDP 直连） |
| :--- | :--- | :--- |
| 上行 SAP → 中继 | 9 KB/s | **190 KB/s** |
| 下行 中继 → SAP（重启后高速窗口内） | — | **6.4 MB/s** |

### 怎么确认流量真走了 UDP

`tunnel_proto=tcp,udp` 只说明两条隧道都在，不说明数据走哪条。用内核计数器归因，传输前后各读一次 `/proc/net/snmp`：

```
                传输前      传输后      增量
UDP In          34,797     70,487     +35,690     ← 20 MB 的数据包
UDP Out        532,381    533,482     +1,101      ← 纯 ACK（基数是扫射留下的）
TCP InSegs      23,362     44,836     +21,474     ← easytier → 本机接收进程的回环投递
```

20 MB 单向传输若走 TCP 隧道，`UDP In` 会基本不动。TCP 那一栏的增量是**回环**（easytier 用 smoltcp 收下后再投给本机服务），别误读成隧道流量。

### 上行必须在服务端计时

客户端 `curl` 自报的上传速率不能当证据：同一次上传 curl 自报 34,952 B/s，服务端只收到 9,099 B/s，差额是本地 socket 缓冲加平台网关缓冲。下行可以在接收端量 —— 接收端量的正是自己真收到的字节。

