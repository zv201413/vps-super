#!/bin/bash
set -e

# 1. 动态创建用户
if ! id -u "${USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${USER}"
fi

# 2. 密码与免密 sudo 配置
echo "${USER}:${PWD}" | chpasswd
echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-custom-user

# 3. 自动注入 sctl 别名到新用户的 .bashrc 和 root 的 .bashrc
for HOME_DIR in "/root" "/home/${USER}"; do
    if [ -d "$HOME_DIR" ]; then
        # 避免重复添加
        sed -i '/alias sctl=/d' "$HOME_DIR/.bashrc"
        echo "alias sctl='sudo supervisorctl'" >> "$HOME_DIR/.bashrc"
        # 确保家目录权限正确
        chown -R "${USER}:${USER}" "/home/${USER}" 2>/dev/null || true
    fi
done

# 4. 时区设置
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
echo $TZ > /etc/timezone

# 5. 启动主进程
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
