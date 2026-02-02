#!/usr/bin/env sh
set -e

# 1. 基础环境初始化
if ! id -u "$SSH_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$SSH_USER"
fi
echo "$SSH_USER:$SSH_PWD" | chpasswd
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/init-users

# 2. 注入快捷别名 sctl
echo "alias sctl='sudo supervisorctl'" >> /root/.bashrc
echo "alias sctl='sudo supervisorctl'" >> "/home/$SSH_USER/.bashrc"

# 3. 核心分流与智能 CF 探测逻辑
# 确定配置文件的路径，默认为镜像内的路径，如果 SSH_CMD 里有 .conf 则更新它
CONF_FILE="/etc/supervisor/supervisord.conf"

if [ -n "$SSH_CMD" ]; then
    # 将 SSH_CMD 转换为位置参数
    set -- $SSH_CMD
    # 尝试从参数中提取用户指定的 .conf 文件路径
    for arg in "$@"; do
        case "$arg" in
            *.conf) CONF_FILE="$arg" ;;
        esac
    done
fi

# 如果没设置 CF_TOKEN，动态注释掉配置文件中的 cloudflare 块
if [ -f "$CONF_FILE" ] && [ -z "$CF_TOKEN" ]; then
    echo "探测到未设置 CF_TOKEN，正在自动屏蔽 Cloudflare 进程以保持环境纯净..."
    # 使用 sed 匹配到 [program:cloudflare] 标题开始，直到下一个 [ 标题或文件末尾，在行首加分号
    sed -i '/\[program:cloudflare\]/,/\[/ { /\[program:cloudflare\]/ s/^/;/; /^[ \t]*[^;\[]/ s/^/;/ }' "$CONF_FILE"
fi

# 4. 启动最终进程
exec "$@"
