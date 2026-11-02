# Local qualification and NanoPi acceptance / Локальная квалификация и приёмка NanoPi

2026-11-02. Local implementation and security verification are recorded in
[the public security report](security-audit.md). Hardware acceptance remains open;
device smoke tests do not replace full acceptance. Corporate gateway checks were
not performed.

2026-11-02. Результаты локальной реализации и проверки безопасности — в
[публичном отчёте](security-audit.ru.md). Аппаратная приёмка открыта; device
smoke-test её не заменяет. Корпоративные проверки не выполнялись.

## Reproduce locally / Повторить локально

Nushell, repository root / из корня репозитория:

```nu
make lint
make check
make test-unit
make test-integ
make test-rpc
make prepare-native
with-env { MB_TEST_DISK: "/private/tmp/mb-cgroup-vm/disk.img" } { make test-native }
```

Native tests require Apple Silicon macOS, QEMU with HVF and Docker. The preparer
uses public vendor images/binaries and synthetic fixtures only; it verifies the
OpenWrt archive against official SHA256 metadata and writes assets in `/private/tmp`.
Existing disks are retained. The VM opens its disk with `snapshot=on`, uses serial
control, has a 330-second lifetime and is reaped by its supervisor. The fixture
container has its own timeout and unique owner name; cleanup targets only that
container. The existing dev-VM and production router are not accessed.

Native-стенд требует Apple Silicon macOS, QEMU/HVF и Docker. Используются только
публичные образы/бинарники и синтетические данные. Образ OpenWrt сверяется с
официальным SHA256; артефакты лежат в `/private/tmp`. Существующий диск сохраняется,
VM использует `snapshot=on`, serial и лимит 330 секунд. Контейнер fixture имеет
собственный timeout и уникальное имя; очистка адресная. Рабочая dev-VM не затрагивается.

## Evidence / Подтверждённое локально

- OpenWrt 25.12.4, kernel 6.12.87; Xray 26.10.31, Hysteria 2.13.0, curl 8.23.0.
- Real VLESS and Hysteria HTTPS; two-target UDP helper/STUN validation; the actual
  Hysteria dynamic relay rejects non-root injection before its first legitimate
  packet while root VPN and unrelated UDP work.
- Guard and production TPROXY coexist for LAN TLS, UDP and transparent DNS.
  Non-loopback diagnostic ingress is dropped. The snapshot VM's unrelated stock
  fw4 zone table is removed only for its synthetic veth; target fw4 integration
  remains part of hardware acceptance.
- Scoped Apply preserves applied outbound/credentials/DNS/globals; real procd,
  Xray, nft and UCI commit-failure compensation; stale recovery fences; independent
  HTTPS/UDP fallback; cancellation and crashed-node descendant cleanup.
- Concurrent LAN packets during actual external reload, commit-failure rollback and
  transition-release failure: no contacts at the controlled direct receiver.
  A cancelled extra request preserves the previous completed node result/timestamp.
- A complete 50-node supported VLESS scan including extras/cleanup: 16.14 s and
  conservative peak sum RSS 63,856,640 bytes in one native run. This is VM evidence,
  not a NanoPi result; resource limits still require physical measurement.
- Real rpcd/uhttpd read/write ACL checks, API v2/deprecated ping and scoped order.
- Actual routing/corporate/status components tested in light/dark, 390px mobile,
  keyboard focus/Escape, literal hostile labels, and a retained draft after error.
  Backend errors in this component fixture are synthetic; backend behavior is
  checked separately by native RPC/runtime tests.

Прямые публичные проверки: обе HTTPS-цели вернули 204 с валидным TLS; Cloudflare
STUN ответил корректным Binding Success, Twilio дал timeout. Это наблюдение
доступности целей в сети стенда. Частичный UDP-результат не равен отказу VPN.

## Hardware gate / Аппаратные ворота

