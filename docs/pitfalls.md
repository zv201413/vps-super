# ZVPS-Super 原理与坑点

**本篇不给可粘贴的命令。** 要步骤 → [操作篇](operations.md)；总入口 → [README](../README.md)。

按「现象 → 判据 → 处置」记，都是实际踩过或实测过的。

---

## 一、镜像为什么只 `EXPOSE 7681`

**故意只留一个。** CF 会把 `EXPOSE` 列表里**最小**的端口当作应用端口接到 `$PORT` 上 —— 多写一个 `22`，22 更小，HTTP 路由就被劫到 sshd 上去了。

其余服务要么走出站隧道 / 打洞（不需要入站端口），要么按你设的端口自行映射。sshd 在容器内照常用 22，不需要 `EXPOSE`。

---

## 二、HYP2P 的两个硬前提

- **持久化**：realm 名与证书指纹存在 `$TARGET_HOME/p2p`。**Koyeb 等无持久盘平台**重启会重新生成 → 本地 client 得重抄。想稳定就挂持久卷，或者显式设 `HYP2P_RV`（固定 realm 名）+ 本地只用 `insecure: true`（不 pin 指纹）。
- **NAT 类型**：UDP 打洞有硬限制 —— 只要**一端对称 NAT（随机端口）**且另一端非公网 IP / 全锥型，就**可能打不通**。公共 `realm.hy2.io` 是免费 best-effort，可能宕机或被墙。若本地有 **IPv6**，强制客户端走 v6（只填 v6 STUN）可绕过 v4 CGNAT，成功率与稳定性显著提升。

---

## 三、`realm://` 还是 `realm+http://`

容器作为 hy2 server 用**自签证书**，指纹是容器内现生成的、事先不知道 —— 所以 `client.example.yaml` 走 `tls.insecure: true` 再用 `pinSHA256` 锁死指纹（防 MITM），而不是校验 CA。

牵线服务器的 scheme 按**它有没有 TLS** 选，选错直接握手失败：

| 牵线服务器 | `HYP2P_RV` 写法 |
| :--- | :--- |
| 自建、裸跑没配 TLS | **`realm+http://token@IP:8443/名字`** |
| 自建、配了 TLS（域名+证书 / Caddy 反代自动签） | `realm://…` |
| 公共 `realm.hy2.io`（HTTPS） | `realm://…`（留空即自动用） |

裸跑的自建服务器用 `realm://` 会握手失败 —— 这是最容易踩的一个。

---

## 四、`vps` 探针的三个坑

三个坑，`vps` 这个包装脚本已经各挡了一道，但**手敲那条原始命令时都会踩**。

**1. `bash <(curl -sL URL)` 下载失败时静默地什么都不做。** 进程替换喂给 bash 的是一个**空文件**，bash 读完正常退出、`$?` 是 **0**，伪装成「跑完了没输出」。免费 PaaS 出口常限速或挡 GitHub，这个失败模式几乎必然撞上。
判据：`curl -I <URL>` 单独试一次。正确写法是先落盘、验退出码且文件非空再交给 bash —— `vps` 就是这么做的，下载失败还会退回 `/tmp/vps_info.sh` 缓存。

**2. 菜单式脚本在无 tty 下会死循环。** 探针主菜单是 `while` 套 `read -p`，stdin 一 EOF 就落进「无效选择 + `sleep 2`」分支**无限转**，每 2 秒一屏、没人看见还在烧 CPU。
`cf ssh <app> -T -c 'vps'` 正是无 tty 的情形；要跑就 `cf ssh <app>` 开真 tty。`vps` 在无 tty 时直接拒绝启动（`VPS_FORCE_NOTTY=1` 可强来）。已经转起来了：`pkill -f 'vps_info[.]sh'` —— **方括号是必须的**，写成 `vps_info.sh` 会匹配到 `cf ssh` 自己那条命令行。

**3. 探针跑完会覆盖 `/usr/local/bin/vps`。** 它自带一段「快捷键配置」，以 root 跑完就 `rm -f /usr/local/bin/vps` 再写它自己那份简版 wrapper（没有上面两道防线）。**不去对抗它**：容器 restart 后镜像里那份自动回来。
`/usr/bin/vps` 故意做成**软链**指向 `/usr/local/bin/vps`（`cf ssh -T -c` 的 PATH 只有 `/bin:/usr/bin`，不含 `/usr/local/bin`）。做软链而不是拷第二份，是为了避免被覆盖后「交互 shell 跑到一个版本、`cf ssh` 跑到另一个版本」。
