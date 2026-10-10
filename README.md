# monkey-business

**English** | [Русский](README.ru.md)

A minimalist VPN client for **OpenWrt / ImmortalWrt** routers (target hardware: **NanoPi R2S**).
Reality + VLESS + XHTTP (and hysteria2) with a simple LuCI interface — a lightweight alternative to
passwall / v2rayA.

```
LuCI (JS) → rpcd (ucode) → UCI → config generator → Xray-core + nftables TPROXY + dnsmasq
```

Subscription import (auto-detected format) or manual `vless://` / `hysteria2://` servers; split
routing by geoip/geosite (local region direct, the rest through the tunnel), kill-switch, IPv6-leak
block, DoH split-DNS, anti-DPI (uTLS + XHTTP padding), and a one-screen dashboard.

Both protocols live in **one** server list: the protocol is a property of the server, so list order
stays the single priority and failover crosses protocols. hysteria2 runs as a separate client next
to Xray (its `proxy` outbound becomes a local socks) — the split, DNS and kill-switch rules are
exactly the ones VLESS uses. The client binary is installed with a button on the dashboard.

Two things happen without you asking. **Local-region traffic skips the proxy in the kernel**: its
CIDRs live in nftables sets (`mb_ru4`/`mb_ru6`) that are excluded from TPROXY, so it never pays the
Xray hop — the `geoip:<region> → direct` rule inside Xray stays as a safety net. And **a dead tunnel
heals itself**: a cron watchdog probes the tunnel every minute and climbs a ladder — *soft bounce →
hard restart → fail over to the next working server → full stop/start → fall back to direct* —
rather than leaving the LAN behind a fail-closed kill-switch. The same kind of probe picks the server when you connect: candidates are tried in list
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

