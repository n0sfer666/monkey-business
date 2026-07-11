# Installing monkey-business on a NanoPi R2S

**English** | [Русский](install-nanopi.ru.md)

A detailed, step-by-step walkthrough for getting the VPN client running on a **NanoPi R2S**
(RK3328, aarch64) that **already runs ImmortalWrt/OpenWrt** and is reachable over SSH.

If you still need to flash ImmortalWrt to the SD card and bring up the network, do that first
(see the ImmortalWrt docs for `rockchip/armv8` / NanoPi R2S) and come back here.

> Throughout, `<router-ip>` is your R2S LAN address (the ImmortalWrt/OpenWrt default is usually
> `192.168.1.1`), and the
> commands prefixed with `#` run **on the router** (via `ssh root@<router-ip>`), while the rest run
> on your dev machine in the repo checkout.

---

## 0. Prerequisites & sanity checks

On the router, confirm the platform and free space — geo databases need ~30 MB and Xray ~25 MB:

```sh
# uname -m            # expect: aarch64
# cat /etc/openwrt_release | grep -E 'ARCH|RELEASE'
# df -h /             # need ~80–100 MB free for xray-core + geo .dat
# nft --version       # fw4/nftables present (modern ImmortalWrt has it)
```

If the overlay is tight, geo `.dat` are downloaded at runtime (not bundled), so the package itself
is small — but xray-core + the two `.dat` are the bulk of the footprint.

---

## 1. Install the runtime dependencies

The app needs these packages on the router:

| Package | Why |
|---------|-----|
| `xray-core` | the proxy engine |
| `kmod-nft-tproxy` | TPROXY support in nftables (fw4) |
| `rpcd-mod-ucode` | runs the ucode rpcd plugin |
| `ucode-mod-uci`, `ucode-mod-fs` | UCI + filesystem access from ucode |
| `curl` | subscription fetch (captures the `Subscription-Userinfo` traffic header) |

`scripts/deploy-vm.sh` installs these automatically (Section 2). To do it by hand:

```sh
# apk update
# apk add xray-core kmod-nft-tproxy rpcd-mod-ucode ucode-mod-uci ucode-mod-fs curl
```

(On older opkg-based builds use `opkg update && opkg install …`.)

---

## 2. Deploy the application files

**Recommended: `make deploy`.** From the repo checkout:

```sh
make deploy HOST=root@<router-ip>
```

