# Corporate routing and VPN availability

Corporate gateways are configured on **Dashboard → Routing → Corporate tunnels**.
Use a public gateway IPv4 and, optionally, a TCP/UDP port. Each rule has its own
**Via VPN** switch and **Tunnel requires UDP** flag. At most 32 rules are allowed.
An exact port takes precedence over a wildcard rule for the same gateway. A rule
switched off explicitly uses direct routing. The override applies to LAN traffic,
including port 53; diagnostics and router bootstrap traffic have separate paths.

Editing, removing and undoing a rule changes the page draft. **Save & Apply** applies
only routing mode, region, custom lists and corporate rules. It retains the actual
running server, credentials, DNS and other runtime settings. During Apply, affected corporate proxy flows are briefly blocked until both routing engines and durable state agree; unrelated traffic and exact direct exceptions remain scoped. A failed Apply retains
the draft and reports the error; a lost response can be retried with the same request.
**Discard changes** restores the latest observed committed draft. Navigating away
from unapplied changes asks whether to stay or discard them.

Enabled corporate rules start direct after boot, explicit VPN activation or a new
outbound. Two successful health rounds allow VPN routing. Two failed HTTPS rounds
fall back to direct; two failed UDP rounds do so only for UDP-dependent rules.
An internal diagnostic error is unknown and retains the effective route. HTTPS and
UDP are independent. Automatic return to VPN respects a 60-second cooldown and
resets only matching original LAN connections; failure of that precise reset is
reported. Turning VPN off does not run network diagnostics.

**Check availability** starts a router-owned job for a node, subscription or all
nodes, including disabled nodes (maximum 200). Closing the progress dialog does not
cancel it; **Cancel check** does. HTTPS status, base latency/success count, UDP and
measurement age are separate. A failed check describes the diagnostic targets,
not the ability to run every possible application or corporate VPN.

Two HTTPS targets are checked in parallel, with TLS verification, no redirects,
expected status 200/204 and a 4096-byte response limit. UDP checks use two STUN
servers. The five best HTTPS candidates get one extra request. Base measurements
alone determine latency and success fraction. Results expire after five minutes
or changes to the node, method, boot or known network generation. The active VPN
health display is independent of these manual results. Up to 500 node records stay
in tmpfs for ten minutes independently of the four job histories. Cancelling an
unfinished extra request preserves the previous completed result and base timestamp.

**Sort** changes the draft within existing subscription/manual group positions;
disabled/manual nodes and the active subscription remain intact. **Apply priority**
saves only priority order and does not reconnect. **Save** in the node editor stages
its fields in LuCI; applying those ordinary editor/settings changes uses LuCI's
configuration Apply and may reconnect. Connect confirms the proposed server through
the VPN before changing the running outbound; no unconfirmed fallback is selected.

Availability targets are edited separately in **Settings** and applied with their
own scoped action. Read-only users can view safe status and results; they cannot
start/cancel checks, edit targets, read raw UCI, upload geo files or change routing.

## Compatibility and migration

The installation needs cgroup v2 with `cgroup.kill`, nft socket-cgroup support
(`kmod-nft-socket`), TPROXY, ucode fs/uci/socket, `curl` with CA certificates,
GNU `timeout`, `flock` and `conntrack`. Startup refuses missing isolation support.
The local qualified versions and hardware gate are in the [acceptance record](routing-availability-acceptance.md).

The procd `monkey-business-observer` service owns jobs, the sole 15-second health
observer and recovery. Installation removes the old cron watchdog entry; the old
watchdog command is a compatibility status check. Reload the LuCI page after an
upgrade: legacy ping RPCs return API v2 `deprecated`, not a fake TCP result. New RPCs
use typed server references, asynchronous availability jobs and scoped revisioned
routing/order/settings changes. Read-only UCI permission is removed; writers retain
editor access. Existing routing/priority is preserved until an explicit action. If an older installation has no applied snapshot, use an explicit Connect/enable to create a confirmed one; routing-only Apply refuses to guess it.

Subscriptions and downloads require HTTPS with certificate validation. Raw captured
subscriptions are private and must be sanitized before becoming test fixtures.
Corporate probes and installation on a real router require separate authorization.
