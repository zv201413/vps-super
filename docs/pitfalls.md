# ZVPS-Super 原理与坑点

**本篇不给可粘贴的命令。** 要步骤 → [操作篇](operations.md)；UDP 打洞的机制单独一篇 → [nat-punching.md](nat-punching.md)；总入口 → [README](../README.md)。

按「现象 → 判据 → 处置」记，都是实际踩过或实测过的。

---

## 一、镜像为什么只 `EXPOSE 7681`

**故意只留一个。** CF 会把 `EXPOSE` 列表里**最小**的端口当作应用端口接到 `$PORT` 上 —— 多写一个 `22`，22 更小，HTTP 路由就被劫到 sshd 上去了。

其余服务要么走出站隧道 / 打洞（不需要入站端口），要么按你设的端口自行映射。sshd 在容器内和组网里照常用 22，不需要 `EXPOSE`。

---

## 二、`ET_PEERS` 为什么要把同一个节点写多种协议

EasyTier 默认开 **UDP 打洞**，打通即 P2P 直连（最低延迟），打不通则经对端节点中继。要让它在 UDP 被封时能自动落到 TCP / WS，就得把**同一个节点的多种协议**都写进 `ET_PEERS`，形成兜底链：

| 协议 | 用途 | 特点 |
| :--- | :--- | :--- |
| `udp://` | **首选**，UDP 打洞 P2P 直连 | 延迟最低；对称 NAT 或封 UDP 时失效 |
| `tcp://` | UDP 不通时兜底 | 稳定，走中继时略高延迟 |
| `ws://` | TCP 也被限制时兜底 | 伪装成 HTTP 流量，穿透性最好 |
| `wss://` | 同上 + TLS | 证书由 EasyTier 自动生成，无需配置 |

本镜像的**监听侧四协议全开**，所以对端可用任意协议接入本节点。

**分隔符的坑**：`ET_PEERS` 官方原生只认逗号，**空格分隔会静默解析成 0 条**（不报错，看着像配了其实一条没配）。本镜像放宽为逗号和空格都接受，自己转过一遍。

---

## 三、TUN 自动降级：判据，以及「无 TUN 是单向的」

组网本需 TUN 设备，但免费 PaaS 通常给不了。启动时探测**两个**条件：`/dev/net/tun` 存在（不存在则尝试 `mknod` 创建）**且**进程持有 `NET_ADMIN` 能力（读 `/proc/self/status` 的 `CapEff` 第 12 位）。

**只看设备节点是不够的**：多数 PaaS 恰好是「节点在、能力无」，这时建 TUN 仍然会失败。

| 模式 | 触发条件 | 能力 |
| :--- | :--- | :--- |
| **TUN 模式** | 有 `/dev/net/tun` + `NET_ADMIN` | 完整三层互通，双向任意协议 |
| **无 TUN 模式** | 缺任一条件（自动降级） | 自动加 `--no-tun --use-smoltcp`；**其他节点仍可访问本容器内的服务** |

> ⚠️ **无 TUN 模式是单向的**：远端节点能访问容器内服务（实测可用），但**容器自己主动访问组网内其他节点不可用** —— 那需要 TUN 或 SOCKS5 出口（SOCKS5 暂未接入）。
>
> 自建 Docker 想要完整互通，启动时加 `--cap-add NET_ADMIN --device /dev/net/tun`。

---

## 四、HYP2P 的两个硬前提

- **持久化**：realm 名与证书指纹存在 `$TARGET_HOME/p2p`。**Koyeb 等无持久盘平台**重启会重新生成 → 本地 client 得重抄。想稳定就挂持久卷，或者显式设 `HYP2P_RV`（固定 realm 名）+ 本地只用 `insecure: true`（不 pin 指纹）。
- **NAT 类型**：UDP 打洞有硬限制 —— 只要**一端对称 NAT（随机端口）**且另一端非公网 IP / 全锥型，就**可能打不通**。公共 `realm.hy2.io` 是免费 best-effort，可能宕机或被墙。若本地有 **IPv6**，强制客户端走 v6（只填 v6 STUN）可绕过 v4 CGNAT，成功率与稳定性显著提升。

