#!/bin/sh
# Разовый захват реального ответа VPNON для мок-фикстуры (этап 3).
#
# BLOCKED в автономном режиме: подписка содержит СЕКРЕТНЫЙ ТОКЕН (email+ts) и боевые
# UUID/ключи Reality. Запускать вручную; сырой ответ сохраняется ВНЕ репозитория.
# Перед использованием как фикстуры — санитизировать секреты (UUID/pbk/sid → синтетические).
#
# usage: scripts/capture-sub.sh <subscription-url>
set -eu

URL="${1:-}"
[ -n "$URL" ] || { echo "usage: $0 <subscription-url>" >&2; exit 2; }

OUT="${MB_CAPTURE_OUT:-/tmp/vpnon-sub.raw}"

command -v curl >/dev/null 2>&1 || { echo "curl required" >&2; exit 1; }

echo ">> fetching subscription (token NOT logged)"
curl -fsSL "$URL" >"$OUT"
bytes=$(wc -c <"$OUT")
echo ">> saved $bytes bytes to $OUT (OUTSIDE repo)"

cat <<'EOF'

Дальше ВРУЧНУЮ:
  1) Если ответ base64 — раскодировать.
  2) Заменить в каждом vless://-URI боевые секреты на синтетические:
       UUID -> 11111111-2222-3333-4444-555555555555
       pbk  -> PUBKEYA   sid -> ab12
     (host/port/sni/type/path можно оставить — это не секреты).
  3) Сохранить как test/fixtures/sub_vpnon_sanitized.txt и только тогда коммитить.

НИКОГДА не коммитить файл с боевым токеном/UUID/ключами.
EOF
