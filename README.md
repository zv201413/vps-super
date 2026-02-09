# 🚀 ZVPS-Super 2026 增强版

基于 **Ubuntu** 的智能型容器基础镜像。支持通过环境变量动态接管启动进程，结合 **Supervisor** 实现多服务保活、**全自动配置初始化**与持久化存储。

---

## 🛠️ 拉取镜像后的操作流程

> [!NOTE]
> **重要提示：** 如无特殊说明，以下示例中的用户名 `zv` 和密码 `105106` 均可由使用者自定义，但请务必在环境变量配置与远程连接时保持一致。

### 步骤 1：一站式环境配置

在平台部署时，请完成以下设置：

#### 1. 设置环境变量
| 变量名 | 必填 | 说明 | 默认值 / 示例 |
| :--- | :--- | :--- | :--- |
| **SSH_USER** | 否 | 你的登录用户名 | `zv` |
| **SSH_PWD** | 否 | 你的登录密码 | `105106` |
| **CF_TOKEN** | 否 | Cloudflare Tunnel Token | 当容器端口不开放，用于开启域名访问实现本地ssh |
| **SSH_CMD** | 否 | 接管启动指令 | `/usr/bin/supervisord -n -c /home/zv/boot/supervisord.conf` |

> [!TIP]
> **Cloudflare 配置关键点：**
> 在 Cloudflare Tunnel 控制台添加 Public Hostname 时：
> - **Service Type:** 必须选择 `SSH`
> - **URL:** 必须填写 `localhost:22`

#### 2. 挂载持久化存储 (Storage)
- **挂载路径**: `/home/zv`

#### 3. 开放端口
- **TCP 22**: SSH 服务端口
- **HTTP 7681**: 内置 Web 终端 (ttyd)
---

### 步骤 2：基础玩法

容器部署完成后，你将获得一个开箱即用的 VPS 环境：

1. **快捷命令**: 镜像已全局内置 `sctl` 软链接。进入终端后，直接输入 `sctl` 即可查看所有进程状态（无需 sudo）。
2. **Web SSH 访问**: 
   - 你可以通过浏览器直接访问：`https://你的域名`（7681 端口对应映射的外部访问链接 ）。
   - 点开链接后即可进入 Web 端终端，实现免客户端登录。
3. **智能探测**: 
   - [x] 若设置了 `CF_TOKEN`，Cloudflare 隧道将自动启动。
   - [ ] 若未设置，脚本会自动在配置文件中注释相关条目，确保环境纯净。"
---

### 步骤 3：进阶配置持久化

由于配置文件已自动写入 `/home/zv/boot/supervisord.conf`：

- **自定义服务**: 你可以随时编辑该文件，添加如 `xray`、`gost` 等自定义进程。
- **即时生效**: 修改文件后，在终端执行 `sctl update` 即可热加载配置，无需重启容器。
- **永久保留**: 即使镜像更新或容器销毁，只要持久化卷还在，配置都会自动恢复。
---
## 🔐 进阶：通过本地 SSH 客户端登录

由于容器平台通常不直接暴露 22 端口，建议使用 **Cloudflared 隧道** 实现本地 SSH 直接访问。

### 1. 本地环境准备 (最简操作版)

* **下载客户端**: 前往 [Cloudflared Releases](https://github.com/cloudflare/cloudflared/releases) 下载 Windows 版本的 `cloudflared-windows-amd64.exe`。
* **打开终端**: 
    1. 进入你下载该文件的文件夹。
    2. 在文件夹地址栏输入 `cmd` 并回车，或者按住 Shift 键在空白处点击右键选择“在此处打开 PowerShell/终端”。
  
> [!NOTE]
> 确保你在 Cloudflare 控制台的 Tunnel 已经配置好（Public Hostname 对应 `ssh://localhost:22`），无需额外设置 Access 策略，只要有域名和 Token 即可。

### 1.1（可选，该项较复杂非必须）本地环境准备 (安全持久验证版)

* **下载客户端**: 前往 [Cloudflared Releases](https://github.com/cloudflare/cloudflared/releases) 下载对应系统的后缀为 `.exe` (Windows) 或二进制文件。
* **配置环境变量**: 将下载好的 `cloudflared.exe` 路径添加到 Windows 的 **系统环境变量 Path** 中，确保在终端输入 `cloudflared -v` 能显示版本号。
* **配置 Access 策略 (关键)**:
    1.  登录 [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) 仪表板。
    2.  进入 **Access** -> **Applications** -> **Add an application** -> **Self-hosted**。
    3.  **Application name**: 随便填（如 `My-SSH`）。
    4.  **Domain**: 填写你为 Tunnel 绑定的那个二级域名。
    5.  **Policies**: 名字随便填，**Selector** 选择 `Emails`，并在 **Value** 中填入你的接收验证码的邮箱。
    6.  保存后，只有通过邮箱验证的人才能拨通此 SSH 隧道。

### 2. 万能 SSH 登录指令 (在 CMD/power 输入以下指令后以实现ssh，如果第三方工具登录请最小化窗口)

 ```cmd
start /b cloudflared-windows-amd64.exe access tcp --hostname 你的域名 --url localhost:2222 & ssh -p 2222 root@127.0.0.1
```
#### 📌2.1 登录信息详解
如果你使用第三方 SSH 工具（如 **PuTTY**, **Xshell**, **FinalShell** 或 **Termius**）进行连接，请参考以下配置表：

| 配置项 | 填入内容 | 说明 |
| :--- | :--- | :--- |
| **主机名 (Host)** | `127.0.0.1` | **必须填这个**。隧道已将远程流量映射到你本地电脑 |
| **端口 (Port)** | `2222` | **必须与指令中 --url localhost: 后的端口一致** |
| **用户名 (User)** | `root` | 用自定义的用户名（如 `zv`）也可以但是没有root权限 |
| **密码 (Password)** | `你的 SSH_PWD` | **你在环境变量中设置的密码（注意不是 SSH_PASSWORD）** |"
#### ⚠️2.2 特别说明
1. * **端口可自定义**：你可以将 `2222` 更改为任何你喜欢的本地空闲端口（例如 `3333`、`5000` 或 `8888`）。
   * **必须同步修改**：如果你更改了端口，请务必确保指令中 `--url localhost:XXXX` 和 `ssh -p XXXX` 中的两个数字**完全相同**。
   * **示例 (若改为 3333):**
    ```dos
    start /b cloudflared-windows-amd64.exe access tcp --hostname 你的域名 --url localhost:3333 & ssh -p 3333 root@127.0.0.1
    ```
2. **用户切换技巧**:
   - 进入终端后，输入 `su zv` 切换用户；按 `Ctrl + D` 退出并恢复 root。
---

## 🏁 流程总结

- **填变量**：在平台面板设置 `SSH_USER`、`SSH_PWD`、`CF_TOKEN`（自定义或保持默认）。
- **挂存储**：添加 Storage 挂载到 `/home/zv/boot`。
- **点部署**：一般不用管 `SSH_CMD` 变量，除非你需要完全自定义启动指令。
- **进终端**：部署成功后，`/home/zv/boot/supervisord.conf` 已经自动生成，`sctl` 已接管并运行所有后台服务。
---

**🤝 鸣谢**
本项目参考了 `vevc/ubuntu` 的设计思路，并针对 Zeabur/Northflank 等平台的持久化存储、Supervisor 智能初始化及 ttyd 交互体验进行了深度优化。



