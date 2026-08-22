#!/usr/bin/env python3
"""sweep.py —— UDP 全端口预授权扫射

为什么需要它
------------
两端 NAT 类型决定了 EasyTier 自己打不通这条洞:
  · 一端 Symmetric  —— 映射端口随目标变化, 它从 STUN 学到的公网端口
    对第三方有效, 对我们这条链路无效, 所以控制通道里交换的端点是错的
  · 一端 PortRestricted —— 入站要求先有出站到**精确的** <对端IP:对端端口>,
    而那个端口正是上面拿不到的值

破法: PortRestricted 侧朝对端 1024-65535 每个端口各发一包, 把所有可能的
映射端口一次性授权掉。实测 64512 个端口 0.9 秒扫完, 代价极低。

关键机制: NAT 放行条目记的是 <内部IP:内部端口 → 外部IP:外部端口> 四元组,
**与哪个进程占用该端口无关**。所以可以接力 ——
本脚本绑 PORT 扫射完立即退出, EasyTier 随后绑同一个 PORT,
它收发用的四元组正好落在已有条目上, 对端的包就能进来了。
故扫完必须立刻退出, 不留 sleep: 空窗越短, 衔接越稳。

用法: sweep.py <对端公网IP> <本地端口> [轮数]
"""
import socket
import struct
import sys
import time

LO, HI = 1024, 65535


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__.strip().splitlines()[-1])
    peer = sys.argv[1]
    port = int(sys.argv[2])
    rounds = int(sys.argv[3]) if len(sys.argv) > 3 else 2

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("0.0.0.0", port))
    except OSError as e:
        # 端口还被 EasyTier 占着 —— 调用方应先停掉它再来
        sys.exit(f"bind {port} 失败: {e}")

    for r in range(rounds):
        t0 = time.monotonic()
        n = 0
        for p in range(LO, HI + 1):
            try:
                s.sendto(b"PA" + struct.pack(">H", p), (peer, p))
                n += 1
            except OSError:
                pass                    # 单个端口发失败无所谓, 继续扫
        print(f"  第{r + 1} 轮: {n} 端口 / {time.monotonic() - t0:.2f}s", flush=True)

    s.close()
    print(f"  已释放 {port}, 立即交给 EasyTier", flush=True)


if __name__ == "__main__":
    main()
