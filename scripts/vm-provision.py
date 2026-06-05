#!/usr/bin/env python3
"""Автонастройка dev-VM через serial-консоль (unix-сокет QEMU).

Делает идемпотентно:
  1) сеть lan -> DHCP (гость получает 10.0.2.15 -> работают проброс портов и интернет);
  2) пароль root = root (для SSH/LuCI);
  3) ставит LuCI + uhttpd + rpcd (apk или opkg), включает сервисы.

Использование: python3 scripts/vm-provision.py [path-to-console.sock]
"""
import socket
import sys
import time

SOCK = sys.argv[1] if len(sys.argv) > 1 else ".dev-vm/console.sock"
PROMPT = "MBP> "


def main():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)
    buf = {"t": ""}

    def rd(t=0.5):
        s.settimeout(t)
        try:
            d = s.recv(65536)
            if d:
                buf["t"] += d.decode("utf-8", "replace")
                return True
        except socket.timeout:
            pass
        return False

    def expect(token, timeout=30):
        end = time.time() + timeout
        while time.time() < end:
            if token in buf["t"]:
                return True
            rd(0.5)
        return False

    def send(line):
        s.sendall((line + "\n").encode())
        time.sleep(0.2)

    def run(cmd, timeout=60):
        buf["t"] = ""
        send(cmd)
        ok = expect(PROMPT, timeout)
        if not ok:
            print(f"!! timeout on: {cmd}\n{buf['t'][-300:]}")
        return buf["t"]

    # активировать консоль и задать предсказуемый prompt
    buf["t"] = ""
    send("")
    time.sleep(0.5)
    send(f"export PS1='{PROMPT}'")
    if not expect(PROMPT, 20):
        print("!! не удалось получить shell-приглашение. Загрузилась ли VM?")
        sys.exit(1)
    print(">> консоль активна")

    print(">> 1/3 сеть -> DHCP")
    run("uci set network.lan.proto='dhcp'")
    run("uci -q delete network.lan.ipaddr; uci -q delete network.lan.netmask; "
        "uci -q delete network.lan.ip6assign; echo ok")
    run("uci commit network")
    run("/etc/init.d/network restart", 30)
    time.sleep(8)
    out = run("ip -4 addr show br-lan | grep -o 'inet [0-9.]*' || echo NO_IP")
    if "10.0.2" not in out:
        print("!! гость не получил 10.0.2.x — проброс может не работать\n", out[-200:])

    print(">> 2/3 пароль root=root")
    buf["t"] = ""
    send("passwd root")
    time.sleep(1)
    send("root")
    time.sleep(1)
    send("root")
    time.sleep(1)
    expect(PROMPT, 15)

    print(">> 3/3 установка LuCI (может занять пару минут)")
    pm = "apk" if "apk" in run("command -v apk >/dev/null && echo apk || echo opkg") else "opkg"
    ok = False
    for attempt in (1, 2):
        if pm == "apk":
            run("apk update", 300)
            run("apk add luci uhttpd uhttpd-mod-ubus rpcd", 600)
        else:
            run("opkg update", 300)
            run("opkg install luci uhttpd uhttpd-mod-ubus rpcd", 600)
        if "HAVE" in run("which uhttpd >/dev/null 2>&1 && echo HAVE || echo MISS"):
            ok = True
            break
        print(f"   uhttpd не встал (попытка {attempt}), повтор...")
    if not ok:
        print("!! LuCI/uhttpd установить не удалось — проверь интернет в VM и повтори make dev-provision")

    run("/etc/init.d/rpcd enable; /etc/init.d/rpcd restart; "
        "/etc/init.d/uhttpd enable; /etc/init.d/uhttpd restart; "
        "/etc/init.d/dropbear restart; echo SVC_DONE", 40)

    s.close()
    if ok:
        print(">> provision готов. LuCI: http://localhost:8080 (root/root), "
              "SSH: make dev-ssh (root/root)")
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
