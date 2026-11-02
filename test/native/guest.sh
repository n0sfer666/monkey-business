#!/bin/sh
set -eu
ip link set eth0 nomaster
ip addr flush dev eth0
ip addr add 10.0.2.15/24 dev eth0
ip link set eth0 up
ip route replace default via 10.0.2.2
printf 'nameserver 1.1.1.1\n' > /tmp/resolv.conf
wget -q -T 15 -O /tmp/mb-native.tgz http://10.0.2.2:18981/project.tgz
tar -C /tmp -xzf /tmp/mb-native.tgz
mkdir -p /usr/share/rpcd/ucode/lib /usr/share/monkey-business
touch /etc/config/monkey-business
chmod 600 /etc/config/monkey-business
ln -s /tmp/mb-native/src /usr/share/rpcd/ucode/lib/monkey-business
cp -R /tmp/mb-native/root/usr/share/monkey-business/* /usr/share/monkey-business/
chmod 755 /usr/share/monkey-business/*.sh
for binary in xray hysteria; do
 wget -q -T 15 -O "/usr/bin/$binary" "http://10.0.2.2:18981/$binary"
 chmod 755 "/usr/bin/$binary"
done
# Signed OpenWrt APK metadata/packages are relayed through the host because the
# sandboxed QEMU network cannot reliably connect to public HTTPS endpoints.
sed -i 's#https://downloads.openwrt.org/#http://10.0.2.2:18981/openwrt/#g' /etc/apk/repositories.d/*.list
apk update >/tmp/mb-apk.log 2>&1 || cat /tmp/mb-apk.log
apk add curl coreutils-timeout conntrack ucode-mod-socket kmod-nft-socket kmod-nft-tproxy ip-full kmod-veth >>/tmp/mb-apk.log 2>&1 || { cat /tmp/mb-apk.log; exit 1; }
wget -q -T 15 -O /tmp/mb-fixture-ca.pem http://10.0.2.2:18981/fixture-ca.pem
wget -q -T 15 -O /tmp/mb-relay-client http://10.0.2.2:18981/relay-client
chmod 700 /tmp/mb-relay-client
export CURL_CA_BUNDLE=/tmp/mb-fixture-ca.pem
sh /usr/share/monkey-business/diagnostic-guard.sh
mkdir -p /usr/share/monkey-business/firewall /usr/share/xray
cp /tmp/mb-native/scripts/firewall/*.sh /usr/share/monkey-business/firewall/
cp /tmp/mb-native/root/etc/init.d/monkey-business /etc/init.d/monkey-business
chmod 755 /etc/init.d/monkey-business
for database in geoip geosite; do
 wget -q -T 15 -O "/usr/share/xray/$database.dat" "http://10.0.2.2:18981/$database-native.dat"
done
if [ "${MB_TEST_CASE:-all}" = all ]; then
 ucode /tmp/mb-native/test/native/worker.uc
 ucode /tmp/mb-native/test/native/observer.uc
fi
if [ "${MB_TEST_CASE:-all}" != apply ]; then sh /tmp/mb-native/test/native/guard.sh; fi
if [ "${MB_TEST_CASE:-all}" != guard ]; then sh /tmp/mb-native/test/native/apply-lan.sh; sh /tmp/mb-native/test/native/lan.sh; fi
