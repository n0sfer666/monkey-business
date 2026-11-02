#!/bin/sh
# procd and scan worker use the same pre-listener isolation boundary.
set -eu
[ "$(cat /tmp/mb-runtime/guard-ready 2>/dev/null)" = cgroup-v2-socket-v1 ] || exit 1
nft list chain inet monkey_business_diagnostics input 2>/dev/null | grep -q 'socket cgroupv2' || exit 1
# Per-job launch joins a validated cgroup in ucode before reaching this wrapper.
# Live engines use a separate leaf; children inherit membership before opening ports.
if [ "${MB_ENGINE_JOINED:-0}" != 1 ]; then
 mkdir -p /sys/fs/cgroup/monkey-business-engines/live
 ucode -e '
 let fs = require("fs"), pid = ARGV[0];
 let file = fs.open("/sys/fs/cgroup/monkey-business-engines/live/cgroup.procs", "w");
 if (file == null) { warn(fs.error()); exit(1); }
 let written = file.write(pid + "\n"), closed = file.close();
 if (written != length(pid) + 1 || !closed) { warn("live cgroup join: " + fs.error() + "\n"); exit(1); }
 ' "$$" || exit 1
fi
grep -q '^0::/monkey-business-engines/' /proc/self/cgroup || exit 1
exec "$@"
