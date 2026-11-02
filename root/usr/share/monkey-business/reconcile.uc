import * as uci from 'uci';
import { reconcile } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/reconcile.uc';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { privateDirectory } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
if (!privateDirectory('/tmp/mb-runtime') || !privateDirectory('/tmp/mb-runtime/uci')) { warn('startup reconciliation: unsafe_runtime_directory\n'); exit(1); }
let error = reconcile(sh, uci.cursor('/etc/config', '/tmp/mb-runtime/uci'), getenv('MB_EXTERNAL_LOCKED') == '1');
if (error != null) { warn('startup reconciliation: ' + error + '\n'); exit(1); }
