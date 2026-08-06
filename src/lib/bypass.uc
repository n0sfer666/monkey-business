// Ядерный обход (nft-сеты mb_ru4/mb_ru6) — производная режима, а не отдельный тумблер: RU-CIDR
// минуют туннель в ядре только там, где регион гонит в direct и сам xray (bypass-local), и только
// для RU (сеты наполняются ru.txt). Лежит в lib/, потому что читают его обе стороны: status (UI)
// и setMode (мутация). Для файрвола тот же расчёт делает mb_direct_bypass() в
// root/etc/init.d/monkey-business — он и передаёт MB_DIRECT_BYPASS в apply.sh.

function directBypass(g) {
	return (g.routing_mode || "bypass-local") == "bypass-local" && (g.local_region || "ru") == "ru";
}

export { directBypass };
