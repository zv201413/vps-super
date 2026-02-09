#!/usr/bin/env sh
set -e

# --- 1. 设置默认值 ---
USER_NAME=${SSH_USER:-zv}
USER_PWD=${SSH_PWD:-105106}

echo "👤 当前用户: $USER_NAME"

# 【精确路径分流】
if [ "$USER_NAME" = "root" ]; then
    TARGET_HOME="/root"
    echo "⚠️ 模式：ROOT 挂载模式 | 路径：$TARGET_HOME"
else
    TARGET_HOME="/home/$USER_NAME"
    echo "🏠 模式：普通用户模式 | 路径：$TARGET_HOME"
fi

# --- 2. 动态创建用户 ---
if [ "$USER_NAME" != "root" ]; then
    if ! id -u "$USER_NAME" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$USER_NAME" || true
    fi
    [ -d "$TARGET_HOME" ] && chown -R "$USER_NAME":"$USER_NAME" "$TARGET_HOME"
fi

echo "root:$USER_PWD" | chpasswd
[ "$USER_NAME" != "root" ] && echo "$USER_NAME:$USER_PWD" | chpasswd
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/init-users
ln -sf /usr/bin/supervisorctl /usr/local/bin/sctl

# --- 3. 自动化生成 init_env.sh (当 GB 变量开启且脚本不存在时) ---
if [ -n "$GB" ] && [ ! -f "$TARGET_HOME/init_env.sh" ]; then
    echo "📊 检测到 GB 变量，正在自动生成流量统计配置..."
    cat << 'EOF' > "$TARGET_HOME/init_env.sh"
#!/bin/sh
# 1. 安装 vnstat
echo "📥 正在安装 vnstat..."
apt-get update && apt-get install -y vnstat

# 2. 数据库永久化 (迁移至挂载目录下的 vnstat_data)
# 自动检测当前用户家目录
MY_HOME=$(eval echo ~$USER)
mkdir -p "$MY_HOME/vnstat_data"
if [ -d "/var/lib/vnstat" ] && [ ! -L "/var/lib/vnstat" ]; then
    rm -rf /var/lib/vnstat
    ln -s "$MY_HOME/vnstat_data" /var/lib/vnstat
    echo "🔗 vnstat 数据库已建立永久化链接"
fi

# 3. 启动服务
/etc/init.d/vnstat start 2>/dev/null || vnstatd -d

# 4. 注入 gb 快捷指令 (MB/GB 双显版)
# 使用 printf 格式化数字，保留两位小数
BASH_FILE="$MY_HOME/.bashrc"
GB_ALIAS="alias gb='cat /proc/net/dev | grep eth0 | awk \"{print \\\"📥 RX: \\\" sprintf(\\\"%.2f\\\", \$2/1024/1024) \\\" MB (\\\" sprintf(\\\"%.2f\\\", \$2/1024/1024/1024) \\\" GB) | 📤 TX: \\\" sprintf(\\\"%.2f\\\", \$10/1024/1024) \\\" MB (\\\" sprintf(\\\"%.2f\\\", \$10/1024/1024/1024) \\\" GB)\\\"}\"'"
grep -q "alias gb=" "$BASH_FILE" || echo "$GB_ALIAS" >> "$BASH_FILE"
echo "✅ gb 快捷指令已注入 $BASH_FILE"
EOF
    chmod +x "$TARGET_HOME/init_env.sh"
    chown "$USER_NAME":"$USER_NAME" "$TARGET_HOME/init_env.sh"
fi

# --- 4. 处理持久化配置 ---
BOOT_DIR="$TARGET_HOME/boot"
BOOT_CONF="$BOOT_DIR/supervisord.conf"
TEMPLATE="/usr/local/etc/supervisord.conf.template"

mkdir -p "$BOOT_DIR"

# 【执行 DIY 勾子】
if [ -f "$TARGET_HOME/init_env.sh" ]; then
    echo "🚀 运行后期 DIY 初始化 (init_env.sh)..."
    # 使用 sh 执行以确保兼容性
    sh "$TARGET_HOME/init_env.sh"
fi

if [ ! -f "$BOOT_CONF" ] || [ "$FORCE_UPDATE" = "true" ]; then
    echo "📦 正在初始化/更新持久化配置模板..."
    cp "$TEMPLATE" "$BOOT_CONF"
    sed -i "s/{SSH_USER}/$USER_NAME/g" "$BOOT_CONF"
    [ -d "$TARGET_HOME" ] && chown -R "$USER_NAME":"$USER_NAME" "$BOOT_DIR"
fi

# --- 5. CF_TOKEN 判断 ---
if [ -z "$CF_TOKEN" ]; then
    echo "⚠️ 未发现 CF_TOKEN，禁用 Cloudflared..."
    sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^/;/ ' "$BOOT_CONF"
else
    echo "☁️ 发现 CF_TOKEN，激活 Cloudflared."
    sed -i '/\[program:cloudflared\]/,/stdout_logfile/s/^;//' "$BOOT_CONF"
fi

# 注入全局别名
echo "alias sctl='supervisorctl -c $BOOT_CONF'" >> /etc/bash.bashrc

# --- 6. 启动控制 ---
# 如果定义了 SSH_CMD，它将接管容器进程（Supervisor 将不启动）
if [ -n "$SSH_CMD" ]; then
    echo "🚀 执行自定义 SSH_CMD: $SSH_CMD"
    exec /bin/sh -c "$SSH_CMD"
else
    echo "✅ 启动 Supervisor (配置: $BOOT_CONF)..."
    exec /usr/bin/supervisord -n -c "$BOOT_CONF"
fi
