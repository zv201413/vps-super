#!/bin/sh
# punchd.sh —— UDP 打洞守护: 让 EasyTier 的 UDP 隧道自愈
#
# 背景: 为什么 EasyTier 自己打不通
# --------------------------------
# 当两端 NAT 是 Symmetric ↔ PortRestricted 时:
#   · Symmetric 侧从 STUN 学到的公网端口只对 STUN 服务器有效 (映射端口随目标变化),
#     所以它在控制通道里告诉对端的端点是错的
#   · PortRestricted 侧入站要求先有出站到**精确的** <对端IP:对端端口>,
#     而那个端口正是上面拿不到的值
# 另外 EasyTier 只对「仅能经中继到达」的 peer 触发打洞, 而 TCP 直连一旦建立
# 就已算 p2p, 于是它根本不会去打洞 —— 这也是必须外挂本守护的原因。
#
# 做法: 授权接力
# --------------
# 周期检查隧道类型, 缺 UDP 就做一次「授权接力」:
#   停 EasyTier → 用同一个端口全端口扫射对端 → 起 EasyTier
# 扫射留下的 NAT 放行条目记的是四元组, **与哪个进程占用该端口无关**,
# 所以 EasyTier 起来后正好落在条目上, 一收到对端包就学到其真实映射端点,
# 之后双向流量自己保活, 不必再扫。
# 代价是每次接力 EasyTier 断几秒, 故只在缺 UDP 时才动, 并带退避。
#
# 为什么需要 auto 模式 (2026-08-23 实测教训)
# ------------------------------------------
# 扫射必须知道对端的公网出口 IP。而 PaaS 容器每次重启都可能换出口 IP
# —— 实测 SAP CF 重启后 20.195.24.178 → 52.139.216.172 (换了 Diego cell)。
# 把对端 IP 写死在 PUNCH 里, 于是「重启一次就永久打不通」, 表现为打洞时好时坏。
# EasyTier 的 peer 列表里**没有**对端公网端点字段 (peer/route 两个子命令都没有),
# 所以只能另开一条带内通道: 每个节点启动时自测出口 IP, 写进自己的 EasyTier
# hostname 后缀 `-ip-a-b-c-d` 广播出去; 本守护从 peer 列表里把它读回来。
# 这条通道免新端口、免凭据、免额外进程 —— TCP 兜底链一通它就通。
#
# 配置
# ----
#   PUNCH=auto[:<端口>[:<间隔秒>]]        对端 IP 从 peer hostname 自动学 (推荐)
#   PUNCH=<对端公网IP>[:<端口>[:<间隔>]]  写死对端 IP (对端不会换 IP 时才用)
#   端口留空 → 取 PUNCH_PORT (entrypoint 传入的 ET 监听端口)
#   间隔留空 → 60 秒
SUP="supervisorctl -s unix:///tmp/supervisor.sock"
SWEEP=/usr/local/bin/sweep.py
CLI=/usr/local/bin/easytier-cli          # 不在 PATH 上, 必须写绝对路径
MAX_TARGETS=4                            # 一次接力最多扫几个 IP, 免得停机太久

F1=$(printf '%s' "$PUNCH" | cut -d: -f1)
PORT=$(printf '%s' "$PUNCH" | cut -d: -s -f2)
INTERVAL=$(printf '%s' "$PUNCH" | cut -d: -s -f3)
echo "$PORT" | grep -qE '^[0-9]+$' || PORT=${PUNCH_PORT:-11010}
echo "$INTERVAL" | grep -qE '^[0-9]+$' || INTERVAL=60

case "$F1" in
    auto|1|yes|on|true) MODE=auto;   STATIC_IP="" ;;
    "")                 MODE=auto;   STATIC_IP="" ;;
    *)                  MODE=static; STATIC_IP="$F1" ;;
esac

log() { echo "[punchd $(date '+%H:%M:%S')] $*"; }

# 对端扫描: 每行输出 "<tunnel_proto>\t<对端公布的出口IP 或 ->"
#
# 走 JSON 而不是刮表格, 三点实测依据 (easytier 2.6.4):
#   · `-o json` 是**全局**选项, 必须放在子命令前面, 写成 `peer -o json` 会报错
#   · 字段名 tunnel_proto; 自身那行的 cost 是 "Local", tunnel_proto 是 "-"
#   · 表格列与 JSON 字段并不一一对应 (JSON 多一个 id), 按列号取值既脆又易错
# 守护长期无人值守跑, 判据一错就会永远认为「缺 UDP」而无限接力。
PEERS_PY='
import json, re, sys
try:
    rows = json.load(sys.stdin)
