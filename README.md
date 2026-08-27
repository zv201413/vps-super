# ZVPS-Super

> 基于 **Ubuntu 22.04** 的「环境变量驱动」多服务容器镜像。
> 设好变量 → 服务自动拉起、配置自动生成、数据自动持久化，由 **Supervisor** 统一保活。

专为 **免费容器平台**（Koyeb / Railway / Render / Zeabur / HuggingFace Spaces / SAP BTP 等，无 Docker 访问权、常无公网入站端口）以及**自建 Docker / VPS** 设计。一个镜像集成：SSH、Web 终端、Cloudflare 隧道、循环保活、流量统计、一次性命令注入以及 **P2P 打洞的 Hysteria2 出站代理**。

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

> 镜像仅 `EXPOSE 7681`，以避免 PaaS 平台将路由误绑定到 22 等端口（详见 [原理与避坑清单](docs/pitfalls.md)）。

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

> PaaS 面板部署（Koyeb / Railway 等）只需在环境变量面板填入对应 KEY/VALUE 即可。

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

---

## 常用排障命令

```bash
sctl status                                      # 查看所有 supervisor 服务状态
vps                                              # 运行内置 VPS 性能与网络体检工具箱
```

---

## 深入文档

- **[操作指南 (docs/operations.md)](docs/operations.md)** —— 环境变量完整说明、持久卷挂载规范、HYP2P 客户端配置与一键批处理、构建与发布。
- **[原理与避坑清单 (docs/pitfalls.md)](docs/pitfalls.md)** —— 为什么只 EXPOSE 7681、CF 隧道代理机制与延迟、`vps` 探针无 tty 死循环等实踩记录。

---

## 仓库文件

| 文件 / 目录 | 作用 |
| :--- | :--- |
| `Dockerfile` | 镜像构建（集成 ttyd / cloudflared / hysteria / sing-box 等） |
| `entrypoint.sh` | 环境变量解析、supervisor 配置生成与服务编排入口 |
| `vps` | VPS 硬件与网络体检工具箱 |
| `fragments/` | Supervisor 模块化服务配置片段 |
| `manifest.yml` | SAP BTP Cloud Foundry 部署清单 |

---

## 鸣谢

参考 `vevc/ubuntu` 的设计思路，针对持久化挂载、流量统计、灵活保活与 P2P 出站代理做了深度定制。
