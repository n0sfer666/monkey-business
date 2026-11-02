#!/bin/sh
# Persistent root-only diagnostics, including engines' dynamic loopback UDP relays.
set -eu
STATE=/tmp/mb-runtime
for dependency in nft ucode curl timeout flock; do
 command -v "$dependency" >/dev/null 2>&1 || { echo "required diagnostic dependency missing: $dependency" >&2; exit 1; }
done
ucode /usr/share/monkey-business/guard-setup.uc
# 0x40000000 is reserved by this application only for non-root loopback UDP packets.
# INPUT clears it for unrelated sockets; no routing hook or global UDP-port ban.
nft -f - <<'NFT'
table inet monkey_business_diagnostics
delete table inet monkey_business_diagnostics
table inet monkey_business_diagnostics {
 chain input {
  type filter hook input priority -150; policy accept;
  meta mark 1 return
  iifname "lo" meta l4proto udp meta mark & 0x40000000 != 0 socket cgroupv2 level 1 "monkey-business-engines" counter drop
  iifname "lo" meta mark & 0x40000000 != 0 meta mark set meta mark & 0xbfffffff
  iifname != "lo" meta l4proto { tcp, udp } th dport { 10808-10811, 11800-12263 } counter drop
  iifname != "lo" ip daddr 127.0.0.0/8 meta l4proto udp socket cgroupv2 level 1 "monkey-business-engines" drop
  iifname != "lo" ip6 daddr ::1 meta l4proto udp socket cgroupv2 level 1 "monkey-business-engines" drop
 }
 chain output {
  type filter hook output priority -150; policy accept;
  meta skuid != 0 ip daddr 127.0.0.0/8 meta l4proto udp meta mark set meta mark | 0x40000000
  meta skuid != 0 ip6 daddr ::1 meta l4proto udp meta mark set meta mark | 0x40000000
  meta skuid != 0 ip daddr 127.0.0.0/8 meta l4proto tcp th dport { 10808-10811, 11800-12263 } reject
  meta skuid != 0 ip6 daddr ::1 meta l4proto tcp th dport { 10808-10811, 11800-12263 } reject
 }
}
NFT
(umask 077; printf 'cgroup-v2-socket-v1\n' > "$STATE/.guard-ready.new" &&
 mv "$STATE/.guard-ready.new" "$STATE/guard-ready")