R2S smoke-test (2026-11-02): ImmortalWrt 25.12.1/kernel 6.12.94, Xray 26.10.31,
Hysteria 2.13.0, curl 8.23.0. Three procd workers, API v2/static UI, router DNS/TLS
HTTPS and a synthetic loopback Hysteria first-packet UDP isolation test passed.
Three fresh HTTPS/UDP-up observer samples and a separate-cgroup synthetic relay test
passed while the live listener identity stayed unchanged. Cleanup/queue release
were verified. This does not qualify LAN routing/flow-offload, cold boot or the
50-node budget. Do not substitute a blanket LAN block for verified scoped protection;
broad network restrictions need separate explicit operator approval.

Ограниченный smoke-test R2S включает loopback UDP isolation, три свежих раунда
HTTPS/UDP up и отдельную тестовую cgroup без смены рабочего listener.
Очистка cgroup и освобождение очереди подтверждены. Общая блокировка LAN не
заменяет проверенную узкую защиту и требует отдельного явного согласования.
Аппаратные проверки ниже этим не заменены.

After separately authorized installation, use synthetic VLESS/Hysteria credentials
and a controlled 50-node scope. Do not use real corporate endpoints for this gate.
Record tree hash, OpenWrt/kernel/package/binary versions, cgroup and nft support.

После отдельно разрешённой установки используйте синтетические credentials и
контролируемые 50 узлов VLESS/Hysteria. Корпоративные шлюзы для этой приёмки не нужны.
Зафиксируйте хеш дерева, версии OpenWrt/ядра/пакетов/движков и поддержку cgroup/nft.

The artifact below starts an active all-node scan. Run it only once that operation
and installation are authorized and the scope contains exactly 50 synthetic nodes.
It reads no UCI/definitions/credentials and emits only aggregate timing/memory/state.

Следующий артефакт запускает активный скан всех узлов. Выполняйте его только после
разрешения установки и проверки, при scope ровно 50 синтетических узлов.
Он не читает UCI/definitions/credentials, выводит только агрегированные измерения.

```nu
scp scripts/nanopi-acceptance.uc root@ROUTER:/tmp/mb-nanopi-acceptance.uc
ssh root@ROUTER 'ucode /tmp/mb-nanopi-acceptance.uc run-synthetic-all' | save --force nanopi-scan-result.json
```

Required observations / Обязательные наблюдения:

1. Full 50-node runs with VPN on and off, mixed VLESS/Hysteria, slow/unreachable
   targets, cancellation and worker restart; cleanup included, ≤240 s and ≤256 MiB
   additional memory. Record baseline, conservative RSS, available memory and kernel
   `memory.peak` if the controller is enabled; do not enable it silently.
2. Real LAN TCP/UDP/DNS/corporate :53, exact-port override, disabled explicit direct,
   wildcard proxy, kill-switch on/off, IPv6 policy and existing target fw4 zones.
3. HTTPS down with UDP up; HTTPS up with UDP down; partial target success; method
   unknown, stale >45 s; two-round confirmation; 60 s return cooldown; precise
   conntrack reset, exact-port exclusions and unrelated flows preserved.
4. Concurrent Apply/Off/WAN change/server subscription refresh, lost RPC response,
   rollback/readonly/full-filesystem faults, daemon restart and cold boot. The
   applied outbound/credentials survive provider edits/removal until explicit change.
5. Non-root TCP and dynamic UDP first-packet injection, non-loopback ingress,
   unrelated local services, occupied diagnostic ports and all process/slot cleanup.
6. UI/API writer vs read-only, reload after API migration, both themes/mobile on
   actual LuCI, and an end-to-end controlled corporate tunnel only after separate
   corporate authorization.

Any confirmed or justified unverified medium/high/critical security risk keeps
acceptance open. There are no silently accepted exceptions. / Подтверждённый либо
обоснованный непроверенный риск medium/high/critical оставляет приёмку открытой;
молчаливого принятия рисков нет.
