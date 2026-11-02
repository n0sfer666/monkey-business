'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.kit.notify as notice';

return baseclass.extend({
  render: function (initial) {
    if (!initial || initial.error) return E('p', {}, [_('Availability settings unavailable')]);
    var revision = initial.revision;
    var fields = initial.targets.map(function (target, index) {
      return {
        url: E('input', {
          type: 'url',
          value: target.url,
          maxlength: 1024,
          'aria-label': _('HTTPS target') + ' ' + (index + 1),
        }),
        code: E(
          'select',
          { 'aria-label': _('Expected status') + ' ' + (index + 1) },
          [200, 204].map(function (code) {
            return E('option', { value: code, selected: code === target.expected_status ? '' : null }, [String(code)]);
          }),
        ),
      };
    });
    var apply = E(
      'button',
      {
        class: 'mb-btn',
        click: function () {
          apply.disabled = true;
          var targets = fields.map(function (field) {
            return { url: field.url.value, expected_status: Number(field.code.value) };
          });

          api
            .availabilitySettingsApply(revision, targets)
            .then(function (result) {
              if (result.error) {
                notice.show(result.error, 'warning');

                return;
              }
              revision = result.revision;
              notice.show(_('Availability targets saved.'), 'info');
            })
            .catch(notice.fail(_('Save failed: ')))
            .finally(function () {
              apply.disabled = false;
            });
        },
      },
      [_('Apply availability targets')],
    );

    return E(
      'section',
      { class: 'mb-panel' },
      [
        E('h3', {}, [_('HTTPS availability targets')]),
        E('p', {}, [
          _(
            'Two distinct hosts. TLS verification is required; redirects are rejected. Applies only to availability checks.',
          ),
        ]),
      ].concat(
        fields.map(function (field) {
          return E('div', {}, [field.url, field.code]);
        }),
        [apply],
      ),
    );
  },
});
