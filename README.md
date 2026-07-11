# monkey-business

**English** | [Русский](README.ru.md)

A minimalist VPN client for **OpenWrt / ImmortalWrt** routers (target hardware: **NanoPi R2S**).
Reality + VLESS + XHTTP with a simple LuCI interface — a lightweight alternative to passwall / v2rayA.

```
LuCI (JS) → rpcd (ucode) → UCI → config generator → Xray-core + nftables TPROXY + dnsmasq
```

Subscription import (auto-detected format) or manual `vless://` servers; split routing by
geoip/geosite (local region direct, the rest through the tunnel), kill-switch, IPv6-leak block,
DoH split-DNS, anti-DPI (uTLS + XHTTP padding), and a one-screen dashboard.

Two things happen without you asking. **Local-region traffic skips the proxy in the kernel**: its
CIDRs live in nftables sets (`mb_ru4`/`mb_ru6`) that are excluded from TPROXY, so it never pays the
Xray hop — the `geoip:<region> → direct` rule inside Xray stays as a safety net. And **a dead tunnel
heals itself**: a cron watchdog probes the tunnel every minute and escalates *reconnect → fail over
to the next working server → fall back to direct* rather than leaving the LAN behind a fail-closed
kill-switch. The same kind of probe picks the server when you connect: candidates are tried in list
order and the first one that actually carries traffic wins.

> ⚠️ **Work in progress.** The backend (subscription parser, config generator, rpcd handlers) is
> covered by host unit tests; the network path (TPROXY/DNS) by a netns harness and real-`xray`
> config validation. Real VPN throughput is validated on hardware.

---

## Install

The app runs on the router. Two ways to get it there.

### Option A — deploy over SSH (no packaging)

If ImmortalWrt/OpenWrt is already on the router and you have SSH access, the one-liner is
`make deploy` — a wrapper (`scripts/deploy.sh`) that runs the local checks first, then deploys
with device defaults (SSH :22) and keeps your `/etc/config/monkey-business` across re-runs:

```sh
make deploy HOST=root@<router-ip>          # add MB_PASS=… if you don't use an SSH key
```

It calls `scripts/deploy-vm.sh` underneath, which you can also run directly:

```sh
MB_VM_SSH_HOST=root@<router-ip> MB_VM_SSH_PORT=22 MB_VM_SSH_PASS=<password> \
  sh scripts/deploy-vm.sh
```

```nu
# nushell
with-env { MB_VM_SSH_HOST: "root@<router-ip>", MB_VM_SSH_PORT: "22", MB_VM_SSH_PASS: "<password>" } { sh scripts/deploy-vm.sh }
```

**With an SSH key** (recommended) — authorize it once (`ssh-copy-id root@<router-ip>`), then just
omit `MB_VM_SSH_PASS`; your key/agent is used automatically:

```sh
MB_VM_SSH_HOST=root@<router-ip> MB_VM_SSH_PORT=22 sh scripts/deploy-vm.sh
```

```nu
# nushell
with-env { MB_VM_SSH_HOST: "root@<router-ip>", MB_VM_SSH_PORT: "22" } { sh scripts/deploy-vm.sh }
```

`<router-ip>` is your router's LAN address — usually `192.168.1.1` (the private `192.168.x.x` range).

This installs the rpcd plugin, LuCI views, init script, firewall and geo scripts, and idempotently
pulls the runtime deps (`xray-core`, `kmod-nft-tproxy`, `curl`, the rpcd/ucode mods) via `apk`.
Then open LuCI → **Services → monkey-business VPN**.

A step-by-step walkthrough for the NanoPi R2S (deps, geo databases, first connection, verification)
is in **[docs/install-nanopi.md](docs/install-nanopi.md)**.

### Option B — build an `.ipk`

Packaging via the OpenWrt/ImmortalWrt SDK for the target (rockchip/armv8):

```sh
export MB_SDK_DIR=/path/to/immortalwrt-sdk   # SDK for rockchip/armv8
make package
```

```nu
# nushell
$env.MB_SDK_DIR = "/path/to/immortalwrt-sdk"  # SDK for rockchip/armv8
make package
```

The artifact lands in the SDK's `bin/packages/aarch64*/`; copy it to the router and
`apk add ./<pkg>.ipk` (or `opkg install`). *(SDK packaging is still being wired up — see
`scripts/package.sh`; until then use Option A.)*

### First run

1. **Servers** tab — paste your subscription URL and *Fetch*, or add a `vless://` server manually.
2. **Dashboard** — *Update geo databases* (downloads & validates geoip/geosite `.dat`).
3. **Dashboard** — *Turn on*. *Check exit IP* confirms traffic leaves through the tunnel.