1. **Servers** tab — paste your subscription URL and *Fetch*, or add a `vless://` / `hysteria2://`
   server manually.
   A second provider is another *Add subscription*; the active one is switched on the Dashboard
   ([multiple subscriptions](docs/install-nanopi.md#10-multiple-subscriptions)).
2. **Dashboard** — *Update geo databases* (downloads & validates geoip/geosite `.dat`).
3. **Dashboard** — *Install / update hysteria* — only if your list contains hysteria2 servers.
4. **Dashboard** — *Turn on*. *Check exit IP* confirms traffic leaves through the tunnel.

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
| `src/parser/` | subscription parser (base64 / uri-list; auto-detect; `vless://` + `hysteria2://`) |
| `src/generator/` | UCI → Xray JSON generator (abstracted for a future sing-box backend) + the hysteria client config |
| `src/rpcd/` | pure rpcd handlers (host-tested; ubus/uci bound in `root/…/rpcd/ucode`) |
| `src/runtime/` | device-bound helpers pulled out of the rpcd plugin (hysteria config/install/probe) |
| `src/lib/` | shared utils (URI parsing) |
| `luci/` | LuCI client-side JS views (dashboard / servers / settings) + the split panel (`routing.js`, rendered inside the dashboard) + menu + ACL |
| `root/` | on-device files: UCI default, procd init, runtime rpcd plugin |
| `root/usr/share/monkey-business/` | on-device shell: `watchdog.sh` + `probes.sh` + `recovery.sh` + `phases.sh` + `wdlock.sh` (self-healing; the lock is shared with `subupdate.sh`), `ruset.sh` (nft direct-bypass sets), `geo.sh`, `fetch.sh` (shared downloader: socks fallback, stalled mirrors dropped by a speed floor), `boothealth.sh`, `hysteria.sh` + `hysum.sh` (hysteria2 client installer, checksum confirmed by a majority of mirrors), `subupdate.sh` (scheduled subscription refresh), `nicfw.sh` + `nicwatch.sh` (RTL8153B USB NIC, see [install guide §9](docs/install-nanopi.md#9-the-rtl8153b-usb-nic-firmware--watchdog)) |
| `scripts/firewall/` | nftables TPROXY apply/flush |
| `scripts/expand-sd.sh` | grow the SD card's ext4 partition from macOS ([docs](docs/sd-expand-macos.md)) |
| `test/` | ucode harness + unit/snapshot tests + netns integration |

Pure logic (`parser`, `generator`) stays free of `uci`/`ubus` so it is host-testable; the only
device-bound code is the runtime rpcd plugin and the shell scripts. See `.context/` for the full
architecture, conventions, and specs.

### Preview on a live router (dev VM)

See the app on a real ImmortalWrt aarch64 system in QEMU before flashing hardware:

```sh
make dev            # boot the VM, provision it, deploy the app, add the subscription
make dev FIXTURE=1  # same, plus seeded UI variants (second subscription, off / manual / unreachable / hysteria2 server)
make dev-test-split # check split routing: exit IP/country via the SOCKS test inbound
make dev-down       # stop the VM and reset it (the downloaded image and geo databases stay cached)
```

Then open **http://localhost:8090** (login `root` / `root`) → **Services → monkey-business VPN**.
Override the port with `MB_VM_HTTP_PORT=NNNN make dev` if 8090 is taken
(nushell: `with-env { MB_VM_HTTP_PORT: "NNNN" } { make dev }`).

`make dev` is idempotent: each step runs only when needed.

- **VM** boots unless already running. The first run downloads the image to `.dev-vm/cache/`.
- **Provision** (static IP 10.0.2.15, root password, LuCI) runs unless SSH `root`/`root` works and `uhttpd` exists.
- **Geo** databases come from the host cache `.dev-vm/cache/geo/` (`scripts/dev-geo.sh`), so the VM
  does not download them while the cache is complete (otherwise deploy downloads the missing ones in
  the VM). An empty cache is filled from the router (`root@192.168.1.1`, override:
  `MB_GEO_R2S`). On every run the cache is checked against the `.sha256sum` files on the mirrors of
  `geo.sh` and re-downloaded only on mismatch; without network the cache is used as is. A file is
  copied into the VM only when its sha256 differs.
- **Deploy** runs when the hash of `luci/`, `root/`, `src/`, `scripts/` differs from the one stored in
  the VM (`/etc/mb-dev-deployed`), so re-running `make dev` after a code change redeploys. The hash is
  stored only after the `monkey-business` ubus object shows up.
- **Subscription** is added from `.context/notes/vpnon-sub.local` (override: `MB_VM_SUB_FILE`) if the
  file exists and the VM has none. The URL goes over stdin, never into
  a command line, and is never printed.
- **Fixture** (`FIXTURE=1`) serves `scripts/fixture/sub.txt` from the host over HTTP (with
  `subscription-userinfo`) and adds it as the *Fixture* subscription (auto-update off), turns one
  server off and adds a manual server (`scripts/fixture/seed.uc`). The unreachable server points at
  `127.0.0.1:9` inside the VM, so it fails regardless of the host network. Re-running re-fetches the
  fixture and adds nothing twice.

| Command | Purpose |
|---------|---------|
| `make dev` | bring the test stand up in one command (VM, provision, geo, deploy, subscription) |
| `make dev FIXTURE=1` | the same plus seeded UI variants for mockup checks |
| `make dev-ssh` | SSH into the VM (`root` / `root`) |
| `make dev-console` | attach to the VM serial console |
| `make dev-status` | VM status |
| `make dev-down` | stop the VM and reset it; the next `make dev` starts from a clean disk |

> The VM uses QEMU user-mode NAT (SSH `:2222→22`, LuCI `:8090→80`) — enough for UI/logic work.
> The "LAN client through TPROXY" scenario is exercised by `make test-integ`, not this VM.

---

## Troubleshooting

### Dev VM (QEMU)

On Apple Silicon the VM uses **HVF** (near-native); elsewhere it falls back to slow TCG emulation.

- **Boot hangs at `procd: - ubus -` (SSH "banner exchange" timeout) — on reboot OR on a second
  boot of an already-used disk.**
  A QEMU-emulation race where `ubusd` doesn't come up on any *non-first* boot
  (openwrt/openwrt#9492, #13600) — **not** the app, and not fixed by HVF/virtio-rng. Only the first
  boot of a fresh disk is reliable. `make dev-down` resets the disk, so `make dev` always boots a
  fresh one. If `make dev` stops with a boot timeout, reset and start over (~5–8 min):
  ```sh
  make dev-down
  make dev
  ```
  Never `reboot` the guest — use `make dev-down` / `make dev`. This race does not occur on real
  NanoPi R2S hardware.

- **The ubus object doesn't register / `Failed to connect to ubus` after the deploy step of `make dev`.**
  Handled by the current scripts; if you hit it, two things were historically at play:
  1. **rpcd compiles ucode plugins from a buffer** (no file path), so the rpcd entrypoint must use
     an **absolute** import path. Relative `./…` imports fail under rpcd (but work via the `ucode`
     CLI, which hides the bug). Transitively imported `lib/` modules may stay relative.
  2. **Emulated `ubusd` wedges on `rpcd restart`** (alive but stops accepting connections,
     openwrt#9492). `make dev` detects this and **respawns `ubusd`+`rpcd` fresh** (dev VM only,
     via `MB_UBUS_RESPAWN=1`; never on real hardware).
  Also, macOS `tar` adds AppleDouble `._*` files — the deploy strips them (`COPYFILE_DISABLE=1`);
  they would otherwise reach a real R2S too. Verify on the target:
  `cat /usr/share/rpcd/ucode/monkey-business.uc | ucode -R -` (must exit cleanly), then
  `ubus call monkey-business status`.

- **No internet in the VM / `apk` fails / LuCI didn't install.** The guest must be on `10.0.2.15`
  (QEMU SLIRP). Provision in `make dev` sets this statically; verify with `make dev-ssh` then
  `ip -4 addr show br-lan`. If it shows `192.168.1.1`, run `make dev-down`, then `make dev`.

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
  directly, just more slowly. The mechanism has no switch of its own — it follows the split you
  picked on the Dashboard and is on only for **Bypass local + Russia** (the sets are filled from a
  RU CIDR list, so any other mode or region would send traffic around the tunnel you asked for).
  Pick another routing mode to turn it off; the Dashboard spells out what each choice enables.
- **The tunnel died and the router switched servers on its own.** That's the watchdog. It logs only
  transitions to syslog — `logread -f -e mb-event` to see
  `Reconnecting…` / `VPN recovered by <step>…` / `VPN stopped, LAN on direct`. Live state is in
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
