// Firewall options follow the applied snapshot, including during routing-only reloads.
import { loadApplied } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/applied.uc';
let key = ARGV[0], fallback = ARGV[1] || '';
if (index(['routing_mode', 'local_region', 'custom_proxy', 'lan_iface', 'tproxy_port', 'kill_switch'], key) < 0) exit(1);
let applied = loadApplied();
if (applied == null) exit(1);
let value = applied.config.global[key];
print(value != null && value != '' ? value : fallback);