---

## Development

Code is edited on the host; checks run in a Linux container (built automatically on first use),
because a macOS host has no ucode/nftables/netns.

```sh
make test        # lint (shellcheck + ucode syntax + eslint) + ucode unit/snapshot tests
make test-integ  # netns TPROXY interception + generated config validated against a real xray
```

Layout:

| Path | What |
|------|------|
| `src/parser/` | subscription parser (base64 / uri-list; auto-detect) |
| `src/generator/` | UCI → Xray JSON generator (abstracted for a future sing-box backend) |
| `src/rpcd/` | pure rpcd handlers (host-tested; ubus/uci bound in `root/…/rpcd/ucode`) |
| `src/lib/` | shared utils (URI parsing) |
| `luci/` | LuCI client-side JS views (dashboard / servers / settings) + menu + ACL |
| `root/` | on-device files: UCI default, procd init, runtime rpcd plugin |
| `root/usr/share/monkey-business/` | on-device shell: `watchdog.sh` + `probes.sh` (self-healing), `ruset.sh` (nft direct-bypass sets), `geo.sh`, `boothealth.sh` |
| `scripts/firewall/` | nftables TPROXY apply/flush |
| `scripts/expand-sd.sh` | grow the SD card's ext4 partition from macOS ([docs](docs/sd-expand-macos.md)) |
| `test/` | ucode harness + unit/snapshot tests + netns integration |

Pure logic (`parser`, `generator`) stays free of `uci`/`ubus` so it is host-testable; the only
device-bound code is the runtime rpcd plugin and the shell scripts. See `.context/` for the full
architecture, conventions, and specs.

### Preview on a live router (dev VM)

See the app on a real ImmortalWrt aarch64 system in QEMU before flashing hardware:

```sh
make dev-up         # boot the VM headless (downloads the image on first run)
make dev-provision  # one-time: DHCP + root password + LuCI (~a few minutes)
make dev-deploy     # install the app into the VM and reload rpcd
make dev-test-split # check split routing: exit IP/country via the SOCKS test inbound
```

Then open **http://localhost:8090** (login `root` / `root`) → **Services → monkey-business VPN**.
Override the port with `MB_VM_HTTP_PORT=NNNN make dev-up` if 8090 is taken
(nushell: `with-env { MB_VM_HTTP_PORT: "NNNN" } { make dev-up }`).

| Command | Purpose |
|---------|---------|
| `make dev-up` | start the VM (background, headless) |
| `make dev-provision` | one-time setup (network / password / LuCI) |
| `make dev-deploy` | deploy the app + runtime deps, reload rpcd |
| `make dev-ssh` | SSH into the VM (`root` / `root`) |
| `make dev-rebuild` | full clean rebuild of the VM (if the boot hangs) |
| `make dev-down` | stop the VM |

> The VM uses QEMU user-mode NAT (SSH `:2222→22`, LuCI `:8090→80`) — enough for UI/logic work.
> The "LAN client through TPROXY" scenario is exercised by `make test-integ`, not this VM.

---

## Troubleshooting

### Dev VM (QEMU)

On Apple Silicon the VM uses **HVF** (near-native); elsewhere it falls back to slow TCG emulation.

