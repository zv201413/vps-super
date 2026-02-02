#!/bin/bash
set -e

# 1. 安全地获取环境变量，并设置默认值（防止变量为空导致报错）
# 使用你指定的新变量名
MY_USER="${SSH_USER:-zv}"
MY_PASS="${SSH_PWD:-105106}"

echo "正在配置用户: $MY_USER ..."

# 2. 创建用户（如果不存在）
if ! id -u "$MY_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$MY_USER"
fi

# 3. 【核心修正】强制注入密码哈希到 shadow 文件
# 这样可以直接跳过所有复杂的 PAM 校验逻辑，直接匹配密码
ENCRYPTED_PW=$(openssl passwd -6 "$MY_PASS")
# 这一行会将 shadow 文件中该用户的密码部分强制替换为我们生成的哈希
sed -i "s|^${MY_USER}:[^:]*:|${MY_USER}:${ENCRYPTED_PW}:|" /etc/shadow

# 4. 简化 PAM 认证（解决你之前看到的 PAM: Authentication failure）
# 移除所有可能卡住容器认证的审计模块，只保留最基础的本地校验
cat > /etc/pam.d/sshd <<EOF
auth       required     pam_unix.so
account    required     pam_unix.so
session    required     pam_unix.so
password   required     pam_unix.so
EOF

# 5. 权限与快捷键 (Alias)
# 给 root 和新用户都加上 sctl 别名
echo "alias sctl='sudo supervisorctl'" >> /root/.bashrc
echo "alias sctl='sudo supervisorctl'" >> "/home/$MY_USER/.bashrc"
# 确保 sudo 权限
echo "$MY_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$MY_USER"

# 6. 确保 SSH 运行目录并清理旧进程
mkdir -p /run/sshd
pkill sshd || true

# 7. 启动进程管理器
echo "配置完成，正在启动 Supervisor..."
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
