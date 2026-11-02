'use strict';
'require baseclass';
'require dom';
'require view.monkey-business.model.rulemsg as msg';

var seq = 0;

return baseclass.extend({
  render: function (defs) {
    var id = 'mb-cr-errs-' + ++seq;
    var titles = {};
    var title = E('div', { class: 'mb-cr-etitle' });
    var rows = E('div', { class: 'mb-cr-erows' });
    var node = E('div', { class: 'mb-cr-errs', id: id, role: 'status', 'aria-live': 'polite', hidden: '' }, [
      title,
      rows,
    ]);

    defs.forEach(function (d) {
      titles[d.key] = d.title;
    });

    function row(i, line) {
      return E('div', { class: 'mb-cr-erow', 'data-list': i.list }, [
        E('div', { class: 'mb-cr-eline' }, [
          E('span', { class: 'mb-cr-where' }, [
            E('span', { class: 'mb-cr-wd' }, [_('%s · line %d').format(titles[i.list], i.line)]),
            E('span', { class: 'mb-cr-wm' }, [_('Line %d').format(i.line) + ' · ']),
          ]),
          E('code', {}, [String(line || '').trim()]),
        ]),
        E('span', { class: 'mb-cr-msg' }, [msg.text(i)]),
      ]);
    }

    return {
      id: id,
      node: node,
      update: function (items, lineOf, tabok) {
        node.hidden = items.length === 0;
        node.classList.toggle('mb-cr-tabok', tabok);
        title.textContent = msg.fixing(items.length) + ' — ' + _('nothing is saved until then');
        dom.content(
          rows,
          items.map(function (i) {
            return row(i, lineOf(i));
          }),
        );
      },
    };
  },
});
