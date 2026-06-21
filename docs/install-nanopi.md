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

The easiest path mirrors the dev workflow but targets the R2S over SSH. From the repo checkout:

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
  - firewall scripts → `/usr/share/monkey-business/firewall/`, geo script → `/usr/share/monkey-business/geo.sh`.
- **Preserves your existing `/etc/config/monkey-business`** across re-deploys (treated as a conffile).
- Installs any missing runtime deps via `apk` (idempotent).
- Restarts `rpcd` and verifies the ubus object registered:
  `>> OK: ubus-объект monkey-business зарегистрирован`.

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
  differs, set `uci set monkey-business.global.lan_iface=<iface>` and re-apply.
- **A *Direct* entry looks ignored (e.g. `ping <IP>` from a LAN client times out).** `ping`/ICMP
  is not a valid test: only TCP/UDP is intercepted, so ICMP to any public IP is dropped by the
  kill-switch whether or not the address is on the *Direct* list. Direct routing happens inside
  Xray (there is no kernel-level bypass), so test with `curl`/`nc` (TCP), or add the host to *Direct*
  and confirm with **Dashboard → Check exit IP** — not with ping.
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

---

For everything else (architecture, development, the dev VM), see the main
[README](../README.md).
