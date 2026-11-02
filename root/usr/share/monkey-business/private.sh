#!/bin/sh
# shellcheck shell=sh
# Caller supplies its own installed script directory, never a remote-supplied path.
mb_private_dir() { ucode "$MB_PRIVATE_LIB/private-state.uc" dir "$1"; }
mb_private_file() { ucode "$MB_PRIVATE_LIB/private-state.uc" check "$1"; }
mb_state_write() { printf '%s' "$2" | ucode "$MB_PRIVATE_LIB/private-state.uc" write "$1"; }
