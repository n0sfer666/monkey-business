'use strict';
'require baseclass';
'require view.monkey-business.kit.icons as icons';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.pingtext as pingtext';

style.add(
  'pingbar',
  [
    '.mb .mb-ping{display:flex;align-items:center;gap:8px;min-width:0;flex-wrap:wrap}',
    '.mb .mb-ping-bar{flex-shrink:0;width:56px;height:4px;border-radius:2px;overflow:hidden;background:var(--mb-line)}',
    '.mb .mb-ping-bar>div{height:100%;background:var(--mb-ok-text)}',
    '.mb .mb-ping-slow .mb-ping-bar>div{background:var(--mb-warn)}',
    '.mb .mb-ping-ms{font-family:var(--mb-mono)}',
    '.mb .mb-ping-fast .mb-ping-ms{color:var(--mb-ok-text)}',
    '.mb .mb-ping-slow .mb-ping-ms{color:var(--mb-slow)}',
    '.mb .mb-ping-off .mb-tip{color:var(--mb-err)}',
    '.mb .mb-ping-na .mb-tip{color:var(--mb-na)}',
    style.MOBILE +
      '{.mb .mb-ping-bar{display:none}.mb .mb-ping-ms{font-size:13px}.mb .mb-ping .mb-tip svg{width:18px;height:18px}}',
  ].join(''),
);

return baseclass.extend({
  render: function (p) {
    var labels = {
      available: _('Available'),
      degraded: _('Degraded'),
      probe_failed: _('Check failed'),
      checking: _('Checking'),
      unknown: _('Unknown'),
      unsupported: _('Unsupported'),
      config_error: _('Configuration error'),
      engine_error: _('Probe error'),
      cancelled: _('Cancelled'),
      incomplete: _('Incomplete'),
      failed: _('Probe error'),
    };
    var kind = p.kind || 'unknown';
    var tones = {
      available: 'ok',
      degraded: 'warn',
      probe_failed: 'err',
      checking: 'accent',
      config_error: 'err',
      engine_error: 'err',
      failed: 'err',
    };
    var tone = tones[kind] || 'muted';
    var icon = E('span', { 'aria-hidden': 'true' });

    icon.innerHTML =
      kind === 'available' || kind === 'checking'
        ? icons.PULSE
        : kind === 'degraded'
          ? icons.WARN
          : kind === 'probe_failed'
            ? icons.WIFI_OFF
            : tone === 'err'
              ? icons.WARN
              : icons.NA;
    var description = (labels[kind] || labels.unknown) + (p.ms == null ? '' : ' · ' + pingtext.ms(p.ms));

    if (p.attempts) description += ' · ' + p.successes + '/' + p.attempts;
    var udpLabels = {
      up: _('available'),
      down: _('no response'),
      unknown: _('unknown'),
      available: _('available'),
      failed: _('no response'),
      success: _('available'),
    };
    var details = [];

    if (p.udp) details.push('UDP: ' + (udpLabels[p.udp.state] || _('unknown')));
    if (p.age != null) details.push(Math.floor(p.age) + 's');

    return E(
      'span',
      {
        class: 'mb-ping',
        style: 'color:var(--mb-' + tone + (tone === 'muted' ? '' : '-text') + ')',
        title: description + ' · ' + details.join(' · '),
        role: 'status',
      },
      [
        icon,
        E('span', { style: 'white-space:normal;overflow-wrap:anywhere' }, [description]),
        E('small', { class: 'mb-muted', style: 'white-space:normal' }, [details.join(' · ')]),
      ],
    );
  },
});
