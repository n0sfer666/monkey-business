# monkey-business

A minimalist VPN client for **OpenWrt / ImmortalWrt** routers (target hardware: **NanoPi R2S**).
Reality + VLESS + XHTTP with a simple LuCI interface — a lightweight alternative to passwall / v2rayA.

LuCI (JS) → rpcd (ucode) → UCI → config generator → Xray-core + nftables TPROXY + dnsmasq.

> ⚠️ **Work in progress.** Backend (subscription parser, config generator, rpcd) is covered by host
> unit tests; the network path (TPROXY/DNS) by a netns harness. Real VPN connection and on-device
> performance are validated on hardware.

## Requirements

- **Docker** (daemon running) — all linting/tests run inside a Linux container, because a macOS host
  has no ucode/nftables/netns.
- **QEMU** (`brew install qemu`) — only for the dev VM.

## Build an installable package

Packaging produces an `.ipk` via the OpenWrt/ImmortalWrt SDK for the target (rockchip/armv8):

```sh
export MB_SDK_DIR=/path/to/immortalwrt-sdk   # SDK for rockchip/armv8
make package
```

The artifact lands in the SDK's `bin/packages/aarch64*/`; copy it to the router and install with
`apk add ./<pkg>.ipk` (or `opkg install`). *(SDK packaging is still being wired up — see
`scripts/package.sh`.)*

## Development

Code is edited on the host; checks run in a container (built automatically on first use):

```sh
make test        # lint + ucode/JS syntax + unit tests
make test-integ  # netns TPROXY + config validation against a real xray (privileged Docker)
```

## Preview on a live router (dev VM)

See the app running on a real ImmortalWrt aarch64 system in QEMU before flashing hardware:

```sh
make dev-up         # boot the VM headless (downloads the image on first run)
make dev-provision  # one-time setup: DHCP + root password + LuCI (~a few min)
make dev-deploy     # install the app into the VM and reload rpcd
```

Then open **http://localhost:8090** (login `root` / `root`) → **Services → monkey-business VPN**.
(Override the port with `MB_VM_HTTP_PORT=NNNN make dev-up` if 8090 is taken.)

| Command | Purpose |
|---------|---------|
| `make dev-up` | start the VM (background, headless) |
| `make dev-provision` | one-time setup (network / password / LuCI) |
| `make dev-deploy` | deploy the app + runtime deps, reload rpcd |
| `make dev-ssh` | SSH into the VM (`root` / `root`) |
| `make dev-status` | VM status and forwarded ports |
| `make dev-down` | stop the VM |

> The VM uses QEMU user-mode NAT (SSH `:2222→22`, LuCI `:8090→80`) — enough for UI/logic work.
> The "LAN client through TPROXY" scenario is exercised by `make test-integ`, not this VM.
> Do **not** `reboot` the guest (emulated `ubusd` doesn't restart cleanly) — use `make dev-down` / `dev-up`.

## Troubleshooting (dev VM)

The dev VM is `qemu-system-aarch64`. On Apple Silicon it uses **HVF** (near-native); elsewhere it
falls back to slow TCG emulation.

- **The ubus object doesn't register / `Failed to connect to ubus` after `make dev-deploy`.**
  Handled by the current scripts; if you hit it, make sure you're up to date. Two things were at play:
  1. **`rpcd` compiles ucode plugins from a buffer** (no file path), so the rpcd entrypoint must use
     an **absolute** import path. Relative `./…` imports fail under rpcd (but work via the `ucode`
     CLI, which hides the bug). Transitively imported modules under `lib/` may stay relative.
  2. **Emulated `ubusd` wedges on `rpcd restart`** (alive but stops accepting connections — a known
     QEMU/OpenWrt issue, openwrt#9492). `make dev-deploy` detects this and **respawns `ubusd`+`rpcd`
     fresh** (only on the dev VM, via `MB_UBUS_RESPAWN=1`; never on real hardware).
  Also, macOS `tar` adds AppleDouble `._*` files (the deploy strips them with `COPYFILE_DISABLE=1`) —
  cosmetic rpcd errors, but worth keeping clean (they also reach a real R2S when deploying from a Mac).
  Verify on the target: `cat /usr/share/rpcd/ucode/monkey-business.uc | ucode -R -` (must exit
  cleanly), then `ubus call monkey-business status`.

- **Boot hangs at `procd: - ubus -` (SSH "banner exchange" timeout) — on reboot OR on `dev-up`
  of an already-used disk.**
  A genuine QEMU-emulation race where `ubusd` doesn't come up on any *non-first* boot
  (see openwrt/openwrt#9492, #13600) — **not** related to the app, and not fixed by HVF/virtio-rng.
  Only the first boot of a freshly-downloaded image is reliable; once the overlay has been written
  (provision/deploy), subsequent boots tend to hang. Recovery — **one command**:
  ```sh
  make dev-rebuild     # clean + up + provision + deploy from scratch (~5–8 min)
  ```
  To avoid it: **keep the VM running between sessions** (don't `make dev-down`). On real NanoPi R2S
  hardware this race does not occur.

- **No internet in the VM / `apk` fails / LuCI didn't install.** The guest must be on
  `10.0.2.15` (QEMU SLIRP). `make dev-provision` sets this statically; verify with
  `make dev-ssh` then `ip -4 addr show br-lan`. If it shows `192.168.1.1`, re-run `make dev-provision`.

For the **backend** (ubus/rpcd/ucode/xray) the most reliable target is real hardware — the same
`deploy-vm.sh` can target a **NanoPi R2S** over SSH:
`MB_VM_SSH_HOST=root@<ip> MB_VM_SSH_PORT=22 MB_VM_SSH_PASS=<pw> sh scripts/deploy-vm.sh`.
Final validation (real VPN connection, performance) is done there.

## License

TBD.
