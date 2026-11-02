#!/bin/sh
# Compatibility entry point for stale cron entries. The sole observer/recovery
# executor is procd-managed; invoking this file never starts another probe loop.
exec /etc/init.d/monkey-business-observer running
