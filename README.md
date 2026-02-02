# zvps-super README

拉取镜像后的操作流程
如果你现在刚拉取镜像，流程如下：

## 步骤 1：初次启动（默认模式）

仅设置环境变量：

SSH_USER: 你的用户名

SSH_PWD: 你的密码

不设置 SSH_CMD，不挂载存储。
<img width="1141" height="467" alt="image" src="https://github.com/user-attachments/assets/d1602ddb-252e-4e56-bef2-e8e6e957a362" />



## 步骤 2：准备持久化“大脑”

通过 SSH 连入容器（一般平台自带，如果不自带web端ssh请看到最后），手动创建 boot 目录：

Bash
mkdir -p /home/zv/boot

将系统默认的 Supervisor 配置拷贝出来作为模板：

Bash
sudo cp /etc/supervisor/supervisord.conf /home/zv/boot/supervisord.conf
或者手动创建一个最简的配置，内容如下面步骤 3

## 步骤 3：配置持久化文件

编辑 /home/zv/boot/supervisord.conf，确保包含基础服务：

Ini, TOML
[supervisord]
nodaemon=true
user=root

[program:sshd]
command=/usr/sbin/sshd -D
autorestart=true

[program:ttyd]
command=/usr/local/bin/ttyd -W bash
autorestart=true

## 步骤 4：挂载存储：将持久化卷挂载到 /home/zv/boot。

设置变量：添加 SSH_CMD = /usr/bin/supervisord -n -c /home/zv/boot/supervisord.conf。
<img width="1143" height="564" alt="image" src="https://github.com/user-attachments/assets/1bc77532-93f6-4f81-b8e1-f268004cd485" />

或者如果平台支持且你想用 Arguments，填 ["supervisord", "-n", "-c", "/home/zv/boot/supervisord.conf"]
<img width="606" height="227" alt="image" src="https://github.com/user-attachments/assets/3c1f054e-2aa4-415e-9baa-398ff893e911" />

重启容器

# 写在最后
1、本镜像集成ttyd，所以当你使用的平台不支持ssh或者你习惯用ttyd，请添加http类型的网络端口为7681的外部可访问链接，生成后点击登录即可<img width="1119" height="273" alt="image" src="https://github.com/user-attachments/assets/f17318c0-7965-489e-91f2-9a6bb82d70e3" />
2、注意执行步骤，最初一定不要挂载永久化存储位置和设置SSH_CMD
3、以上流程演示中使用了默认的”zv“用户名，请根据个人设置进行相应修改

## 鸣谢：vevc大佬项目的思路@(https://github.com/vevc/ubuntu)
