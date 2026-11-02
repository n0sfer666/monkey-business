# Changelog

[Русский](CHANGELOG.ru.md)

## 0.2.0 — 2026-11-02

- Add LAN-only corporate IPv4/port routing with independent HTTPS/UDP fallback,
  exact-port precedence, return cooldown and precise connection resets.
- Retain the actual applied VPN outbound during scoped routing changes; add
  revisioned routing, server-order and diagnostic-settings Apply operations.
- Add asynchronous HTTPS/STUN availability jobs, typed server references,
  bounded completed-result caching and group-preserving manual ranking.
- Replace cron VPN monitoring with one procd health observer and fenced recovery;
  isolate diagnostics with authenticated listeners, cgroup v2 and nft socket guards.
- Restrict read-only RPC access, retire executable watchdog state and harden
  downloads, temporary files, process cleanup and device deployment.
- Include the compact Dashboard/Servers/Settings UI and multi-subscription work
  previously developed on the local development branch.
- Migrate ping consumers to API v2 and document the required page reload,
  dependencies, EN/RU user flows, security verification and rollback preparation.

This is a source release. The OpenWrt SDK package target remains unimplemented.
Physical 50-node resource limits, controlled LAN/flow-offload, cold boot and complete
installed LuCI acceptance remain open. See [security verification](docs/security-audit.md)
and the [acceptance procedure](docs/routing-availability-acceptance.md).
