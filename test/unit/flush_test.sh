#!/bin/sh
set -eu
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/nft" <<'STUB'
#!/bin/sh
if [ "$1" = list ]; then
 [ ! -f "$STATE/present" ] || echo 'table inet monkey_business'
 exit 0
fi
[ ! -f "$STATE/fail" ] || exit 1
rm -f "$STATE/present"
STUB
printf '#!/bin/sh\nexit 0\n' > "$T/ip"
chmod 700 "$T/nft" "$T/ip"
export STATE="$T" PATH="$T:$PATH"
sh scripts/firewall/flush.sh >/dev/null
touch "$T/present" "$T/fail"
if sh scripts/firewall/flush.sh >/dev/null 2>&1; then echo 'masked nft cleanup failure'; exit 1; fi
rm "$T/fail"
sh scripts/firewall/flush.sh >/dev/null
[ ! -f "$T/present" ]
echo 'PASS: absent table is idempotent; real deletion error is propagated'
