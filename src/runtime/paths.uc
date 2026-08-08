// Пути и имена, общие для рантайм-модулей rpcd-плагина. Одно место, потому что расхождение
// (например, xray.json тут и там) снаружи выглядит как «конфиг применился, но ничего не изменилось».

const CONFIG = 'monkey-business';
const CONF_DIR = '/etc/monkey-business';
const XRAY_CONF = CONF_DIR + '/xray.json';
const GEO_DIR = '/usr/share/xray';
const GEO_SCRIPT = '/usr/share/monkey-business/geo.sh';
const WD_STATE = '/tmp/mb-watchdog/state';
// Активный сервер — рантайм-состояние, а не выбор пользователя (выбора в UI нет, приоритет задаётся
// порядком секций). Раньше он лежал в uci.selected.server, и КАЖДЫЙ автофейловер делал commit,
// переписывая /etc/config/monkey-business целиком; в застрявшем цикле — раз в BACKOFF, круглые
// сутки. Теперь это один файл рядом с xray.json, и пишется он только при РЕАЛЬНОЙ смене тега.
const ACTIVE_FILE = CONF_DIR + '/active';

export { CONFIG, CONF_DIR, XRAY_CONF, GEO_DIR, GEO_SCRIPT, WD_STATE, ACTIVE_FILE };
