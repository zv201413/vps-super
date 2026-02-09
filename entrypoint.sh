#!/usr/bin/env sh
set -e

# --- 1. 设置默认值 (保持原样) ---
USER_NAME=${SSH_USER:-zv}
USER_PWD=${SSH_PWD:-105106}

echo "👤 当前用户: $USER_NAME"

# --- 2. 动态创建用户 (保持原样) ---
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$USER_NAME" || true
fi

chown -R "$USER_NAME":"$USER_NAME" /home/"$USER_NAME"

echo "root:$USER_PWD" | chpasswd
echo "$USER_NAME:$USER_PWD" | chpasswd
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/init-users
ln -sf /usr/bin/supervisorctl /usr/local/bin/sctl

# --- 3. 处理持久化配置 (保持原样) ---
BOOT_DIR="/home/$USER_NAME/boot"
BOOT_CONF="$BOOT_DIR/supervisord.conf"
TEMPLATE="/usr/local/etc/supervisord.conf.template"

mkdir -p "$BOOT_DIR"

if [ ! -f "$BOOT_CONF" ] || [ "$FORCE_UPDATE" = "true" ]; then
    echo "📦 正在初始化/更新持久化配置模板..."
    cp "$TEMPLATE" "$BOOT_CONF"
    sed -i "s/{SSH_USER}/$USER_NAME/g" "$BOOT_CONF"
    chown "$USER_NAME":"$USER_NAME" "$BOOT_CONF"
fi

# --- 【CF_TOKEN 判断逻辑】 ---
if [ -z "$CF_TOKEN" ]; then
    echo "⚠️ 未发现 CF_TOKEN，正在配置中禁用 Cloudflared..."
    # 注释掉配置文件中从 [program:cloudflared] 到日志输出的行
    sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^/;/ ' "$BOOT_CONF"
else
    echo "☁️ 发现 CF_TOKEN，配置已激活."
    # 确保没有被注释（移除行首的分号）
    sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^;//' "$BOOT_CONF"
fi
# ----------------------------------------------

# 设置 sctl 命令别名 (保持原样)
echo "alias sctl='supervisorctl -c $BOOT_CONF'" >> /etc/bash.bashrc

# --- 4. 启动 (保持原样) ---
if [ -n "$SSH_CMD" ]; then
    echo "🚀 执行自定义 SSH_CMD: $SSH_CMD"
    exec /bin/sh -c "$SSH_CMD"
else
    echo "✅ 启动 Supervisor (用户: $USER_NAME)..."
    exec /usr/bin/supervisord -n -c "$BOOT_CONF"
fi