- **Boot hangs at `procd: - ubus -` (SSH "banner exchange" timeout) — on reboot OR on a second
  `dev-up` of an already-used disk.**
  A QEMU-emulation race where `ubusd` doesn't come up on any *non-first* boot
  (openwrt/openwrt#9492, #13600) — **not** the app, and not fixed by HVF/virtio-rng. Only the first
  boot of a freshly-downloaded image is reliable. Recovery is one command:
  ```sh
  make dev-rebuild   # clean + up + provision + deploy from scratch (~5–8 min)
  ```
  To avoid it: **keep the VM running between sessions** (don't `make dev-down`), and never `reboot`
  the guest — use `make dev-down` / `dev-up`. This race does not occur on real NanoPi R2S hardware.

- **The ubus object doesn't register / `Failed to connect to ubus` after `make dev-deploy`.**
  Handled by the current scripts; if you hit it, two things were historically at play:
  1. **rpcd compiles ucode plugins from a buffer** (no file path), so the rpcd entrypoint must use
     an **absolute** import path. Relative `./…` imports fail under rpcd (but work via the `ucode`
     CLI, which hides the bug). Transitively imported `lib/` modules may stay relative.
  2. **Emulated `ubusd` wedges on `rpcd restart`** (alive but stops accepting connections,
     openwrt#9492). `make dev-deploy` detects this and **respawns `ubusd`+`rpcd` fresh** (dev VM only,
     via `MB_UBUS_RESPAWN=1`; never on real hardware).
  Also, macOS `tar` adds AppleDouble `._*` files — the deploy strips them (`COPYFILE_DISABLE=1`);
  they would otherwise reach a real R2S too. Verify on the target:
  `cat /usr/share/rpcd/ucode/monkey-business.uc | ucode -R -` (must exit cleanly), then
  `ubus call monkey-business status`.

- **No internet in the VM / `apk` fails / LuCI didn't install.** The guest must be on `10.0.2.15`
  (QEMU SLIRP). `make dev-provision` sets this statically; verify with `make dev-ssh` then
  `ip -4 addr show br-lan`. If it shows `192.168.1.1`, re-run `make dev-provision`.

For the backend (ubus/rpcd/ucode/xray) the most reliable target is real hardware — `deploy-vm.sh`
can target a NanoPi R2S over SSH (see Install → Option A).

### Runtime (on the router)

- **`Turn on` fails / `geo databases missing`.** Xray won't start without geoip/geosite `.dat`.
  Press **Update geo databases** on the Dashboard first (downloads ~30 MB in the background and
  validates with `xray -test` before installing — slower than the ubus timeout, hence the button).
- **`no servers — add a subscription or a manual server first`.** Import a subscription on the
  Servers tab, or add a `vless://` server manually.
- **Apply fails with an Xray message.** The generated config is validated with `xray -test` before
  being written; the first error line is surfaced. A common cause is a wrong Reality
  SNI/publicKey/shortId from the server entry.
- **Status stuck on "Starting…".** Xray started but isn't running — it likely crashed. Check
  `logread | grep xray`. (Liveness uses `pidof xray`; BusyBox `pgrep -x` does not match.)
- **"Check exit IP" returns an error.** The probe goes through the SOCKS test inbound — make sure
  the VPN is on and the service is running.
- **Settings/routing changes don't apply from LuCI.** Save & Apply commits server-side
  (`config_apply` / `set_routing`) so nothing is left in LuCI's "Unsaved Changes" limbo.
- **A LAN client can ping local-region IPs but not foreign ones.** Expected, with the kill-switch on
  (the default). ICMP is never proxied (only TCP/UDP is intercepted), so a foreign IP is dropped by
  the kill-switch, while a local-region IP is accepted because it sits in the `mb_ru4`/`mb_ru6`
  bypass sets. Ping therefore tells you set membership, not tunnel health — check with
  `nft list set inet monkey_business mb_ru4`.
- **The bypass sets are empty / local traffic still goes through Xray.** The CIDR list is built at
  deploy time; rebuild it by hand with `sh /usr/share/monkey-business/ruset.sh build` (there is no
  cron job and *Update geo databases* does **not** rebuild it — it only refreshes the `.dat` files).
  An empty set is not a leak: Xray's `geoip:<region> → direct` rule still routes that traffic
  directly, just more slowly. To disable the mechanism entirely:
  ```sh
  # uci set monkey-business.global.direct_bypass=0
  # uci commit monkey-business
  # /etc/init.d/monkey-business restart
  ```
- **The tunnel died and the router switched servers on its own.** That's the watchdog. It logs only
  transitions to `/usr/local/server.main.log` (not `logread`) — `tail -f` it to see
  `Reconnecting…` / `Failover switched server…` / `VPN stopped, LAN on direct`. Live state is in
  `/tmp/mb-watchdog/state`. See [the install guide](docs/install-nanopi.md#8-self-healing-watchdog--failover)
  for the escalation ladder and how to tune or disable it.
- **Direct (non-tunnelled) sites are slow while the tunnel itself is fine.** Usually `odhcp6c`
  busy-looping on `wan6` when the ISP hands out no IPv6 — see
  [the install guide](docs/install-nanopi.md#7-nanopi-r2s-notes--troubleshooting).

---

## Feedback

Found a bug, hit a routing edge case, or want a feature? Please use GitHub:

- **Bugs / feature requests** → [open an issue](https://github.com/n0sfer666/monkey-business/issues).
  Include your router model, ImmortalWrt/OpenWrt version, the routing mode and local region, and the
  relevant `logread | grep -iE 'xray|monkey-business'` output (redact your subscription token/UUIDs).
- **Questions / ideas** → [GitHub Discussions](https://github.com/n0sfer666/monkey-business/discussions).
- **Patches** → pull requests welcome. Run `make test` (and `make test-integ` if you touched the
  generator or firewall) before submitting; keep commits in [Conventional Commits](https://www.conventionalcommits.org) style.

---

## License

[GPL-3.0](LICENSE).
