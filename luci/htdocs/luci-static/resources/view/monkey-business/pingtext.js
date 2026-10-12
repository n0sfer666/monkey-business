'use strict';
'require baseclass';

function msText(ms) {
  return ms + '\u00a0ms';
}

function text(ms, na, autoOff) {
  if (na) return _('n/a');
  if (ms != null) return msText(ms) + (autoOff ? ' · ' + _('auto-off') : '');

  return autoOff ? _('down · auto-off') : '—';
}

function results(res) {
  if (res && res.results) return res.results;

  return res && res.id != null ? [res] : [];
}

return baseclass.extend({
  ms: msText,
  text: text,
  results: results,
});
