#!/usr/bin/env sh
set -e

# 1. 基础环境初始化（每次启动都强制执行，确保权限和账户永远正确）
if ! id -u "$SSH_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$SSH_USER"
fi
echo "$SSH_USER:$SSH_PASSWORD" | chpasswd
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/init-users

# 2. 注入你的神级别名 sctl
echo "alias sctl='sudo supervisorctl'" >> /root/.bashrc
echo "alias sctl='sudo supervisorctl'" >> "/home/$SSH_USER/.bashrc"

# 3. 核心：支持通过变量动态修改启动命令
# 如果设置了 START_CMD，就用它替换掉默认的 CMD
if [ -n "$START_CMD" ]; then
    set -- $START_CMD
fi

# 执行最终命令 (可能是默认的 sshd，也可能是你变量里的 supervisord)
exec "$@"
