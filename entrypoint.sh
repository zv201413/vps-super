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

# --- 4. TTYD 配置解析 ---
# 格式: TTYD_P1=端口:用户名:密码 (端口默认7681，密码可省略)
# 向后兼容: TTYD_P1 未设置时使用 TTYD/TTYD_PORT

parse_ttyd() {
    local var="$1"
    local default_port="$2"
    local result
    
    if [ -n "$(eval echo \${$var})" ]; then
        # 有设置 TTYD_P1 或 TTYD_P2
        local val=$(eval echo \${$var})
        local port=$(echo "$val" | cut -d: -f1)
        local user=$(echo "$val" | cut -d: -f2)
        local pass=$(echo "$val" | cut -d: -f3)
        
        if [ -n "$port" ] && [ "$port" != "$val" ]; then
            # 有端口格式: 端口:user:pass
            result="PORT:$port"
            [ -n "$user" ] && [ -n "$pass" ] && result="$result AUTH:-c $user:$pass"
        elif [ -n "$port" ]; then
            # 只有端口: 端口
            result="PORT:$port"
        else
            result="PORT:$default_port"
        fi
    else
        # 回退到旧变量
        if [ "$var" = "TTYD_P1" ]; then
            [ -n "$TTYD" ] && result="AUTH:-c $TTYD"
            result="${result:-PORT:$default_port}"
        else
            result="PORT:$default_port"
        fi
    fi
    echo "$result"
}

# 解析 TTYD_P1
if [ -n "$TTYD_P1" ]; then
    P1_PORT=$(echo "$TTYD_P1" | cut -d: -f1)
    P1_USER=$(echo "$TTYD_P1" | cut -d: -f2)
    P1_PASS=$(echo "$TTYD_P1" | cut -d: -f3)
    # 如果只有端口没有密码
    if [ -n "$P1_PORT" ] && [ "$P1_PORT" != "$TTYD_P1" ] && [ -z "$P1_USER" ]; then
        P1_PORT=$(echo "$TTYD_P1" | cut -d: -f1)
        P1_AUTH=""
    elif [ -n "$P1_USER" ] && [ -n "$P1_PASS" ]; then
        P1_AUTH="-c $P1_USER:$P1_PASS"
    else
        P1_AUTH=""
    fi
    # 检查端口是否为数字或空
    if ! echo "$P1_PORT" | grep -qE '^[0-9]+$'; then
        P1_PORT="7681"
    fi
else
    # 向后兼容旧变量
    P1_PORT=${TTYD_PORT:-7681}
    if [ -n "$TTYD" ]; then
        P1_AUTH="-c $TTYD"
    else
        P1_AUTH=""
    fi
fi

# 解析 TTYD_P2
if [ -n "$TTYD_P2" ]; then
    P2_PORT=$(echo "$TTYD_P2" | cut -d: -f1)
    P2_USER=$(echo "$TTYD_P2" | cut -d: -f2)
    P2_PASS=$(echo "$TTYD_P2" | cut -d: -f3)
    if [ -n "$P2_USER" ] && [ -n "$P2_PASS" ]; then
        P2_AUTH="-c $P2_USER:$P2_PASS"
    else
        P2_AUTH=""
    fi
    if ! echo "$P2_PORT" | grep -qE '^[0-9]+$'; then
        P2_PORT=""
        P2_AUTH=""
    fi
else
    P2_PORT=""
    P2_AUTH=""
fi

# 生成指纹
FINGERPRINT="USER:$USER_NAME|P1:$P1_PORT|P2:${P2_PORT:-none}|CF:${CF_TOKEN:-none}|KPAL:${KPAL:-none}|HYP2P:${HYP2P:-none}|RV:${HYP2P_RV:-public}|SBP2P:${SBP2P:-none}|ET:${ET:-none}|ETP:${ET_PEERS:-none}|ETM:${ET_MODE:-auto}|ETA:${ET_ARGS:-none}"

# --- 5. 保活脚本生成 ---
if [ -n "$KPAL" ]; then
    cat > /tmp/keepalive.sh <<'EOF'
