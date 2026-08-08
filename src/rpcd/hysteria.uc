// Подготовка hysteria-процесса под выбранный сервер. Отдельный модуль, потому что это своя
// ответственность (файл конфига + бинарь), а handlers.uc и так на пределе.
//
// Контракт ctx (рантайм — root/usr/share/rpcd/ucode/monkey-business.uc):
//   hysteriaInstalled() -> bool        applyHysteria(jsonStr|null) -> errString|null
//   hysteriaStatus() -> { installed, version, state, ... }   hysteriaInstall() -> { ok, detail }

import { isHysteria, hysteriaConfigJson } from "../generator/hysteria.uc";

// Вызывать ДО applyConfig: xray-аутбаунд смотрит в локальный socks hysteria, и конфиг клиента должен
// лежать на месте к моменту reload'а — init поднимает оба процесса одним разом.
// Сервер не hysteria -> конфиг снимается, иначе после переключения на vless остался бы висеть
// лишний процесс, который долбится в старый сервер.
function prepareHysteria(ctx, server) {
	if (ctx.applyHysteria == null)
		return isHysteria(server) ? "hysteria is not supported by this runtime" : null;
	if (!isHysteria(server))
		return ctx.applyHysteria(null);
	// Без бинаря отказываемся ЯВНО, а не молча уходим в vless-путь: иначе xray поднялся бы с
	// аутбаундом в пустой socks-порт, и весь трафик уткнулся бы в отказ соединения при живом
	// kill-switch — снаружи это неотличимо от «интернет пропал».
	if (!ctx.hysteriaInstalled())
		return "hysteria is not installed — install the client on the dashboard first";
	return ctx.applyHysteria(hysteriaConfigJson(server));
}

function hysteriaStatus(ctx) {
	if (ctx.hysteriaStatus == null)
		return { installed: false, state: "unsupported" };
	return ctx.hysteriaStatus();
}

function hysteriaInstall(ctx) {
	if (ctx.hysteriaInstall == null)
		return { error: "hysteria is not supported by this runtime" };
	return ctx.hysteriaInstall();
}

export { prepareHysteria, hysteriaStatus, hysteriaInstall };