`make deploy` is a thin wrapper (`scripts/deploy.sh`) around the dev deployer. It exists so a
push to real hardware is safe and one-line: it first runs the local checks
(`make lint check test-unit`) so you never ship broken code, then sets the device defaults
(SSH port 22) and hands off to `scripts/deploy-vm.sh` for the actual copy. Re-running it is an
**update** — files are refreshed while your `/etc/config/monkey-business` (servers, selection,
settings) is kept intact. Optional env overrides (prefix the command, e.g.
`MB_PASS=secret make deploy HOST=…`): `MB_PORT` (SSH port), `MB_PASS` (root password if you don't
use a key), `MB_SKIP_CHECKS=1` (skip the pre-flight checks when Docker isn't available).

Under the hood it calls `scripts/deploy-vm.sh`, which you can also run directly for finer control
(this is what `make deploy` ends up executing):

```sh
MB_VM_SSH_HOST=root@<router-ip> \
MB_VM_SSH_PORT=22 \
MB_VM_SSH_PASS=<root-password> \
  sh scripts/deploy-vm.sh
```

```nu
# nushell
with-env {
  MB_VM_SSH_HOST: "root@<router-ip>",
  MB_VM_SSH_PORT: "22",
  MB_VM_SSH_PASS: "<root-password>"
} { sh scripts/deploy-vm.sh }
```

**With an SSH key** (recommended) — authorize it once (`ssh-copy-id root@<router-ip>`), then drop
`MB_VM_SSH_PASS` entirely; the script uses plain `ssh`/`scp`, so your key/agent is picked up
automatically (no extra flag needed):

```sh
MB_VM_SSH_HOST=root@<router-ip> MB_VM_SSH_PORT=22 sh scripts/deploy-vm.sh
```

```nu
# nushell
with-env { MB_VM_SSH_HOST: "root@<router-ip>", MB_VM_SSH_PORT: "22" } { sh scripts/deploy-vm.sh }
```

`<router-ip>` is the router's LAN address — usually `192.168.1.1` (private `192.168.x.x`). Double-check
it: `191.168.x.x` is a *public* internet address, not your LAN, and will fail with
`Connection closed … / lost connection`.

What this does:

- Stages the files and copies them to the right paths:
  - rpcd plugin → `/usr/share/rpcd/ucode/monkey-business.uc` (+ `lib/monkey-business/` from `src/`),
  - LuCI views → `/www/luci-static/resources/view/monkey-business/`, menu + ACL,
  - `/etc/config/monkey-business` (UCI), `/etc/init.d/monkey-business` (procd),
  - firewall scripts → `/usr/share/monkey-business/firewall/`, geo script → `/usr/share/monkey-business/geo.sh`,
  - watchdog → `/usr/share/monkey-business/watchdog.sh` + `probes.sh`, bypass-set builder →
    `ruset.sh`.
- **Registers two cron entries** and enables `cron` — idempotent, so re-deploys don't duplicate them:
  `* * * * * …/watchdog.sh` (self-healing, Section 8) and `*/5 * * * * …/boothealth.sh beat`
  (flash-safety heartbeat for the ext4 rootfs). It also enables the `mb-boothealth` init script.
- **Downloads the geo databases** if `/usr/share/xray/{geoip,geosite}.dat` are missing, then builds
  the kernel bypass sets (`ruset.sh build`). Neither is fatal: if the download fails you can still
  do it later from the UI, and without the sets local traffic simply goes direct *through* Xray.
- **Preserves your existing `/etc/config/monkey-business`** across re-deploys (treated as a conffile).
- Installs any missing runtime deps via `apk` (idempotent).
- Restarts `rpcd` and verifies the ubus object registered:
  `>> OK: ubus-объект monkey-business зарегистрирован`.

> This is currently the **only** way to install: `scripts/package.sh` is a stub that always exits
> non-zero, so there is no `.ipk` to build yet (the "Alternative" below is a placeholder for when
> there is).

> **Do not set `MB_UBUS_RESPAWN=1` for real hardware.** That flag (used only by `make dev-deploy`
> for the QEMU dev VM) force-respawns `ubusd`/`rpcd` to work around an emulator bug. The R2S doesn't
> need it and you don't want to kill `ubusd` on a live router.

> **Deploying from macOS:** `deploy-vm.sh` already strips AppleDouble `._*` files
> (`COPYFILE_DISABLE=1`). If you ever copy files to the router by other means, make sure no `._*`
> end up under `/usr/share/rpcd/ucode/` — rpcd-mod-ucode tries to compile them and errors out.

Prefer key-based SSH over a password if you can (`ssh-copy-id root@<router-ip>`), then omit
`MB_VM_SSH_PASS`.

Verify the backend is up:

```sh
# ubus call monkey-business status
# ucode -R - < /usr/share/rpcd/ucode/monkey-business.uc   # must exit cleanly (syntax sanity)
```

### Alternative: install an `.ipk`

If you built a package (`make package` with an `MB_SDK_DIR` SDK — still being wired up), copy it
over and install:

```sh
# apk add ./monkey-business_*.ipk        # or: opkg install ./monkey-business_*.ipk
```

---

## 3. Download the geo databases

Xray will not start without `geoip.dat` and `geosite.dat`. Easiest from LuCI:

**LuCI → Services → monkey-business VPN → Dashboard → Update geo databases.**

It downloads from Loyalsoldier/v2ray-rules-dat (or your custom URLs), validates each file with a
real `xray -test`, and installs them into `/usr/share/xray/`. The download (~30 MB) runs in the
background and the UI polls for completion.

From the shell instead:

```sh
# sh /usr/share/monkey-business/geo.sh download
# ls -la /usr/share/xray/geoip.dat /usr/share/xray/geosite.dat
```

---

## 4. Add servers

In **LuCI → … → Servers**:

- **Subscription:** paste your provider URL and press *Fetch*. Servers are imported (format
  auto-detected: base64 list or `vless://` URI list). The list order is your priority — drag to
  reorder; the first server is the active one. Re-fetch preserves your manual order.
- **Manual:** add a `vless://…` server (Reality/VLESS/XHTTP).

Your subscription token and server UUIDs are stored in UCI (root-only) and masked in the UI — keep
them out of logs and issues.

---

## 5. Configure routing (Settings)

**LuCI → … → Settings.** Sensible defaults are pre-filled:

- **Routing mode** — `Bypass local (recommended)`: your local region (RU/CN/IR) and private
  addresses go direct, everything else through the tunnel. Other modes: `Only blocked via VPN`
  (gfwlist) and `Everything via VPN` (global).
- **Local region** — which region is treated as "local" for direct routing. Pick **`Other`** if
  your region has no geo preset: there is no predefined local geo-category, so you drive the split
  yourself via the custom **Direct (bypass VPN)** / **Via VPN** lists on the Dashboard. Private
  addresses stay direct, and everything not in your lists follows the **Routing mode** default
  (bypass-local → tunnel, gfwlist → direct, global → tunnel).
- **Kill-switch** — fail-closed (default on): LAN traffic to non-local destinations is dropped, not
  leaked direct, whenever it isn't carried by the tunnel (Xray down, a rule gap, or non-proxied
  traffic like ICMP). Disable for a direct fallback when the tunnel is down (less safe).
  Local-region and private traffic are unaffected. Implemented as an nftables `forward` leak-guard
  (`scripts/firewall/apply.sh`).
