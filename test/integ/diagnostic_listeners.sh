#!/bin/sh
set -eu
timeout 20 python3 test/integ/diagnostic_listeners.py