#!/bin/bash
# 从环境读取 KPAL
if [ -z "$KPAL" ]; then
  echo "Error: KPAL environment variable is not set."
  exit 1
fi

# 解析 KPAL 环境变量: [RANGE]:[OFFSET]:URL
# 支持格式: 
# 1. 300:60:http://...
# 2. 300::http://... (offset 默认为 60)
# 3. :60:http://...  (range 默认为 300)
# 4. http://...      (range=300, offset=60)

if [[ "$KPAL" == *":"*":"* ]]; then
    # 含有两个或更多冒号
    range=$(echo "$KPAL" | cut -d: -f1)
    offset=$(echo "$KPAL" | cut -d: -f2)
    url=$(echo "$KPAL" | cut -d: -f3-)
elif [[ "$KPAL" == *":"* ]]; then
    # 只有一个冒号，视为 RANGE:URL 或 :URL
    p1=$(echo "$KPAL" | cut -d: -f1)
    url=$(echo "$KPAL" | cut -d: -f2-)
    range="${p1:-300}"
    offset=60
else
    # 没有冒号，视为纯 URL
    url="$KPAL"
    range=300
    offset=60
fi

# 默认值处理
range=${range:-300}
offset=${offset:-60}

# 最终检查 URL 是否存在且合法 (以 http 开头)
if [[ ! "$url" =~ ^http ]]; then
  echo "❌ Error: URL is missing or invalid in KPAL: $KPAL"
  echo "💡 Hint: KPAL format should be RANGE:OFFSET:URL"
  exit 1
fi

echo "🚀 Keepalive started for $url (Range: $range, Offset: $offset)"

while true; do
  # 确保是大于 0 的数字，防止随机数报错
  if ! [[ "$range" =~ ^[0-9]+$ ]] || [ "$range" -lt 1 ]; then range=300; fi
  if ! [[ "$offset" =~ ^[0-9]+$ ]]; then offset=60; fi

  sleep_time=$((RANDOM % range + offset))
  sleep $sleep_time

  status=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
  
  # 记录日志
  echo "$(date '+%Y-%m-%d %H:%M:%S') [KPAL] range:$range offset:$offset sleep:$sleep_time URL:$url Status:$status" >> /tmp/keepalive.log
  tail -n 20 /tmp/keepalive.log > /tmp/keepalive.tmp && mv /tmp/keepalive.tmp /tmp/keepalive.log
done
EOF
    chmod +x /tmp/keepalive.sh
fi

BOOT_DIR="$TARGET_HOME/boot"
STATE_FILE="$BOOT_DIR/.config_state"
BOOT_CONF="$BOOT_DIR/supervisord.conf"
TEMPLATE="/usr/local/etc/supervisord.conf.template"

mkdir -p "$BOOT_DIR"

# === 确保 include 分片目录存在 (必须在指纹检测块外部) ===
mkdir -p /etc/supervisor/conf.d
mkdir -p "$TARGET_HOME/supervisor"
if [ "$USER_NAME" != "root" ]; then
    chown -R "$USER_NAME":"$USER_NAME" "$TARGET_HOME/supervisor"
fi
SYS_CONF_DIR="$BOOT_DIR/system.conf.d"
mkdir -p "$SYS_CONF_DIR"
# =========================================================

OLD_FINGERPRINT=$(cat "$STATE_FILE" 2>/dev/null || echo "")

if [ -f "$TARGET_HOME/init_env.sh" ]; then
	sh "$TARGET_HOME/init_env.sh"
fi

