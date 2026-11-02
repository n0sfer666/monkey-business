#!/bin/sh
set -eu
timeout 35 python3 test/integ/https_probe.py
