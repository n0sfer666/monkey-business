// Мелкие строковые помощники парсеров. Отдельный модуль, потому что нужны и subscription.uc, и
// нормализаторам протоколов, которые subscription.uc импортирует, — иначе вышел бы цикл импортов.

function truncate(s, n) {
	n = n || 40;
	return (length(s) > n) ? (substr(s, 0, n) + "...") : s;
}

export { truncate };
