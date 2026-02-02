# 🚀 ZVPS-Super 2026 增强版

基于 Ubuntu 的智能型容器基础镜像。支持通过环境变量动态接管启动进程，结合 Supervisor 实现多服务保活、**全自动配置初始化**与持久化存储。

---

## 🛠️ 拉取镜像后的操作流程

> [!IMPORTANT]
> **新版核心改进：** 镜像已集成“智能引导”脚本。首次部署时**推荐直接挂载存储**并设置变量，系统会自动完成所有初始化工作，无需再手动执行 `mkdir` 或 `cp`。

### 步骤 1：一站式环境配置

在平台（Zeabur、Koyeb 等）部署时，请完成以下设置：

#### 1. 设置环境变量
* **SSH_USER**: 你的用户名（默认 `zv`）
* **SSH_PWD**: 你的登录密码
* **CF_TOKEN**: (可选) 填入 Cloudflare Tunnel Token 以开启域名访问
* **SSH_CMD**: (选填) 若需完全接管启动指令，建议填写：
  `/usr/bin/supervisord -n -c /home/zv/boot/supervisord.conf`

#### 2. 挂载持久化存储 (Storage)
* **挂载路径**: `/home/zv/boot`
* **说明**: 只要挂载了此路径，脚本启动时若检测到目录为空，会自动将镜像内置的“满血版”配置模板初始化到该目录下。

#### 3. 开放端口
* **TCP 22**: SSH 服务端口。
* **HTTP 7681**: 内置 Web 终端 (ttyd)。

---

### 步骤 2：验证与管理

容器部署完成后，你将获得一个开箱即用的 VPS 环境：

1. **快捷命令**: 镜像已全局内置 `sctl` 软链接。进入终端后，直接输入 `sctl` 即可查看所有进程状态（无需 sudo）。
2. **智能探测**: 
   - 若设置了 `CF_TOKEN`，Cloudflare 隧道将自动启动。
   - 若未设置，脚本会自动在配置文件中注释掉相关条目，确保 `sctl` 列表中环境纯净且不报错。



---

### 步骤 3：进阶配置持久化

由于配置文件已自动写入 `/home/zv/boot/supervisord.conf`：

* **自定义服务**: 你可以随时编辑该文件，添加如 `xray`、`gost` 等自定义进程。
* **即时生效**: 修改文件后，在终端执行 `sctl update` 即可热加载配置，无需重启容器。
* **永久保留**: 即使镜像更新或容器销毁，只要持久化卷还在，你的所有配置和服务改动都会在下次启动时自动恢复。

---

## 💡 技巧与鸣谢

* **Web 终端支持**: 本镜像集成 `ttyd`。如果你不想使用平台自带终端，访问 `http://你的IP或域名:7681` 即可登录。
* **WindTerm 推荐**:
  1. 系统 Path 添加 `cloudflared.exe`。
  2. WindTerm 新建会话 -> 代理 -> 类型选择【自定义命令】。
  3. 输入：`cloudflared access ssh --hostname 你的域名`。
  * *WindTerm 会自动处理文件同步与终端监控，是本镜像的最佳拍档。*

---

## 💡 流程总结

填变量：SSH_PWD、CF_TOKEN。

挂存储：添加 Storage 挂载到 /home/zv/boot。

点部署：不用管 SSH_CMD。

进终端：/home/zv/boot/supervisord.conf 已经存在，且 sctl 已经接管了所有服务。

**🤝 鸣谢**
本项目参考了 vevc/ubuntu 的设计思路，并针对 Zeabur/Koyeb 等平台的持久化存储、Supervisor 智能初始化及 ttyd 交互体验进行了深度优化。
