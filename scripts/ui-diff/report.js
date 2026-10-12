const fs = require('fs');
const path = require('path');

const PAIRS_SHOWN = 40;

function cell(v) {
  return String(v === null || v === undefined || v === '' ? '—' : v)
    .replace(/</g, '&lt;')
    .replace(/\|/g, '\\|')
    .replace(/\n/g, ' ');
}

function row(values) {
  return '| ' + values.map(cell).join(' | ') + ' |';
}

function table(head, rows) {
  if (!rows.length) return ['нет', ''];

  return [row(head), row(head.map(() => '---')), ...rows.map(row), ''];
}

function label(e, containers) {
  const where = e.cid >= 0 ? containers[e.cid] + ' › ' : '';

  return `${where}${e.role} «${(e.key || e.text || '').slice(0, 60)}»`;
}

function geometry(e) {
  return `${e.x},${e.y} ${e.w}×${e.h}`;
}

function findings(rows, board, impl, loose) {
  const groups = new Map();

  for (const f of rows) {
    const what =
      f.b !== undefined ? label(board.elements[f.b], board.containers) : label(impl.elements[f.i], impl.containers);
    const key = [what, f.prop, f.expected, loose ? '' : f.actual].join('\u0000');
    const g = groups.get(key);

    if (g) g[4]++;
    else groups.set(key, [what, f.prop, f.expected, f.actual, 1]);
  }

  return [...groups.values()].map((g) => [g[0], g[1], g[2], loose && g[4] > 1 ? g[3] + ' …' : g[3], g[4]]);
}

function summary(r) {
  const via = r.matched.pairs.reduce((a, p) => (a[p.via]++, a), { text: 0, order: 0 });
  const c = r.cmp;

  return [
    `сопоставлено ${r.matched.pairs.length} (текст+роль ${via.text}, порядок ${via.order})`,
    `нет в реализации ${r.matched.missing.length}`,
    `лишних ${r.matched.extra.length}`,
    `стиль ${c.style.length}`,
    `тексты ${c.text.length}`,
    `данные ${c.data.length}`,
    `контраст ${c.contrast.length}`,
    r.pix ? `diff-регионов ${r.pix.regions.length}` : 'pixel diff не делался (светлая тема)',
    `console ${r.log.console.length}`,
  ].join(' · ');
}

function markdown(r) {
  const { meta, board, impl, matched, cmp, pix, log, files } = r;
  const B = board.elements,
    I = impl.elements;
  const pairDiffs = pix
    ? matched.pairs
        .map((p, k) => Object.assign({ p }, pix.pairs[k] || { px: 0 }))
        .filter((x) => x.px >= meta.minPx)
        .sort((a, b) => b.px - a.px)
    : [];

  return [
    `# ${meta.board} ${meta.width} · ${meta.theme} · ${meta.engine}`,
    '',
    `Экран \`${meta.page}\` · борд \`${meta.board}\` ${JSON.stringify(meta.props)} · ${meta.date} · загрузка ${JSON.stringify(meta.load)}`,
    `Кадр: борд ${board.box.width}×${board.box.height}, реализация ${impl.box.width}×${impl.box.height}`,
    '',
    `**Сводка:** ${summary(r)}`,
    '',
    '## Console (blocker)',
    '',
    ...(log.console.length ? log.console.map((l) => '- ' + l) : ['нет']),
    '',
    '## Нет в реализации (major)',
    '',
    ...table(
      ['элемент борда', 'геометрия'],
      matched.missing.map((k) => [label(B[k], board.containers), geometry(B[k])]),
    ),
    '## Лишнее в реализации (major)',
    '',
    ...table(
      ['элемент реализации', 'геометрия'],
      matched.extra.map((k) => [label(I[k], impl.containers), geometry(I[k])]),
    ),
    '## Стиль и геометрия (minor, допуск ±2px)',
    '',
    ...table(['элемент', 'свойство', 'борд', 'реализация', 'раз'], findings(cmp.style, board, impl)),
    '## Тексты не дословно (minor)',
    '',
    ...table(['элемент', 'свойство', 'борд', 'реализация (пример)', 'раз'], findings(cmp.text, board, impl, true)),
    '## Различия данных (разобрать: данные или текст)',
    '',
    ...table(['элемент', 'свойство', 'борд', 'реализация', 'раз'], findings(cmp.data, board, impl)),
    '## Контраст (minor, А.5)',
    '',
    ...table(['элемент', 'свойство', 'нужно', 'есть', 'раз'], findings(cmp.contrast, board, impl)),
    '## Pixel diff',
    '',
    ...(pix
      ? [
          `Порог ${meta.threshold} (YIQ), клетка ${meta.cell}px, регион от ${meta.minPx}px. Отличается ${pix.total} px из ${pix.width}×${pix.height}.`,
          '',
          ...table(
            ['#', 'x,y', 'w×h', 'px'],
            pix.regions.map((g) => [g.n, `${g.x},${g.y}`, `${g.w}×${g.h}`, g.px]),
          ),
          `### Пары элементов с пиксельной разницей (топ ${PAIRS_SHOWN})`,
          '',
          ...table(
            ['элемент', 'сопоставлен', 'px', '%'],
            pairDiffs.slice(0, PAIRS_SHOWN).map((x) => [label(B[x.p.b], board.containers), x.p.via, x.px, x.ratio]),
          ),
        ]
      : ['не делался: светлых бордов нет (А.5)', '']),
    '## Снимки',
    '',
    ...Object.entries(files).map(([k, f]) => `- ${k}: \`${f}\``),
    '',
    ...(log.network.length ? ['## Сеть', '', ...log.network.map((l) => '- ' + l), ''] : []),
  ].join('\n');
}

function write(dir, stem, r) {
  fs.writeFileSync(path.join(dir, stem + '.md'), markdown(r));
  const { meta, board, impl, matched, cmp, log } = r;
  const pix = r.pix ? { total: r.pix.total, regions: r.pix.regions, pairs: r.pix.pairs } : null;

  fs.writeFileSync(
    path.join(dir, stem + '.json'),
    JSON.stringify({ meta, board, impl, matched, cmp, pix, log }, null, 1),
  );

  return { stem, summary: summary(r) };
}

function index(dir, runs) {
  const lines = ['# ui-diff', '', ...runs.map((x) => `- [${x.stem}](${x.stem}.md) — ${x.summary}`), ''];

  fs.writeFileSync(path.join(dir, 'index.md'), lines.join('\n'));
}

module.exports = { write, index };
