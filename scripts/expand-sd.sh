#!/bin/sh
# expand-sd.sh — grow an SD-card partition on macOS (native tools + e2fsprogs).
#
# Finds the largest partition, verifies a primary ext superblock sits at its
# start, then (on confirmation) grows the partition to the end of the card and
# the filesystem on it (e2fsck -f + resize2fs). If the table start does not
# match the real filesystem location (broken offset) it scans the disk, finds
# the true start and fixes the table. Schemes: MBR and GPT. Filesystems: ext2/3/4
# only (f2fs cannot be grown on macOS). The script installs NOTHING — it only
# checks for tools and tells you what to install.
#
#   sh scripts/expand-sd.sh /dev/disk14
#   MB_START=131072 sh scripts/expand-sd.sh /dev/disk14   # set the start manually
#   MB_SCAN_MB=1024  sh scripts/expand-sd.sh /dev/disk14   # scan window (MB, default 512)
#
# Needs sudo (raw disk reads, table edit, filesystem ops) — will ask for a password.
set -eu

die()  { printf '!! %s\n' "$*" >&2; exit 1; }
note() { printf '>> %s\n' "$*"; }

# --- raw reads and ext superblock detection --------------------------------
# sector_hex DEV SECTOR -> 1024 hex chars (512 bytes of the sector)
sector_hex() { sudo dd if="$1" bs=512 skip="$2" count=1 2>/dev/null | od -An -v -tx1 | tr -d ' \n'; }

# sb_primary_on DEV START -> 0 if a PRIMARY ext superblock sits at START.
# The superblock starts 1024 B in (sector START+2). magic 0xEF53 (LE "53ef") at
# offset 56; s_block_group_nr at offset 90 == 0 only for the primary copy
# (backups have it != 0 — this rejects false hits on backup superblocks).
sb_primary_on() {
	_h=$(sector_hex "$1" $(( $2 + 2 )))
	[ "$(printf '%s' "$_h" | cut -c113-116)" = 53ef ] || return 1
	[ "$(printf '%s' "$_h" | cut -c181-184)" = 0000 ] || return 1
}

# find_primary FROM LIMIT WIN -> prints the first sector holding a primary
# superblock in the window [FROM .. min(FROM+WIN, LIMIT)], step 1 MB (2048 sect).
find_primary() {
	_from=$(( ($1 / 2048) * 2048 )); _end=$(( $1 + $3 ))
	[ "$_end" -gt "$2" ] && _end=$2
	_c=$_from
	while [ "$_c" -le "$_end" ]; do
		if sb_primary_on "$RDISK" "$_c"; then printf '%s\n' "$_c"; return 0; fi
		_c=$(( _c + 2048 ))
	done
	return 1
}

# --- preconditions and arguments -------------------------------------------
[ "$(uname -s)" = Darwin ] || die "скрипт только для macOS"

DEV="${1:-}"
[ -n "$DEV" ] || die "использование: sh scripts/expand-sd.sh /dev/diskN"

ID=$(printf '%s' "$DEV" | sed -E 's#^/dev/(r?)##')
case "$ID" in disk[0-9]*) : ;; *) die "ожидается /dev/diskN, получено: $DEV" ;; esac
case "$ID" in *s[0-9]*) die "укажи всё устройство /dev/diskN, а не раздел" ;; esac
DISK="/dev/$ID"
RDISK="/dev/r$ID"

# --- tool check (no installation) ------------------------------------------
MISSING=0
for t in diskutil fdisk gpt dd od cut; do
	command -v "$t" >/dev/null 2>&1 || { echo "!! нет тулзы: $t" >&2; MISSING=1; }
done
E2DIR=""
for d in /opt/homebrew/opt/e2fsprogs/sbin /usr/local/opt/e2fsprogs/sbin; do
	[ -x "$d/resize2fs" ] && { E2DIR="$d"; break; }
done
if [ -z "$E2DIR" ] && command -v brew >/dev/null 2>&1; then
	p=$(brew --prefix e2fsprogs 2>/dev/null || true)
	[ -n "$p" ] && [ -x "$p/sbin/resize2fs" ] && E2DIR="$p/sbin"
fi
[ -n "$E2DIR" ] || { echo "!! e2fsprogs не найден. Поставь (keg-only):  brew install e2fsprogs" >&2; MISSING=1; }
[ "$MISSING" = 0 ] || die "поставь недостающее и повтори"
E2FSCK="$E2DIR/e2fsck"; RESIZE2FS="$E2DIR/resize2fs"; DUMPE2FS="$E2DIR/dumpe2fs"