---

## 五、`realm://` 还是 `realm+http://`

容器作为 hy2 server 用**自签证书**，指纹是容器内现生成的、事先不知道 —— 所以 `client.example.yaml` 走 `tls.insecure: true` 再用 `pinSHA256` 锁死指纹（防 MITM），而不是校验 CA。

牵线服务器的 scheme 按**它有没有 TLS** 选，选错直接握手失败：

| 牵线服务器 | `HYP2P_RV` 写法 |
| :--- | :--- |
| 自建、裸跑没配 TLS | **`realm+http://token@IP:8443/名字`** |
| 自建、配了 TLS（域名+证书 / Caddy 反代自动签） | `realm://…` |
| 公共 `realm.hy2.io`（HTTPS） | `realm://…`（留空即自动用） |

裸跑的自建服务器用 `realm://` 会握手失败 —— 这是最容易踩的一个。

---

## 六、CF 隧道当入口：这是中转，不是 P2P

**什么时候才用它**：两端都开不了入站端口（SAP BTP 只放行 80/443，Koyeb / Render 同理），没有任何一端能当中继节点。**只要有一端能开入站端口，就优先直连**，把这条留作兜底。

**为什么 ws / wss 两端协议不对称是正常的**：容器内监听明文 `ws`，TLS 由 CF 边缘提供，对端用 `wss` 连。EasyTier 的 `wss` 就是为这个设计的，官方 `--help` 里 `wss` 的说明正是「配置服务器 ws 被代理为 wss 时」。它的 `wss` 客户端不校验证书，CF 的有效证书自然无碍。

**实测记录**：

- **TCP 类型 + `cloudflared access tcp`** —— 真实环境跑通（SAP BTP 新加坡容器 ↔ 家庭宽带）。SAP 侧只设 `CF_TOKEN` + `ET`，容器无 TUN 自动降级 `--no-tun --use-smoltcp`；本机经 socks5 访问到容器内 ttyd，返回真实响应头 `server: ttyd/1.7.3`。`peer` 表 `tunnel=tcp`、`loss=0.0%`、路由 `DIRECT`，**延迟约 550 ms**（绕 Cloudflare 边缘 + 本地 cloudflared 中转两跳）。
- **HTTP 类型 + `wss`** —— 用 TLS 终止 + HTTP 头重建的反代精确模拟 CF 链路验证：握手穿过 HTTP 层重建后返回 `101 Switching Protocols`，B 端 `tunnel=wss` / A 端 `tunnel=ws`，路由 `DIRECT`，真实载荷到达容器内服务。

**代价**：cloudflared 只传 TCP/HTTP，**UDP 打洞在这条路上完全用不上**，全部流量绕行 Cloudflare 边缘，延迟远高于直连（实测 550 ms）、带宽受 CF 限制。CF 免费版对代理非网页流量另有 ToS 约束（第 2.8 条），当常规链路跑大流量有风险。

**两个不要**：

- ⚠️ **不要给这条主机名加 Cloudflare Access 应用**。Access 会要求浏览器 OAuth 登录，`Allow + Everyone` 也一样要走登录流程（只有 `Bypass` 才不拦），而 EasyTier 不是浏览器，握手会被跳转到登录页而失败。组网的准入靠**网络名 + 密钥**，本身就是凭证。
- ⚠️ **走 TCP 类型时，`cloudflared access tcp --url` 的本地端口不要用 11010**。本机 easytier 自己默认也监听 `0.0.0.0:11010`，会撞成 `Address in use` 而整个实例启动失败。换个端口（如 21010），或给本机 easytier 显式指定 `-l tcp://0.0.0.0:21011`。

