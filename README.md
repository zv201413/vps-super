# ZVPS-Super

> 基于 **Ubuntu 22.04** 的「环境变量驱动」多服务容器镜像。
> 设好变量 → 服务自动拉起、配置自动生成、数据自动持久化，由 **Supervisor** 统一保活。

专为 **免费容器平台**（Koyeb / Railway / Render / Zeabur / HuggingFace Spaces 等，无 Docker 访问权、常无公网入站端口）以及**自建 Docker / VPS** 设计。一个镜像同时提供：SSH、Web 终端、Cloudflare 隧道、循环保活、流量统计、一次性安装注入、**P2P 打洞的 Hysteria2 出站代理**，以及 **EasyTier 异地组网**。

```
ghcr.io/zv201413/zvps:latest
```

> CI 每次推送自动构建并发布到 GHCR（见 [操作篇 §七](docs/operations.md)）。

---

## 文档分三份，别在这里找步骤

| 文件 | 答什么 | 里面有 |
| :--- | :--- | :--- |
| **本页** | 是什么、该读哪一份 | 服务一览、最小启动、分诊表、文件清单 |
| **[操作篇](docs/operations.md)** | **怎么做** | 部署命令、环境变量全表、持久化怎么挂、HYP2P / 组网怎么开、运维命令、构建发布 |
| **[原理与坑点](docs/pitfalls.md)** | **为什么这样、坏了怎么认** | 设计取舍、判据、实测数字、不要这么干 |
| **[nat-punching.md](docs/nat-punching.md)** | UDP 打洞的机制 | Symmetric ↔ PortRestricted 怎么破 |

---

## 服务一览

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
| **punchd** | UDP 打洞守护：缺 UDP 就做授权接力（Symmetric ↔ PortRestricted 专用） | `PUNCH` | ⬜ OFF | — |

镜像只 `EXPOSE 7681`，是[故意的](docs/pitfalls.md)（§一）。

---

## 60 秒上手

```bash
docker run -d --name zvps \
  -e SSH_PWD="改成你的密码" \
  -p 2222:22 -p 7681:7681 \
  ghcr.io/zv201413/zvps:latest
```

- SSH：`ssh zv@<host> -p 2222`（默认用户 `zv`）
- Web 终端：`http://<host>:7681`

全功能启动、平台面板部署、每个变量的含义 → **[操作篇 §一、§二](docs/operations.md)**。

---

## 我要做的事 → 读哪一节

| 我想… | 去哪 |
| :--- | :--- |
| 挂持久卷，别一重启就没了 | [操作篇 §三](docs/operations.md) |
| 让容器变成我的出站代理（本地翻出去） | [操作篇 §四](docs/operations.md) |
| Windows 上双击就连 | [操作篇 §4.4](docs/operations.md) |
| 把几台机器拉进同一个虚拟局域网 | [操作篇 §5.1](docs/operations.md) |
| 两端都开不了端口，还想组网 | [操作篇 §5.2](docs/operations.md)（先看[原理 §六](docs/pitfalls.md)） |
| 让 UDP 打洞打通 | [操作篇 §5.4](docs/operations.md) → [nat-punching.md](docs/nat-punching.md) |
| 看流量 / 看进程 / 重启某个服务 | [操作篇 §六](docs/operations.md) |
| 给机器做体检（`vps`） | [操作篇 §6.1](docs/operations.md) |
| 自己构建镜像 | [操作篇 §七](docs/operations.md) |

## 坏了 → 去哪查

| 症状（你会怎么说） | 大概是 | 去哪 |
| :--- | :--- | :--- |
| 「数据一重启就没了」 | 卷挂错路径（`SSH_USER` 决定家目录） | [操作篇 §三](docs/operations.md) |
| 「组网起来了但容器自己 ping 不通别人」 | 无 TUN 模式是单向的 | [原理 §三](docs/pitfalls.md) |
| 「`ET_PEERS` 明明填了，一个对端都没有」 | 用了空格分隔，静默解析成 0 条 | [原理 §二](docs/pitfalls.md) |
| 「牵线服务器连不上，握手就失败」 | `realm://` / `realm+http://` 选错 | [原理 §五](docs/pitfalls.md) |
| 「组网通了但慢得离谱（半秒延迟）」 | 走的是 CF 中转不是 P2P | [原理 §六](docs/pitfalls.md) |
| 「easytier 起不来，`Address in use`」 | `cloudflared access --url` 撞了 11010 | [原理 §六](docs/pitfalls.md) |
| 「加了 Cloudflare Access 之后就连不上了」 | Access 要 OAuth，EasyTier 不是浏览器 | [原理 §六](docs/pitfalls.md) |
| 「莫名多出一个 socks5 端口」 | 残留的 `ET_*` 变量被 easytier 原生读走 | [原理 §七](docs/pitfalls.md) |
| 「本地 client 昨天还能连，今天不行了」 | 无持久卷平台重启换了 realm 名和指纹 | [原理 §四](docs/pitfalls.md) |
| 「`tunnel` 一直只有 tcp 出不来 udp」 | 两端 NAT 类型组合需要 `PUNCH` | [nat-punching.md](docs/nat-punching.md) |
| 「`vps` 敲了没反应 / 一直刷无效选择」 | 下载静默失败，或没有真 tty | [原理 §九](docs/pitfalls.md) |

---

## 文件

| 文件 | 作用 |
| :--- | :--- |
| `Dockerfile` | 镜像构建：装 ttyd / cloudflared / hysteria / sing-box / easytier / opencode，投放脚本 |
| `entrypoint.sh` | 按环境变量生成 supervisor 配置并启动；配置指纹机制避免每次重启都重写 |
| `supervisord.conf` | supervisor 基础配置模板（含 `{SSH_USER}` 占位符） |
| `fragments/*.conf` | 各服务的 supervisor 片段，由 entrypoint 按需投放 |
| `etaddr.py` | STUN 自测本节点 UDP 出口 IP 与映射端口（供 hostname 广播和 `--mapped-listeners`） |
| `sweep.py` | 全端口 UDP 预授权扫射。与 docker-ocr-mesh 里的**同一份，改动两边同步** |
| `punchd.sh` | 打洞守护，两个角色：`auto` 缺 UDP 就做授权接力，`dial` 把 `udp://` 对端跟到它广播的出口 IP。**同上，两边同步** |
| `vps` | `vps` 命令：拉 [`zv201413/info`](https://github.com/zv201413/info) 的探针跑机器体检。**同上，两边同步** |
| `manifest.yml` | SAP CF 部署清单（`cf push` 用） |
| `.github/workflows/build-image.yml` | CI：推送即构建并发布到 GHCR |

---

## 鸣谢

参考 `vevc/ubuntu` 的设计思路，针对持久化挂载、流量统计、灵活保活与 P2P 出站代理做了深度定制。
