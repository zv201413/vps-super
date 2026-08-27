# HYP2P 进阶与客户端配置指南

> 返回 [主界面 (README)](../README.md) ｜ 查看 [原理与避坑清单](pitfalls.md)

---

## 一、自建牵线服务器 (hysteria-realm-server)

在一台具有公网 IP 的服务器上运行 [hysteria-realm-server](https://github.com/apernet/hysteria-realm-server)：

```bash
git clone https://github.com/apernet/hysteria-realm-server.git && cd hysteria-realm-server
docker build -t hy-realm .
docker run -d --name hy-realm --restart unless-stopped -p 8443:8443 \
  -e HYSTERIA_REALM_TOKEN="你的token" -e HYSTERIA_REALM_LISTEN=":8443" hy-realm
# 防火墙放行 TCP 8443
```

### 容器端对接环境变量

在 ZVPS 容器环境变量中填入：
- **裸跑（无 TLS）**：`HYP2P_RV="realm+http://你的token@IP:8443/名字"`
- **配置了 TLS / 域名反代**：`HYP2P_RV="realm://你的token@域名:8443/名字"`

> ⚠️ Scheme 选择的详细判据与自签证书机制见 [原理与避坑清单 · realm scheme 选择](pitfalls.md#三realm-还是-realmhttp)。

---

## 二、Windows 一键批处理脚本

容器部署后，可通过批处理脚本实现本地一键直连，无需每次手动敲命令行。

### 1. 前置准备
将官方客户端 [hysteria-windows-amd64.exe](https://github.com/apernet/hysteria/releases/latest/download/hysteria-windows-amd64.exe) 下载并放入桌面 `hysteria\` 目录下（重命名为 `hysteria.exe`）。

### 2. 获取容器连接凭据
在容器终端执行：
```bash
cat /home/zv/p2p/realm_name            # 获取 realm 名
cat /home/zv/p2p/cert_sha256           # 获取证书指纹
```

### 3. 创建批处理脚本
在本地桌面创建 `hy2-隧道.bat`，写入以下内容并将前三行替换为容器的实际值：

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

### 4. 运行与停止
- **启动**：双击运行 `hy2-隧道.bat`，自动打洞建立 P2P 直连，本地应用设置 SOCKS5 代理为 `127.0.0.1:25002` 即可。
- **停止**：再次双击运行同一脚本，将自动终止后台进程并关闭隧道。

> ⚠️ 无持久卷平台（Koyeb 等）重启后凭据会重新生成，如遇连接失败需重新 `cat` 获取最新指纹并更新脚本中的三行变量。
