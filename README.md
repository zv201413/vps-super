# 🚀 ZVPS-Super 基础镜像

基于 Ubuntu 的通用型容器基础镜像。支持通过环境变量动态接管启动进程，结合 Supervisor 实现多服务保活与持久化存储。

---

## 🛠️ 拉取镜像后的操作流程

> [!IMPORTANT]
> **注意执行步骤：** 最初一定不要挂载永久化存储位置，也请勿设置 `SSH_CMD`。

### 步骤 1：初次启动（默认模式）

#### 1、设置环境变量
如果你现在刚拉取镜像，请先在平台（Zeabur、koyeb 等）仅设置基础环境变量：

* **SSH_USER**: 你的用户名
* **SSH_PWD**: 你的密码
* **CF_TOKEN**: 见下文说明

#### 2、开端口
* 设置 TCP 端口为 `22`（一定要打开外部可访问）
  <img width="1194" height="340" alt="image" src="https://github.com/user-attachments/assets/6361b40f-a977-46fc-ab91-c9e4d8e388f9" />

* 设置 HTTP 端口为 `7681`

#### 说明
1、**Web SSH / ttyd**: 如果你的平台没有 Web 端 SSH，或者你想体验 Web 版终端：打开外部访问端口 `7681`，访问生成的链接即可。
<img width="1322" height="301" alt="image" src="https://github.com/user-attachments/assets/efb63767-7151-4efd-8cdf-7613d9f5e556" />

2、**CF_TOKEN**: （如果你需要本地终端/第三方软件 SSH 登录）填入隧道 Token。用法见“写在最后”
> [!IMPORTANT]
> 请确保 Cloudflare 后台设置的服务类型为 "SSH"，Hostname 绑定你的域名。
<img width="1126" height="299" alt="image" src="https://github.com/user-attachments/assets/1f8ac238-bafe-46c6-87dd-1df424aed195" />

---

### 步骤 2：准备持久化“大脑”

通过平台自带的 Web 终端连入容器，手动创建 `boot` 目录：

```bash
mkdir -p /home/zv/boot

随后将系统默认的 Supervisor 配置拷贝出来作为模板（或者直接参考步骤 3 手动创建）

Bash
sudo cp /etc/supervisor/supervisord.conf /home/zv/boot/supervisord.conf
```
### 步骤 3（可选）：配置持久化文件
编辑 /home/zv/boot/supervisord.conf，确保包含基础服务：

```Ini, TOML
[supervisord]
nodaemon=true
user=root

[program:sshd]
command=/usr/sbin/sshd -D
autostart=true
autorestart=true

[program:ttyd]
command=/usr/local/bin/ttyd -W bash
autostart=true
autorestart=true

[program:cloudflare]
# 镜像已集成智能探测：若环境变量无 CF_TOKEN，系统启动时将自动屏蔽此块
command=cloudflared tunnel --no-autoupdate run --token %(ENV_CF_TOKEN)s
autostart=true
autorestart=true
```
### 步骤 4：启用基础模式
挂载存储：将持久化卷挂载到 /home/zv/boot。

设置启动变量：添加环境变量 SSH_CMD = /usr/bin/supervisord -n -c /home/zv/boot/supervisord.conf。

<img width="1357" height="551" alt="image" src="https://github.com/user-attachments/assets/e394f4cd-f2df-4b2e-bc62-133cdcbd7c2b" />


> [!TIP]
> 如果平台支持且你想用 Arguments，可填写：["supervisord", "-n", "-c", "/home/zv/boot/supervisord.conf"]

<img width="606" height="227" alt="image" src="https://github.com/user-attachments/assets/3c1f054e-2aa4-415e-9baa-398ff893e911" />

重启容器：完成最后部署。

💡 写在最后
* **Web 终端支持**:本镜像集成 ttyd。如果你习惯用ttyd代替平台自带 Web 登录，请确保 7681 端口已映射。 
* **强烈推荐：WindTerm (媲美 FinalShell，免手动转发)**:
  1. **配置环境变量**：下载`cloudflared.exe`，并将其所在目录（如 C:\btp-tool）添加到系统【环境变量-Path】中。
  2. **配置 WindTerm**：新建会话 -> 在左侧【会话】栏找到【连接】 -> 【代理】 -> 【类型】选择【自定义命令】。
  3. **输入命令**：`cloudflared access ssh --hostname 你的域名`。
  4. **完成**：点击连接即可，WindTerm 会自动处理文件管理和监控，体验非常顺滑。

* **关于 FinalShell**:
  由于 FinalShell 不支持自定义连接代理命令，仍需手动在 CMD 运行桥接命令后再连 localhost，建议迁移至 WindTerm 以获得更好体验。

* **用户名适配**: 以上流程演示中使用默认的 zv 用户名，请根据你个人设置的 SSH_USER 修改路径。

🤝 鸣谢
本项目参考了 vevc/ubuntu 大佬的设计思路，并针对数据持久化、Supervisor 智能启动及 ttyd 集成等场景进行了优化与补充。
