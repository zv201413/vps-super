#!/usr/bin/env python3
"""etaddr.py —— 自测本节点的 UDP 出口地址 (公网 IP + 映射端口 + 映射类型)

为什么需要
----------
打洞要用到两个「自己也不知道」的事实:
  1) 本节点的公网出口 IP —— 用于 --mapped-listeners 告诉对端来哪里找我,
     也用于把 IP 写进 EasyTier hostname 广播给对端 (对端据此扫射我)
  2) 该 UDP 端口在 NAT 上的映射端口, 以及映射是否与目标无关

为什么用 STUN 而不是 curl ifconfig.me
------------------------------------
· curl 走 TCP, 拿到的是 TCP 出口 IP; 打洞要的是 **UDP** 出口 IP。
  多数平台两者相同, 但这是巧合不是保证, 不该赌。
· curl 拿不到端口映射信息, 只能假设「映射端口 == 本地端口」。
  该假设在 Cone NAT 下成立, 在 Symmetric NAT 下必然错。
STUN 从**待用的那个端口**发出去问, 拿回来的正是这条链路真实的映射。

映射类型判定
------------
用同一个 socket 问两台不同的 STUN 服务器:
  · 两次回答的 IP 与端口都相同 → 映射与目标无关 (Cone), 端口可以公布给任意对端
  · 端口不同                   → Symmetric, 映射随目标变化, 端口对第三方无意义,
                                 此时只有 IP 可信 —— 这也正是必须靠全端口扫射的场合
输出: 单行 "<IP> <端口> <cone|symmetric>"; 全部失败则无输出且退出码 1。
STUN 全挂时退化到 HTTP 取 IP, 端口按本地端口填, 类型标 unknown。

用法: etaddr.py <本地UDP端口>
"""
import os
import socket
import struct
import sys
import urllib.request

STUN_SERVERS = [
    ("stun.l.google.com", 19302),
    ("stun.cloudflare.com", 3478),
    ("stun.miwifi.com", 3478),
    ("stun.qq.com", 3478),
]
HTTP_SERVICES = [
    "https://api.ipify.org",
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
]
MAGIC = 0x2112A442
TIMEOUT = 1.5


def parse_response(data, tid):
    if len(data) < 20:
        return None
    mtype, mlen, cookie, rtid = struct.unpack(">HHI12s", data[:20])
    if mtype != 0x0101 or rtid != tid:        # 只认 Binding Success 且事务号对得上
        return None
    body = data[20:20 + mlen]
    i = 0
    while i + 4 <= len(body):
        atype, alen = struct.unpack(">HH", body[i:i + 4])
        val = body[i + 4:i + 4 + alen]
        i += 4 + alen + ((4 - alen % 4) % 4)  # 属性按 4 字节对齐
        if atype in (0x0020, 0x0001) and len(val) >= 8 and val[1] == 0x01:
            port = struct.unpack(">H", val[2:4])[0]
            raw = val[4:8]
            if atype == 0x0020:               # XOR-MAPPED-ADDRESS 要异或掉 magic
                port ^= MAGIC >> 16
                raw = bytes(a ^ b for a, b in zip(raw, struct.pack(">I", MAGIC)))
            return socket.inet_ntoa(raw), port
    return None


def ask(sock, host, port):
    try:
        addr = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_DGRAM)[0][4]
    except OSError:
        return None
    tid = os.urandom(12)
    req = struct.pack(">HHI12s", 0x0001, 0, MAGIC, tid)
    for _ in range(2):                        # UDP 会丢, 单服务器重试一次
        try:
            sock.sendto(req, addr)
            data, _src = sock.recvfrom(2048)
        except OSError:
            continue
        got = parse_response(data, tid)
        if got:
            return got
    return None


def by_stun(local_port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(TIMEOUT)
    # 故意**不设** SO_REUSEADDR: UDP 上它会允许与已在监听的 easytier 共绑同一端口,
    # 结果是入站包被内核派给我们这个 socket, 把 easytier 的流量吃掉;
    # 且此时报出的映射也不是 easytier 那条。宁可 bind 失败退到临时端口。
    exact = True
    try:
        s.bind(("0.0.0.0", local_port))       # 必须绑目标端口: 换端口问出来的映射不是这条
    except OSError:
        s.bind(("0.0.0.0", 0))                # 端口已被占 (如 easytier 已在跑) → 只有 IP 可信
        exact = False
    answers = []
    try:
        for host, port in STUN_SERVERS:
            got = ask(s, host, port)
            if got:
                answers.append(got)
            if len(answers) >= 2:
                break
    finally:
        s.close()
    if not answers:
        return None
    ip, port = answers[0]
    if not exact:
        return ip, local_port, "unknown"      # 映射端口属于临时端口, 不能当成目标端口的
    if len(answers) < 2:
        return ip, port, "unknown"            # 只有一家答, 无从判断映射是否随目标变化
    ip2, port2 = answers[1]
    if ip2 != ip:
        return ip, port, "symmetric"          # 连出口 IP 都不一致, 更别提端口
    return ip, port, "cone" if port2 == port else "symmetric"


def by_http(local_port):
    for url in HTTP_SERVICES:
        try:
            with urllib.request.urlopen(url, timeout=3) as r:
                ip = r.read(64).decode().strip()
        except Exception:
            continue
        try:
            socket.inet_aton(ip)
        except OSError:
            continue
        return ip, local_port, "unknown"
    return None


def main():
    if len(sys.argv) < 2 or not sys.argv[1].isdigit():
        sys.exit("用法: etaddr.py <本地UDP端口>")
    local_port = int(sys.argv[1])
    got = by_stun(local_port) or by_http(local_port)
    if not got:
        sys.exit(1)
    print("%s %d %s" % got)


if __name__ == "__main__":
    main()
