#!/bin/bash
set -e

# 1. 强制覆盖 SSH 关键配置
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sed -i 's/^#\?UsePAM.*/UsePAM no/g' /etc/ssh/sshd_config

# 2. 动态创建用户
if ! id -u "${USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${USER}"
fi

# 3. 密码与免密 sudo 配置
echo "${USER}:${PWD}" | chpasswd
echo "root:${PWD}" | chpasswd
echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-custom-user

# 4. 自动注入 sctl 别名
for HOME_DIR in "/root" "/home/${USER}"; do
    if [ -d "$HOME_DIR" ]; then
        sed -i '/alias sctl=/d' "$HOME_DIR/.bashrc"
        echo "alias sctl='sudo supervisorctl'" >> "$HOME_DIR/.bashrc"
    fi
done
chown -R "${USER}:${USER}" "/home/${USER}" 2>/dev/null || true

# 5. 时区设置
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
echo $TZ > /etc/timezone

# 6. 启动主进程
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