[ -e "$DISK" ] || die "устройство $DISK не найдено"

LIST=$(diskutil list "$DISK" 2>/dev/null) || die "diskutil не видит $DISK"
case "$LIST" in
	*GUID_partition_scheme*)  SCHEME=gpt ;;
	*FDisk_partition_scheme*) SCHEME=mbr ;;
	*) die "неизвестная схема разделов (ни MBR, ни GPT)" ;;
esac
note "устройство: $DISK   схема: $SCHEME   (нужен sudo)"

# --- largest partition + growth limit --------------------------------------
if [ "$SCHEME" = mbr ]; then
	FD=$(sudo fdisk "$RDISK") || die "fdisk не прочитал $RDISK"
	LIMIT=$(printf '%s\n' "$FD" | sed -n 's/.*\[\([0-9][0-9]*\) sectors\].*/\1/p' | head -1)
	[ -n "$LIMIT" ] || die "не удалось определить размер диска (fdisk)"
	# shellcheck disable=SC2046
	set -- $(printf '%s\n' "$FD" | tr -d '[]' | awk '
		/^[[:space:]]*[1-4]:[[:space:]]/ && $2!="00" { if ($12+0 > m){ m=$12; pn=$1; ps=$10 } }
		END{ if(m>0){ sub(/:/,"",pn); print pn, ps, m } }')
	NUM="${1:-}"; START="${2:-}"; SIZE="${3:-}"
	[ -n "$NUM" ] || die "не найден ни один раздел в MBR"
else
	GP=$(sudo gpt show "$DISK") || die "gpt не прочитал $DISK"
	# shellcheck disable=SC2046
	set -- $(printf '%s\n' "$GP" | awk '
		$3 ~ /^[0-9]+$/ { if ($2+0 > m){ m=$2; idx=$3; st=$1 } }
		END{ if(m>0) print idx, st, m }')
	NUM="${1:-}"; START="${2:-}"; SIZE="${3:-}"
	[ -n "$NUM" ] || die "не найден ни один раздел в GPT"
	LIMIT=$(printf '%s\n' "$GP" | awk '/Sec GPT table/{print $1; exit}')
	[ -n "$LIMIT" ] || die "не найдена вторичная GPT-таблица"
fi
SLICE="${DISK}s${NUM}"; RSLICE="${RDISK}s${NUM}"
TOKEN="${ID}s${NUM}"
note "самый большой раздел: $SLICE (№$NUM)  старт=$START  размер=$SIZE сект."

# --- find the REAL start (where the primary ext superblock lives) ----------
SCAN_MB="${MB_SCAN_MB:-512}"
if [ -n "${MB_START:-}" ]; then
	GOODSTART="$MB_START"
	sb_primary_on "$RDISK" "$GOODSTART" || die "на заданном MB_START=$GOODSTART нет первичного ext-суперблока"
	note "старт задан вручную: $GOODSTART (первичный суперблок подтверждён)"
elif sb_primary_on "$RDISK" "$START"; then
	GOODSTART="$START"
	note "первичный ext-суперблок на старте $START — ок"
else
	note "на старте раздела ($START) НЕТ первичного ext-суперблока — таблица не соответствует ФС."
	note "сканирую диск на первичный суперблок (окно ${SCAN_MB} МБ, шаг 1 МБ)…"
	GOODSTART=$(find_primary "$START" "$LIMIT" $(( SCAN_MB * 2048 ))) \
		|| die "первичный суперблок не найден в окне. Задай старт вручную: MB_START=<сектор>"
	note "найден реальный старт раздела: $GOODSTART"
fi

MAXSIZE=$(( LIMIT - GOODSTART ))

# table edit needed if the start is wrong OR the partition is not full-card yet
if [ "$START" = "$GOODSTART" ] && [ "$SIZE" -ge $(( MAXSIZE - 2048 )) ]; then
	NEED_EDIT=0
else
	NEED_EDIT=1
fi

# --- plan + confirmation ---------------------------------------------------
note "план:"
note "  раздел:   $SLICE (№$NUM)"
[ "$START" != "$GOODSTART" ] && note "  СТАРТ:    $START -> $GOODSTART  (исправление сбитого offset!)"
note "  старт:    $GOODSTART сект."
note "  размер:   до $MAXSIZE сект. (~$((MAXSIZE/2048)) МБ)"
if [ "$NEED_EDIT" = 0 ]; then
	note "  таблица уже корректна — правка не нужна, только ФС."
fi
diskutil info "$DISK" | grep -E 'Device Location|Removable Media|Media Name|Disk Size' || true

printf '\n!! Бэкап обязателен. При ошибке данные на %s можно потерять.\n' "$TOKEN"
printf 'Для подтверждения введи "%s": ' "$TOKEN"
read -r ans
[ "$ans" = "$TOKEN" ] || die "не подтверждено — выход"

note "размонтирую ${DISK}…"
sudo diskutil unmountDisk "$DISK"

# --- partition table edit --------------------------------------------------
if [ "$NEED_EDIT" = 1 ]; then
	if [ "$SCHEME" = mbr ]; then
		note "правлю MBR (fdisk -e): раздел $NUM -> старт $GOODSTART, размер $MAXSIZE сект…"
		printf 'edit %s\n\n\n%s\n%s\nwrite\ny\nquit\n' "$NUM" "$GOODSTART" "$MAXSIZE" \
			| sudo fdisk -e "$RDISK" || die "fdisk -e не справился"
		note "новая таблица:"; sudo fdisk "$RDISK" | sed -n '/start/,$p'
	else
		note "правлю GPT (recover → remove → add без -s)…"
		sudo gpt recover "$DISK" || true
		sudo gpt remove -i "$NUM" "$DISK" || die "gpt remove не справился"
		sudo gpt add -i "$NUM" -b "$GOODSTART" -t linux "$DISK" || die "gpt add не справился"
		note "новая таблица:"; sudo gpt show "$DISK"
	fi
fi

# --- filesystem: only if the slice node already sees the primary superblock -
if ! sb_primary_on "$RSLICE" 0; then
	note "таблица в порядке, но ядро ещё не перечитало её для $SLICE (узел указывает не туда)."
	note "ИЗВЛЕКИ И ВСТАВЬ карту, затем запусти скрипт снова — он доделает только ФС."
	note "  sudo diskutil eject ${DISK}"
	exit 0
fi

# after the table edit macOS may have re-claimed the disk -> drop the claim,
# otherwise writes to the raw device fail with "unable to set superblock flags".
note "снимаю claim (unmountDisk) перед правкой ФС…"
sudo diskutil unmountDisk "$DISK" >/dev/null 2>&1 || true

# e2fsck codes: 0 clean, 1 fixed, 2 fixed(+reboot) — all success; >2 — failure.
# raw (rdisk) is faster but may reject writes -> fall back to the buffered (disk) node.
FSDEV="$RSLICE"
note "проверяю/чиню ФС (e2fsck -fy) на ${FSDEV}…"
set +e; sudo "$E2FSCK" -fy "$FSDEV"; rc=$?; set -e
if [ "$rc" -gt 2 ]; then
	note "raw (${FSDEV}) не дался на запись (код $rc) — пробую буферизованное ${SLICE}…"
	sudo diskutil unmountDisk "$DISK" >/dev/null 2>&1 || true
	FSDEV="$SLICE"
	set +e; sudo "$E2FSCK" -fy "$FSDEV"; rc=$?; set -e
	[ "$rc" -le 2 ] || die "e2fsck не справился (код $rc) и на $SLICE — проверь, что диск не занят"
fi
note "растягиваю ФС (resize2fs) на ${FSDEV}…"
sudo "$RESIZE2FS" "$FSDEV"

HDR=$(sudo "$DUMPE2FS" -h "$FSDEV" 2>/dev/null)
BC=$(printf '%s\n' "$HDR" | awk -F: '/Block count/{gsub(/ /,"",$2);print $2;exit}')
BS=$(printf '%s\n' "$HDR" | awk -F: '/Block size/{gsub(/ /,"",$2);print $2;exit}')
FS_SECT=$(( BC * BS / 512 ))
note "ФС: $BC блоков × $BS Б = ~$((FS_SECT/2048)) МБ;  цель раздела ~$((MAXSIZE/2048)) МБ"
if [ "$FS_SECT" -lt $(( MAXSIZE - 4096 )) ]; then
	note "ФС НЕ заняла весь раздел — извлеки/вставь карту и запусти скрипт ещё раз."
else
	note "готово: ФС занимает весь раздел."
fi
