#!/bin/sh
set -eu
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/nft" <<'STUB'
#!/bin/sh
cat >/dev/null
exit "${NFT_FAIL:-0}"
STUB
cat > "$T/ip" <<'STUB'
#!/bin/sh
exit "${IP_FAIL:-0}"
STUB
chmod 700 "$T/nft" "$T/ip"
export PATH="$T:$PATH" MB_DIRECT_BYPASS=0 MB_CORPORATE_SETS="$T/missing"
if NFT_FAIL=7 sh scripts/firewall/apply.sh > "$T/out" 2>&1; then echo 'nft failure masked'; exit 1; fi
if NFT_FAIL=0 IP_FAIL=1 sh scripts/firewall/apply.sh > "$T/out" 2>&1; then echo 'policy-route failure masked'; exit 1; fi
NFT_FAIL=0 IP_FAIL=0 sh scripts/firewall/apply.sh >/dev/null
echo 'PASS: main nft and policy-route installation failures cannot claim successful Apply'
