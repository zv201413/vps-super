#!/usr/bin/env sh
set -e

# --- 1. 设置默认值 ---
USER_NAME=${SSH_USER:-zv}
USER_PWD=${SSH_PWD:-105106}

echo "👤 当前用户: $USER_NAME"

# 【精确分流逻辑】
if [ "$USER_NAME" = "root" ]; then
    TARGET_HOME="/root"
    echo "⚠️ 模式：ROOT 挂载模式 | 路径：$TARGET_HOME"
else
    TARGET_HOME="/home/$USER_NAME"
    echo "🏠 模式：普通用户模式 | 路径：$TARGET_HOME"
fi

# --- 2. 动态创建用户 (如果是 root 则跳过创建) ---
if [ "$USER_NAME" != "root" ]; then
    if ! id -u "$USER_NAME" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$USER_NAME" || true
    fi
    # 仅在非 root 模式下修复 /home 权限
    [ -d "$TARGET_HOME" ] && chown -R "$USER_NAME":"$USER_NAME" "$TARGET_HOME"
fi

echo "root:$USER_PWD" | chpasswd
[ "$USER_NAME" != "root" ] && echo "$USER_NAME:$USER_PWD" | chpasswd
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/init-users
ln -sf /usr/bin/supervisorctl /usr/local/bin/sctl

# --- 3. 处理持久化配置 ---
BOOT_DIR="$TARGET_HOME/boot"
BOOT_CONF="$BOOT_DIR/supervisord.conf"
TEMPLATE="/usr/local/etc/supervisord.conf.template"

mkdir -p "$BOOT_DIR"

# 【核心：后期 DIY 脚本执行】
# 如果你在挂载目录放了 init_env.sh，这里会自动执行
if [ -f "$TARGET_HOME/init_env.sh" ]; then
    echo "🚀 运行后期 DIY 初始化 (init_env.sh)..."
    sh "$TARGET_HOME/init_env.sh"
fi

if [ ! -f "$BOOT_CONF" ] || [ "$FORCE_UPDATE" = "true" ]; then
    echo "📦 正在初始化/更新持久化配置模板..."
    cp "$TEMPLATE" "$BOOT_CONF"
    sed -i "s/{SSH_USER}/$USER_NAME/g" "$BOOT_CONF"
    [ -d "$TARGET_HOME" ] && chown -R "$USER_NAME":"$USER_NAME" "$BOOT_DIR"
fi

# --- 【CF_TOKEN 判断逻辑】 ---
if [ -z "$CF_TOKEN" ]; then
    echo "⚠️ 未发现 CF_TOKEN，禁用 Cloudflared..."
    sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^/;/ ' "$BOOT_CONF"
else
    echo "☁️ 发现 CF_TOKEN，激活 Cloudflared."
    sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^;//' "$BOOT_CONF"
fi

# 设置 sctl 别名
echo "alias sctl='supervisorctl -c $BOOT_CONF'" >> /etc/bash.bashrc

# --- 4. 启动 ---
# 只有在 SSH_CMD 为空时才启动 Supervisor
if [ -n "$SSH_CMD" ]; then
    echo "🚀 执行自定义 SSH_CMD: $SSH_CMD"
    # 提醒：这会替代掉 Supervisor
    exec /bin/sh -c "$SSH_CMD"
else
    echo "✅ 启动 Supervisor (用户: $USER_NAME)..."
    exec /usr/bin/supervisord -n -c "$BOOT_CONF"
fi
