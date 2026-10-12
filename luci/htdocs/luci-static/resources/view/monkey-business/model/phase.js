'use strict';
'require baseclass';

function connected(st, line) {
  return { title: _('Connected'), sub: line || st.server || '', dot: 'ok' };
}

function info(st, line) {
  if (!st.enabled && st.running)
    return {
      title: _('Off — tunnel still up'),
      dot: 'warn',
      sub: _(
        'The toggle is off, but xray and the kill-switch are still up. Press Turn on to finish enabling, then Turn off to tear it down.',
      ),
    };
  if (!st.enabled) return { title: _('Off'), sub: _('VPN is not running'), dot: 'off' };
  if (st.running) return connected(st, line);
  if (st.wd_phase === 'down')
    return {
      title: _('Disabled by watchdog'),
      dot: 'err',
      sub: _('No working server found — traffic goes directly, WITHOUT VPN.'),
    };
  if (st.wd_phase === 'reconnecting')
    return {
      title: _('Reconnecting…'),
      dot: 'warn',
      sub: _('The tunnel dropped, the watchdog is reconnecting. Kill-switch is still held.'),
    };

  return { title: _('Starting…'), sub: '', dot: 'warn' };
}

return baseclass.extend({
  info: info,
});
