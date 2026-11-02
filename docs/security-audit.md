# Security verification and release limits

[Русский](security-audit.ru.md)

The routing and availability update was reviewed across the application, including
existing security defects. This report describes tested boundaries; it is not a
claim that the software is free of vulnerabilities.

## Changes

- Routing-only Apply retains the actual applied outbound and credentials. Revision,
  runtime, network and intent fences reject stale mutations and recovery actions.
- A scoped transition guard protects corporate proxy destinations while Xray and
  nft state change. Compensation and request-result persistence are tested together.
- One observer supplies independent HTTPS and UDP health to routing and recovery.
  Unfinished manual scans cannot replace a completed result or refresh its timestamp.
- Authenticated diagnostic listeners force the selected VPN path. Root-owned cgroup
  v2 and nft socket rules isolate dynamic UDP relays before their first packet.
- Reader RPC permissions expose safe DTOs; UCI editing, jobs, uploads and mutations
  require write permission. Legacy ping calls explicitly return API v2 deprecation.
- Runtime state, locks, logs and temporary credentials use protected directories.
  Executable legacy watchdog state was retired. Download/install paths enforce TLS,
  size/time limits, complete transfers and validation of the bytes being installed.
- Deployment checks SSH host keys, preserves the existing UCI file and supports
  BusyBox tar through an exclusion file rather than GNU-only long options.

## Evidence

The required `make lint`, `make check` and `make test-unit` checks passed. Additional
integration tests cover real Xray configuration, TPROXY/DNS, diagnostic isolation,
kill-switch behavior and transition/rollback faults. Native OpenWrt rpcd/uhttpd tests
cover reader/writer ACLs, API v2 and scoped order idempotency.

Disposable native OpenWrt tests exercise real procd/Xray/Hysteria/nft/UCI,
concurrent LAN requests during reload and failed Apply, stale recovery decisions,
cancellation, node-process crashes and owned-process cleanup. A 50-node VLESS run
including extra probes and cleanup completed in 16.14 seconds with a conservative
peak sum RSS of 63,856,640 bytes **in a VM**.

On an R2S, three fresh observer samples reported HTTPS and UDP up. A separate-cgroup
synthetic loopback test blocked non-root Hysteria relay injection while preserving
root replies, unrelated UDP and the running VPN listener. Test processes, groups
and queue locks were cleaned up. No real corporate gateway checks were performed.

Qualified local versions include OpenWrt 25.12.4/kernel 6.12.87, Xray 26.10.31,
Hysteria 2.13.0 and curl 8.23.0. Device smoke tests also covered ImmortalWrt
25.12.1/kernel 6.12.94. Qualification applies to the tested builds, not arbitrary
future package versions.

## Open acceptance gates

Physical 50-node timing/memory limits, controlled LAN packet paths and flow-offload,
cold boot, fault recovery and complete installed LuCI QA remain open. VM measurements
and a working observer do not close these gates. Updating a running VPN while
preserving every required proxy path has not been qualified.

Do not introduce a blanket LAN block as a substitute for a verified scoped guard.
Prepare a private backup and a tested rollback before device installation. Broad
network restrictions need separate explicit operator approval.

See [the acceptance procedure](routing-availability-acceptance.md) for reproducible
checks and remaining hardware requirements. Packaging through the OpenWrt SDK is
still not implemented; a source tag does not imply a distributable package.
