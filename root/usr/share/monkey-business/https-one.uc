// Child of an owned node/observer group; argv contains only a private request path.
import { privateJson } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { probeHttps } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/https-probe.uc';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
let path = ARGV[0];
if (type(path) != 'string' || match(path, /^\/tmp\/mb-runtime\/(jobs|observer)\/[a-f0-9]{32}\/[a-z0-9-]+\.json$/) == null) exit(1);
let request = privateJson(path, 16384);
if (request == null) exit(1);
print(sprintf('%J', probeHttps(sh, request.diagnostic, request.target, request.directory)));