if [ ! -f "$BOOT_CONF" ] || [ "$FINGERPRINT" != "$OLD_FINGERPRINT" ] || [ "$FORCE_UPDATE" = "true" ]; then
	echo "🔄 检测到配置变更正在同步..."
	rm -f "$BOOT_CONF"
	cp "$TEMPLATE" "$BOOT_CONF"
	sed -i "s/{SSH_USER}/$USER_NAME/g" "$BOOT_CONF"
	sed -i "s|{TARGET_HOME}|$TARGET_HOME|g" "$BOOT_CONF"

	# 清空上一次动态生成的系统片段，防止配置残留
	rm -f "$SYS_CONF_DIR"/*.conf
	
	# 核心系统服务：直接拷贝
	cp /usr/local/etc/fragments/sshd.conf "$SYS_CONF_DIR/"
	
	# ttyd 基础服务：拷贝并替换占位符
	cp /usr/local/etc/fragments/ttyd.conf "$SYS_CONF_DIR/"
	sed -i "s/{TTYD_P1_PORT}/$P1_PORT/g" "$SYS_CONF_DIR/ttyd.conf"
	sed -i "s/{TTYD_P1_AUTH}/$P1_AUTH/g" "$SYS_CONF_DIR/ttyd.conf"

	if [ -n "$P2_PORT" ]; then
		cp /usr/local/etc/fragments/ttyd2.conf "$SYS_CONF_DIR/"
		sed -i "s/{TTYD_P2_PORT}/$P2_PORT/g" "$SYS_CONF_DIR/ttyd2.conf"
		sed -i "s/{TTYD_P2_AUTH}/$P2_AUTH/g" "$SYS_CONF_DIR/ttyd2.conf"
	fi

	if [ -n "$CF_TOKEN" ]; then
		cp /usr/local/etc/fragments/cloudflared.conf "$SYS_CONF_DIR/"
	fi

	if [ -n "$KPAL" ]; then
		cp /usr/local/etc/fragments/kpal.conf "$SYS_CONF_DIR/"
	fi
	
	KOMARI_CMD="${komari:-$KOMARI}"
	if [ -n "$KOMARI_CMD" ]; then
		cat > /tmp/komari-init.sh <<EOF
#!/bin/sh
echo "🚀 执行注入的初始化指令..."
$KOMARI_CMD
EOF
		chmod +x /tmp/komari-init.sh
		cp /usr/local/etc/fragments/komari.conf "$SYS_CONF_DIR/"
	fi

	echo "$FINGERPRINT" > "$STATE_FILE"
	[ -d "$TARGET_HOME" ] && chown -R "$USER_NAME":"$USER_NAME" "$BOOT_DIR"
else
	echo "😴 配置未变更直接启动"
fi

# --- 7. HYP2P: Hysteria2 P2P 打洞出站代理 ---
# 总开关  HYP2P=<auth>:<obfs>:<进程名>   (auth 为空=关闭; auth/obfs 不能含冒号)
# 牵线    HYP2P_RV 为空 -> 公共 realm.hy2.io + 自动生成并持久化 realm 名; 非空 -> 用你的 URI
# 持久化目录固定为 $TARGET_HOME/p2p (随现有挂载持久化)
if [ -n "$HYP2P" ]; then
    set +e   # P2P 初始化为 best-effort: 失败不应拖垮 sshd/ttyd 等其他服务
    HP_AUTH=$(printf '%s' "$HYP2P" | cut -d: -f1)
    HP_OBFS=$(printf '%s' "$HYP2P" | cut -d: -s -f2)
    HP_PROC=$(printf '%s' "$HYP2P" | cut -d: -s -f3); HP_PROC=${HP_PROC:-hy2}
    P2P_DIR="$TARGET_HOME/p2p"

    if [ -z "$HP_AUTH" ]; then
        echo "⚠️ HYP2P 已设置但第 1 段 auth 为空 → 跳过 P2P 代理"
    else
        mkdir -p "$P2P_DIR"

        # 1) 牵线服务器: 自建(HYP2P_RV) 或 公共回落(自动生成并持久化 realm 名)
        if [ -n "$HYP2P_RV" ]; then
            HP_RV="$HYP2P_RV"; HP_MODE="custom"
        else
            [ -f "$P2P_DIR/realm_name" ] || openssl rand -hex 6 > "$P2P_DIR/realm_name"
            HP_NAME=$(cat "$P2P_DIR/realm_name")
            HP_RV="realm://public@realm.hy2.io/$HP_NAME"; HP_MODE="public"
        fi

        # 2) hy2 监听器自签证书(持久化, 已存在则复用 → pinSHA256 稳定)
        if [ ! -f "$P2P_DIR/cert.pem" ]; then
            openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
                -keyout "$P2P_DIR/key.pem" -out "$P2P_DIR/cert.pem" \
                -days 3650 -nodes -subj "/CN=cloudflare.com" >/dev/null 2>&1
        fi
        HP_PIN=$(openssl x509 -in "$P2P_DIR/cert.pem" -noout -fingerprint -sha256 | sed 's/.*=//')
        printf '%s\n' "$HP_PIN" > "$P2P_DIR/cert_sha256"

        # 3) 生成 server config.yaml
        {
            echo "listen: $HP_RV"
            echo "tls:"
            echo "  cert: $P2P_DIR/cert.pem"
            echo "  key: $P2P_DIR/key.pem"
            echo "  alpn:"
            echo "    - h3"
            echo "auth:"
            echo "  type: password"
            echo "  password: \"$HP_AUTH\""
            if [ -n "$HP_OBFS" ]; then
                echo "obfs:"
                echo "  type: salamander"
                echo "  salamander:"
                echo "    password: \"$HP_OBFS\""
            fi
        } > "$P2P_DIR/config.yaml"

        # 4) 生成本地 client 示例配置(部署后 cat 出来直接用)
        {
            echo "server: $HP_RV"
            echo "auth: \"$HP_AUTH\""
            echo "tls:"
            echo "  insecure: true"
            echo "  pinSHA256: $HP_PIN"
            echo "  alpn:"
            echo "    - h3"
            if [ -n "$HP_OBFS" ]; then
                echo "obfs:"
                echo "  type: salamander"
                echo "  salamander:"
                echo "    password: \"$HP_OBFS\""
            fi
            echo "socks5:"
            echo "  listen: 127.0.0.1:1080"
            echo "http:"
            echo "  listen: 127.0.0.1:8080"
        } > "$P2P_DIR/client.example.yaml"

        # 5) 进程伪装: 复制二进制为自定义名 (ps/sctl/日志均显示该名)
        cp -f /usr/local/bin/hysteria "/usr/local/bin/$HP_PROC"

        # 6) 渲染 supervisord 片段 (program 名 = 进程名)
        sed -e "s/{HP_PROC}/$HP_PROC/g" -e "s#{P2P_DIR}#$P2P_DIR#g" \
            /usr/local/etc/fragments/hy2.conf > "$SYS_CONF_DIR/$HP_PROC.conf"

        # 7) 自建 realm:// 指向裸 IP 的踩坑提示(多半没配 TLS)
        case "$HP_RV" in
            realm://*)
                HP_HOST=$(printf '%s' "$HP_RV" | sed -E 's#^realm://[^@]*@([^/:]+).*#\1#')
                if printf '%s' "$HP_HOST" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                    echo "💡 HYP2P_RV=realm:// 指向裸 IP ($HP_HOST): 牵线服务器若未配 TLS 请改用 realm+http://"
                fi ;;
        esac

        [ "$USER_NAME" != "root" ] && chown -R "$USER_NAME":"$USER_NAME" "$P2P_DIR"

        echo "========================================"
        echo " HYP2P server ready  (mode: $HP_MODE, proc: $HP_PROC)"
        [ "$HP_MODE" = "public" ] && echo " Realm name : $HP_NAME"
        echo " Server URI : $HP_RV"
        echo " pinSHA256  : $HP_PIN"
        echo " Client cfg : cat $P2P_DIR/client.example.yaml"
        echo "========================================"
    fi
    set -e
fi

# --- 8. SBP2P: Sing-box Hysteria2 P2P 打洞出站代理 ---
# 格式: SBP2P=<auth>:<obfs>:<进程名>   (auth 为空=关闭, obfs 可空)
# 牵线: SBP2P_RV 为空 -> 公共 realm.hy2.io + 自动生成 realm 名; 非空 -> 自定义 URI
if [ -n "$SBP2P" ]; then
    set +e
    SB_AUTH=$(printf '%s' "$SBP2P" | cut -d: -f1)
    SB_OBFS=$(printf '%s' "$SBP2P" | cut -d: -s -f2)
    SB_PROC=$(printf '%s' "$SBP2P" | cut -d: -s -f3); SB_PROC=${SB_PROC:-sb}
    P2P_DIR="$TARGET_HOME/p2p"
    SB_PORT=8343

    if [ -z "$SB_AUTH" ]; then
        echo "⚠️ SBP2P 已设置但第 1 段 auth 为空 → 跳过"
    else
        mkdir -p "$P2P_DIR"

        # 1) 牵线服务器
        if [ -n "$SBP2P_RV" ]; then
            SB_RV="$SBP2P_RV"; SB_MODE="custom"
        else
            [ -f "$P2P_DIR/sb_realm_name" ] || openssl rand -hex 6 > "$P2P_DIR/sb_realm_name"
            SB_NAME=$(cat "$P2P_DIR/sb_realm_name")
            SB_RV="https://realm.hy2.io"; SB_MODE="public"
        fi

        # 2) TLS 证书 (复用或生成)
        if [ ! -f "$P2P_DIR/cert.pem" ]; then
            openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
                -keyout "$P2P_DIR/key.pem" -out "$P2P_DIR/cert.pem" \
                -days 3650 -nodes -subj "/CN=cloudflare.com" >/dev/null 2>&1
        fi
        SB_PIN=$(openssl x509 -in "$P2P_DIR/cert.pem" -noout -fingerprint -sha256 | sed 's/.*=//')
        printf '%s\n' "$SB_PIN" > "$P2P_DIR/sb_cert_sha256"

        # 3) 生成 sing-box server JSON 配置
        # 拆分为条件前/条件后两部分，obfs 可选中插
        > "$P2P_DIR/sb-config.json"
        printf '{"log":{"level":"error","timestamp":true},"inbounds":[{"type":"hysteria2","tag":"sb-hy2-in","listen":"0.0.0.0","listen_port":%s,"users":[{"password":"%s"}],' "$SB_PORT" "$SB_AUTH" >> "$P2P_DIR/sb-config.json"

        if [ -n "$SB_OBFS" ]; then
            printf '"obfs":{"type":"salamander","password":"%s"},' "$SB_OBFS" >> "$P2P_DIR/sb-config.json"
        fi

        printf '"realm":{"server_url":"%s","token":"public","realm_id":"%s","stun_servers":["turn.cloudflare.com:3478"]},"tls":{"enabled":true,"certificate_path":"%s","key_path":"%s","alpn":["h3"]}}],"outbounds":[{"type":"direct","tag":"direct"}]}' \
            "$SB_RV" "$SB_NAME" "$P2P_DIR/cert.pem" "$P2P_DIR/key.pem" >> "$P2P_DIR/sb-config.json"

        # 4) 生成 sing-box 客户端示例配置（极简版 SOCKS5 + HTTP）
        > "$P2P_DIR/sb-client.json"
        printf '{"log":{"level":"info","timestamp":true},"inbounds":[{"type":"socks","tag":"socks-in","listen":"127.0.0.1","listen_port":1080},{"type":"http","tag":"http-in","listen":"127.0.0.1","listen_port":8080}],"outbounds":[{"type":"hysteria2","tag":"p2p-out","password":"%s"' \
            "$SB_AUTH" >> "$P2P_DIR/sb-client.json"

        if [ -n "$SB_OBFS" ]; then
            printf ',"obfs":{"type":"salamander","password":"%s"}' "$SB_OBFS" >> "$P2P_DIR/sb-client.json"
        fi

        printf ',"tls":{"enabled":true,"server_name":"cloudflare.com","insecure":true,"alpn":["h3"]},"realm":{"server_url":"%s","token":"public","realm_id":"%s","stun_servers":["turn.cloudflare.com:3478"]}}]}' \
            "$SB_RV" "$SB_NAME" >> "$P2P_DIR/sb-client.json"

        # 5) 进程伪装: 复制二进制
        cp -f /usr/local/bin/sing-box "/usr/local/bin/$SB_PROC"

        # 6) 渲染 supervisord 片段
        sed -e "s/{SB_PROC}/$SB_PROC/g" -e "s#{P2P_DIR}#$P2P_DIR#g" \
            /usr/local/etc/fragments/sb.conf > "$SYS_CONF_DIR/$SB_PROC.conf"

        [ "$USER_NAME" != "root" ] && chown -R "$USER_NAME":"$USER_NAME" "$P2P_DIR"

        echo "========================================"
        echo " SBP2P server ready  (mode: $SB_MODE, proc: $SB_PROC)"
        [ "$SB_MODE" = "public" ] && echo " Realm name : $SB_NAME"
        echo " Server URL : $SB_RV"
        echo " pinSHA256  : $SB_PIN"
        echo " Server cfg : cat $P2P_DIR/sb-config.json"
        echo " Client cfg : cat $P2P_DIR/sb-client.json"
        echo "========================================"
    fi
    set -e
fi

# --- 9. ET: EasyTier 异地组网 ---
# 格式: ET=<监听端口>:<网络名>:<密钥>:<虚拟IP>
#   监听端口 : udp/tcp 用该端口, ws 用 +1, wss 用 +2 (默认 11010/11011/11012)
#              UDP 用于打洞直连, TCP/WS/WSS 在 UDP 被封时兜底
#   网络名   : 必填, 同一组网的所有节点必须一致
#   密钥     : 必填, 同一组网的所有节点必须一致
#   虚拟IP   : 可空, 留空则 --dhcp 自动分配 (从 10.0.0.1 起)
#   注意: 前四段用冒号分隔, 故网络名与密钥不能含冒号
# 对端节点: ET_PEERS="udp://主机:11010,tcp://主机:11010,ws://主机:11011"
#           同一主机写多种协议即为兜底链: UDP 打不通自动落到 TCP, 再落到 WS
# 其他: ET_MODE=auto|tun|notun (默认 auto, 自动探测 TUN 可用性)
#       ET_ARGS=追加的原生 easytier-core 参数 (逃生阀, 勿重复上面已设的参数)
if [ -n "$ET" ]; then
    set +e   # 组网初始化为 best-effort: 失败不应拖垮 sshd/ttyd 等其他服务
    ET_PORT=$(printf '%s' "$ET" | cut -d: -f1)
    ET_NET=$(printf '%s' "$ET" | cut -d: -s -f2)
    ET_SEC=$(printf '%s' "$ET" | cut -d: -s -f3)
    ET_VIP=$(printf '%s' "$ET" | cut -d: -s -f4)

    echo "$ET_PORT" | grep -qE '^[0-9]+$' || ET_PORT=11010

    if [ -z "$ET_NET" ] || [ -z "$ET_SEC" ]; then
        echo "⚠️ ET 已设置但网络名或密钥为空 → 跳过异地组网"
        echo "   正确格式: ET=<监听端口>:<网络名>:<密钥>:<虚拟IP>  (虚拟IP 可省略)"
    else
        # 1) TUN 可用性探测: 设备节点 + NET_ADMIN 能力
        #    只看 /dev/net/tun 存在是不够的 —— 缺 NET_ADMIN 时 TUNSETIFF 仍会失败,
        #    而绝大多数免费 PaaS 恰好是「节点在、能力无」, 故必须查 CapEff 第 12 位
        et_tun_ok() {
            if [ ! -c /dev/net/tun ]; then
                mkdir -p /dev/net 2>/dev/null
                mknod /dev/net/tun c 10 200 2>/dev/null
                chmod 600 /dev/net/tun 2>/dev/null
            fi
            [ -c /dev/net/tun ] || return 1
            _cap=$(grep -m1 '^CapEff:' /proc/self/status 2>/dev/null | tr -d '\t ' | cut -d: -f2)
            [ -n "$_cap" ] || return 1
            [ "$(( (0x$_cap >> 12) & 1 ))" = "1" ] || return 1
            return 0
        }

        case "${ET_MODE:-auto}" in
            tun)   ET_USE_TUN=1 ;;
            notun) ET_USE_TUN=0 ;;
            *)     if et_tun_ok; then ET_USE_TUN=1; else ET_USE_TUN=0; fi ;;
        esac

        if [ "$ET_USE_TUN" = "1" ]; then
            ET_TUN_ARGS=""
            ET_TUN_DESC="TUN 模式 (完整三层互通)"
        else
            # 无 TUN: 靠 smoltcp 用户态栈, 远端仍可访问本容器服务
            ET_TUN_ARGS="--no-tun --use-smoltcp"
            ET_TUN_DESC="无 TUN 模式 (smoltcp 用户态栈)"
        fi

        # 2) 虚拟 IP: 显式指定优先, 否则 dhcp 自动分配
        if [ -n "$ET_VIP" ]; then
            ET_IP_ARG="-i $ET_VIP"
        else
            ET_IP_ARG="--dhcp"
        fi

        # 3) 监听器: 四协议全开, 让对端可用任意协议接入本节点
        ET_WS_PORT=$((ET_PORT + 1))
        ET_WSS_PORT=$((ET_PORT + 2))
        ET_LISTEN_ARGS="-l udp://0.0.0.0:$ET_PORT -l tcp://0.0.0.0:$ET_PORT"
        ET_LISTEN_ARGS="$ET_LISTEN_ARGS -l ws://0.0.0.0:$ET_WS_PORT -l wss://0.0.0.0:$ET_WSS_PORT"

        # 4) 对端节点: 逗号或空格分隔都接受
        #    (EasyTier 原生 ET_PEERS 只认逗号, 空格会静默解析成 0 条, 这里放宽并显式转成 -p)
        ET_PEER_ARGS=""
        ET_PEER_N=0
        if [ -n "$ET_PEERS" ]; then
            for _u in $(printf '%s' "$ET_PEERS" | tr ',' ' '); do
                ET_PEER_ARGS="$ET_PEER_ARGS -p $_u"
                ET_PEER_N=$((ET_PEER_N + 1))
            done
        fi

        # 5) 生成启动包装脚本
        #    走包装脚本而非 sed 渲染模板: peer URI 含 / 与可能的 &, 直接 sed 替换要多层转义
        ET_CMD="/usr/local/bin/easytier-core --network-name '$ET_NET' --network-secret '$ET_SEC'"
        ET_CMD="$ET_CMD $ET_IP_ARG $ET_LISTEN_ARGS $ET_PEER_ARGS $ET_TUN_ARGS"
        ET_CMD="$ET_CMD --rpc-portal 127.0.0.1:15888 --console-log-level info"
        [ -n "$ET_ARGS" ] && ET_CMD="$ET_CMD $ET_ARGS"

        {
            echo '#!/bin/sh'
            echo '# 由 entrypoint.sh 自动生成, 每次配置变更时重写, 请勿手改'
            echo "exec $ET_CMD"
        } > /usr/local/bin/easytier-run.sh
        chmod +x /usr/local/bin/easytier-run.sh

        # 6) 投放 supervisord 片段
        cp /usr/local/etc/fragments/easytier.conf "$SYS_CONF_DIR/"

        echo "========================================"
        echo " EasyTier 异地组网已启用"
        echo " 网络名     : $ET_NET"
        echo " 运行模式   : $ET_TUN_DESC"
        echo " 本节点 IP  : ${ET_VIP:-dhcp 自动分配}"
        echo " 监听端口   : udp/tcp $ET_PORT | ws $ET_WS_PORT | wss $ET_WSS_PORT"
        if [ "$ET_PEER_N" -gt 0 ]; then
            echo " 对端节点   : $ET_PEER_N 个"
        else
            echo " 对端节点   : 未设置 ET_PEERS → 仅能发现同局域网节点, 异地组网需填"
        fi
        echo " 查看状态   : easytier-cli peer / easytier-cli route"
        echo " 运行日志   : tail -f /var/log/easytier.err.log"
        echo "========================================"
    fi
    set -e
fi

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