- **Block IPv6** — on by default, so client traffic can't leak around the IPv4 tunnel.
- **TPROXY port** — change only on a conflict (default `12345`).
- **DNS** — `Split` resolves local-region domains directly and the rest over DoH in the tunnel;
  `All over DoH` sends everything over DoH.
- **Anti-DPI** — uTLS fingerprint + optional XHTTP padding.

Custom per-domain/IP overrides (split-tunnel modes only) live on the **Dashboard** as two lists:
*Direct (bypass VPN)* and *Via VPN* — one entry per line: `domain`, `IP/CIDR`, `geosite:NAME` or
`geoip:NAME`.

Press **Save & Apply**.

---

## 6. Connect & verify

**Dashboard → Turn on.** The status goes *Starting…* → *Connected* once Xray is up (the UI polls
and surfaces errors instead of hanging).

Connecting is not blind: the servers are tried **in list order**, each on a throwaway Xray instance
that must actually carry traffic, and the first one that works becomes the selected server. Reorder
the list to express your preference — a dead entry near the top is skipped rather than connected to.

Probing is not free, though: each candidate costs up to ~10 s, the whole list is tried, and there is
no cap. With many servers and most of them dead, *Turn on* can therefore exceed the ubus timeout and
surface an error instead of a graceful fallback. Keep known-dead servers out of the list, or put a
reliable one first.

Verify the exit path:

- **Dashboard → Check exit IP** — probes ip-api.com *through the split rules*; you should see your
  VPN server's country. (Add ip-api.com to the *Direct* list to see your real IP instead.)
- From the shell:
  ```sh
  # ubus call monkey-business check_exit '{"domain":"ip-api.com"}'
  # pidof xray && echo "xray running"
  # nft list table inet monkey_business        # TPROXY ruleset present
  # logread | grep -iE 'xray|monkey-business'  # runtime logs
  ```
- From a **LAN client** (the real test — this box is your gateway): browse to a foreign site and
  check the observed IP; a local-region site should still report your real IP.

---

## 7. NanoPi R2S notes & troubleshooting

- **Performance.** The RK3328 has no AES hardware acceleration; realistic Reality/VLESS throughput
  is ~100–300 Mbit/s. If you're below that, it's the CPU, not a misconfig — tune XHTTP/sniffing,
  and prefer Reality over heavier TLS stacks.
- **Two NICs.** One R2S Ethernet port is behind USB3; make sure your LAN bridge (`br-lan`) is the
  one clients are on. The firewall intercepts `iifname "br-lan"` by default — if your LAN interface
  differs:
  ```sh
  # uci set monkey-business.global.lan_iface=<iface>
  # uci commit monkey-business          # without commit it reverts on reboot
  # /etc/init.d/monkey-business restart
  ```
- **A *Direct* entry looks ignored (e.g. `ping <IP>` from a LAN client times out).** `ping`/ICMP is
  not a valid test of your *Direct* list: only TCP/UDP is intercepted, and ICMP to a public IP is
  dropped by the kill-switch. Custom *Direct* entries live in Xray's routing only — there is no
  kernel bypass for them — so test with `curl`/`nc` (TCP), or add the host to *Direct* and confirm
  with **Dashboard → Check exit IP**, not with ping.
  The one exception is the **local region**: its CIDRs *are* in the kernel bypass sets
  (`mb_ru4`/`mb_ru6`, enabled by `direct_bypass`, on by default), which the leak-guard accepts — so
  those addresses do answer ping. A local-region IP that doesn't is simply missing from the set:
  ```sh
  # nft list set inet monkey_business mb_ru4 | head        # is the address in there?
  # sh /usr/share/monkey-business/ruset.sh build           # rebuild the sets from the CIDR list
  # sh /usr/share/monkey-business/ruset.sh status          # {"state":…,"v4":N,"v6":N}
  ```
  The sets are built at deploy time and **never refreshed automatically** (no cron, and *Update geo
  databases* only touches the `.dat` files) — rebuild them by hand once in a while. An empty set is
  not a leak: Xray's `geoip:<region> → direct` rule still sends that traffic direct, just slower.
- **`geo databases missing` on Turn on.** Do Section 3 first.
- **Stuck on "Starting…".** Xray crashed — `logread | grep xray`. Usual causes: wrong Reality
  params on the server entry, or a TPROXY port already in use.