---

## 七、`ET_*` 是 EasyTier 的原生环境变量命名空间

`easytier-core` 自己会读 `ET_SOCKS5`、`ET_PEERS` 等同名变量。本镜像的参数都以**命令行显式传入**（优先级高于 env），但**残留的 `ET_*` 变量仍可能生效** —— 例如遗留一个 `ET_SOCKS5=12333`，容器就会额外开一个 socks5 出口。

**处置**：换方案时把用不到的 `ET_*` 变量删干净。

---

## 八、组网的四条注意事项

- **必须自备对端节点**：官方公共节点 `public.easytier.cn` **已无 DNS A 记录**（实测解析失败），镜像因此不内置任何默认公共节点。用自己的公网 VPS 当节点最可靠；两端都没有公网端口时走 §六 的 CF 隧道，或自行找可用的社区公共节点填进 `ET_PEERS`。
- **网络名 / 密钥不能含冒号**：`ET` 靠冒号分四段，含冒号会被切错。只用字母数字和 `-`。同理 `HYP2P` 的两个密码靠冒号分三段。
- **NAT 类型决定能否 P2P**：一端对称 NAT（随机端口）且另一端非公网 / 全锥型时，UDP 打洞**可能失败**，此时自动走中继（功能正常，延迟和带宽受中继节点限制）。这种组合可以用 `PUNCH` 强行打通，见 [nat-punching.md](nat-punching.md)。
- **密钥即入网凭证**：任何拿到网络名 + 密钥的人都能进你的组网，当密码对待。

---

## 九、`vps` 探针的三个坑

三个坑，`vps` 这个包装脚本已经各挡了一道，但**手敲那条原始命令时都会踩**。

**1. `bash <(curl -sL URL)` 下载失败时静默地什么都不做。** 进程替换喂给 bash 的是一个**空文件**，bash 读完正常退出、`$?` 是 **0**，伪装成「跑完了没输出」。免费 PaaS 出口常限速或挡 GitHub，这个失败模式几乎必然撞上。
判据：`curl -I <URL>` 单独试一次。正确写法是先落盘、验退出码且文件非空再交给 bash —— `vps` 就是这么做的，下载失败还会退回 `/tmp/vps_info.sh` 缓存。

**2. 菜单式脚本在无 tty 下会死循环。** 探针主菜单是 `while` 套 `read -p`，stdin 一 EOF 就落进「无效选择 + `sleep 2`」分支**无限转**，每 2 秒一屏、没人看见还在烧 CPU。
`cf ssh <app> -T -c 'vps'` 正是无 tty 的情形；要跑就 `cf ssh <app>` 开真 tty。`vps` 在无 tty 时直接拒绝启动（`VPS_FORCE_NOTTY=1` 可强来）。已经转起来了：`pkill -f 'vps_info[.]sh'` —— **方括号是必须的**，写成 `vps_info.sh` 会匹配到 `cf ssh` 自己那条命令行。

**3. 探针跑完会覆盖 `/usr/local/bin/vps`。** 它自带一段「快捷键配置」，以 root 跑完就 `rm -f /usr/local/bin/vps` 再写它自己那份简版 wrapper（没有上面两道防线）。**不去对抗它**：容器 restart 后镜像里那份自动回来。
`/usr/bin/vps` 故意做成**软链**指向 `/usr/local/bin/vps`（`cf ssh -T -c` 的 PATH 只有 `/bin:/usr/bin`，不含 `/usr/local/bin`）。做软链而不是拷第二份，是为了避免被覆盖后「交互 shell 跑到一个版本、`cf ssh` 跑到另一个版本」。

---

## 十、UDP 打洞

Symmetric ↔ PortRestricted 的死锁怎么破、为什么必须外挂守护、为什么**不能把对端 IP 写死** —— 单独一篇：**[nat-punching.md](nat-punching.md)**。