except Exception:
    sys.exit(0)                          # RPC 不通/输出不是 JSON, 一律当作没拿到
pat = re.compile(r"-ip-(\d{1,3})-(\d{1,3})-(\d{1,3})-(\d{1,3})$")
for r in rows:
    if r.get("cost") == "Local":
        continue
    t = (r.get("tunnel_proto") or "").strip()
    if not t or t == "-":
        continue
    ip = "-"
    m = pat.search(r.get("hostname") or "")
    if m and all(0 <= int(x) <= 255 for x in m.groups()):
        ip = ".".join(m.groups())
    print("%s\t%s" % (t, ip))
'
scan() {
    "$CLI" -o json -p 127.0.0.1:15888 peer 2>/dev/null | python3 -c "$PEERS_PY"
}

if [ "$MODE" = static ]; then
    log "启动: 对端 $STATIC_IP (写死), 本地端口 $PORT, 每 ${INTERVAL}s 检查"
else
    log "启动: 对端 IP 自动学 (peer hostname 后缀), 本地端口 $PORT, 每 ${INTERVAL}s 检查"
fi

fails=0
while :; do
    rows=$(scan)

    if [ -z "$rows" ]; then
        # 一个对端都没有 = 连 TCP 都没通, 对端多半不在线。
        # 此时扫射是白费 (也学不到对端 IP), 等它上线再说。
        log "尚无对端 (对端不在线或 EasyTier 未就绪), 等待"
        fails=0
        sleep "$INTERVAL"
        continue
    fi

    # 缺 UDP 的对端行 (大小写无关的子串判断, 不去赌 tunnel_proto 的具体拼法)
    lack=$(printf '%s\n' "$rows" | awk -F'\t' 'tolower($1) !~ /udp/')
    if [ -z "$lack" ]; then
        [ "$fails" -gt 0 ] && log "UDP 已恢复 (tunnel=$(printf '%s' "$rows" | awk -F'\t' '{print $1}' | tr '\n' ' '))"
        fails=0
        sleep "$INTERVAL"
        continue
    fi

    # 选扫射目标
    if [ "$MODE" = static ]; then
        targets="$STATIC_IP"
    else
        targets=$(printf '%s\n' "$lack" | awk -F'\t' '$2 != "-" {print $2}' | sort -u)
        if [ -z "$targets" ]; then
            # 对端在线但没公布出口 IP: 它跑的是旧镜像, 或它那侧关掉了 ET_ANNOUNCE_IP
            log "对端未公布出口 IP (hostname 无 -ip- 后缀) → 无法自动扫射;"
            log "  请把对端也升级到带 ET_ANNOUNCE_IP 的镜像, 或改用 PUNCH=<对端IP>"
            fails=0
            sleep "$INTERVAL"
            continue
        fi
        n=$(printf '%s\n' "$targets" | wc -l)
        if [ "$n" -gt "$MAX_TARGETS" ]; then
            log "缺 UDP 的对端有 $n 个, 本轮只扫前 $MAX_TARGETS 个 (其余下轮)"
            targets=$(printf '%s\n' "$targets" | head -n "$MAX_TARGETS")
        fi
    fi

    fails=$((fails + 1))
    log "缺 UDP (tunnel=$(printf '%s' "$lack" | awk -F'\t' '{print $1}' | tr '\n' ' ')), 第 ${fails} 次授权接力 → $(printf '%s' "$targets" | tr '\n' ' ')"

    $SUP stop easytier >/dev/null 2>&1
    sleep 1                              # 等端口真正释放, 否则 sweep 会 bind 失败
    for ip in $targets; do
        python3 "$SWEEP" "$ip" "$PORT" 2 2>&1 | sed "s/^/[punchd $ip] /"
    done
    $SUP start easytier >/dev/null 2>&1
    log "接力完成, EasyTier 已重启"

    # 退避: 连续失败说明对端侧可能也没配好, 别一直重启把好用的 TCP 通道也拖垮
    if [ "$fails" -ge 3 ]; then
        back=$((INTERVAL * 5))
        log "连续 ${fails} 次未成, 退避 ${back}s (期间 TCP 通道照常可用)"
        sleep "$back"
    else
        sleep 25                         # 给 EasyTier 时间完成握手再复查
    fi
done