- **Config survives reboot/sysupgrade.** `/etc/config/monkey-business` is UCI; keep it in your
  sysupgrade keep-list (it is by default) so servers and credentials persist.
- **`WARN: ubus object did not come up` right after deploy.** A `rpcd restart` can occasionally leave
  `ubusd` alive but not accepting connections (openwrt#9492) — rarer on hardware than in QEMU, but it
  *does* happen. `deploy-vm.sh` now detects an unreachable ubus and respawns `ubusd`+`rpcd`
  automatically; packet forwarding is unaffected (only management blips for a second). If you hit a
  wedge outside the script, recover with
  `killall rpcd ubusd; rm -f /var/run/ubus/ubus.sock; /sbin/ubusd & sleep 2; /sbin/rpcd &` — or just
  `reboot` (the boot itself is fine on hardware; only the QEMU dev-VM has the separate boot-hang).
- **`apk` vs `opkg`.** `deploy-vm.sh` installs runtime deps via whichever your build has. If neither is
  found, install `xray-core kmod-nft-tproxy rpcd-mod-ucode ucode-mod-uci ucode-mod-fs curl` by hand.
- **Direct (non-tunnelled) traffic is slow — seconds to first byte — while the tunnel itself is
  fine.** One known cause: if your ISP hands out no IPv6, `odhcp6c` on `wan6` keeps retrying, burns
  CPU and causes SYN retransmits on direct traffic. It looks like CGNAT or a monkey-business routing
  bug; it is neither. **Confirm before changing anything** — the process should be visibly spinning
  and the log full of retries:
  ```sh
  # top -b -n1 | grep odhcp6c        # noticeable CPU on a supposedly idle router
  # logread | grep -i odhcp6c | tail
  # ip -6 addr show dev $(uci -q get network.wan.device)   # no global IPv6 = nothing to wait for
  ```
  If that matches, disable WAN IPv6. This turns off IPv6 on the WAN entirely — fine when the ISP
  gives you none, but don't do it if you actually have working IPv6:
  ```sh
  # uci set network.wan6.disabled='1'
  # uci commit network
  # /etc/init.d/network restart
  ```
  Verified on one ISP/device; if the symptoms don't match the checks above, look elsewhere.
- **Out of space on the overlay.** A stock ImmortalWrt image leaves a small rootfs; xray-core plus the
  two `.dat` files fill it quickly. You can grow the SD card's ext4 partition from macOS — see
  [docs/sd-expand-macos.md](sd-expand-macos.md).

---

## 8. Self-healing (watchdog & failover)

`make deploy` installs a cron watchdog that runs every minute. It is what keeps a fail-closed
kill-switch from turning a dead tunnel into a dead LAN.

Each tick it checks liveness cheaply (a TLS handshake through the tunnel's SOCKS port) and, every
few ticks, verifies that the exit IP still differs from your home IP — that catches traffic leaking
*around* the tunnel, which a plain "is xray running" check misses. After **3 consecutive failures**
it escalates:

0. **Is the internet up at all?** If a probe *without* the proxy also fails, the problem is your
   uplink, not the tunnel — reconnecting or switching servers would be pointless. The VPN is stopped
   immediately (LAN falls back to direct) and retried every 10 minutes until the link returns.
1. **Reconnect** — otherwise, bounce Xray (`kill`; procd respawns it). The kill-switch is *held*
   throughout, so nothing leaks while the tunnel is down. Up to 2 attempts.
2. **Failover** — ask the backend to re-apply the config, which re-probes the servers in list order
   and selects the first working one.
3. **Fall back to direct** — if no server works, stop the service. This flushes the firewall and
   removes the kill-switch, so the LAN keeps working *without* the VPN. The watchdog then retries
   every 10 minutes and restores the tunnel when it comes back.

Transitions (only transitions — this is flash-friendly) are logged to `/usr/local/server.main.log`,
**not** to `logread`:

```sh
# tail -f /usr/local/server.main.log
# cat /tmp/mb-watchdog/state          # phase, fail counters, exit/home IP
```

There are no UCI options and no LuCI switch. Tuning is env-only (`MB_WD_*`, defaults at the top of
`watchdog.sh`), and since cron passes no environment, you tune it by editing the crontab line
itself — e.g. to fail over sooner:

```sh
# sed -i 's#^\* \* \* \* \* /usr/share/monkey-business/watchdog.sh#* * * * * MB_WD_FAIL_LIMIT=2 /usr/share/monkey-business/watchdog.sh#' /etc/crontabs/root
# /etc/init.d/cron restart
```

To disable it, delete the **`watchdog.sh`** line from `/etc/crontabs/root` (leave the
`boothealth.sh beat` line — that one is flash-safety, not VPN).

---

For everything else (architecture, development, the dev VM), see the main
[README](../README.md).
