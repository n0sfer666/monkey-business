import { privateJson } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { probeExit } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/exit-probe.uc';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
let path = ARGV[0] || '';
if (match(path, /^\/tmp\/mb-runtime\/leak\/[a-f0-9]{32}\/(direct|proxy).json$/) == null) exit(1);
let request = privateJson(path, 4096);
if (request == null) exit(1);
print(sprintf('%J', probeExit(sh, request.proxy, null, request.directory)));
