#!/usr/bin/env python3
"""Public, synthetic assets only. Never reads the user's existing VM or credentials."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    assets = Path(os.environ.get('MB_TEST_ASSETS', '/private/tmp/mb-cgroup-vm/assets')).resolve()
    assets.mkdir(parents=True, exist_ok=True)
    image = 'monkey-business-integ'
    subprocess.run(['sh', str(ROOT / 'scripts/docker-image.sh'), image, 'Dockerfile.integ'], cwd=ROOT, check=True, timeout=240)
    subprocess.run(['docker', 'run', '--rm', '--label', 'monkey-business.check=1', '-v', str(assets) + ':/assets',
                    image, 'timeout', '10', 'sh', '-ec', 'test "$(uname -m)" = aarch64; cp /usr/local/bin/xray /usr/local/bin/hysteria /assets/'], check=True, timeout=15)
    subprocess.run(['docker', 'run', '--rm', '--label', 'monkey-business.check=1', '-v', str(assets) + ':/assets',
                    '-v', str(ROOT / 'test/integ/cgroup_relay_client.c') + ':/fixture.c:ro',
                    'alpine:edge', 'timeout', '90', 'sh', '-ec',
                    'apk add --no-cache gcc musl-dev >/dev/null; cc -static -O2 -Wall -Wextra -o /assets/relay-client /fixture.c'], check=True, timeout=100)
    cidr = b'\x0a\x04\x0a\x00\x00\x00\x10\x08'
    entry = b'\x0a\x07PRIVATE' + b'\x12' + bytes([len(cidr)]) + cidr
    (assets / 'geoip-native.dat').write_bytes(b'\x0a' + bytes([len(entry)]) + entry)
    entry = b'\x0a\x07PRIVATE'
    (assets / 'geosite-native.dat').write_bytes(b'\x0a' + bytes([len(entry)]) + entry)
    hashes = {name: hashlib.sha256((assets / name).read_bytes()).hexdigest()
              for name in ['xray', 'hysteria', 'relay-client', 'geoip-native.dat', 'geosite-native.dat']}
    (assets / 'asset-sha256.json').write_text(json.dumps(hashes, indent=2) + '\n')
    disk = Path(os.environ.get('MB_TEST_DISK', str(assets.parent / 'disk.img'))).resolve()
    if not disk.exists():
        name = 'openwrt-25.12.4-armsr-armv8-generic-ext4-combined.img.gz'
        base = 'https://downloads.openwrt.org/releases/25.12.4/targets/armsr/armv8/'
        for filename in ['sha256sums', name]:
            subprocess.run(['docker', 'run', '--rm', '--label', 'monkey-business.check=1',
                            '-v', str(assets) + ':/assets', image, 'timeout', '95', 'curl', '--disable', '-fsSL',
                            '--proto', '=https', '--max-time', '90', '--max-filesize', '134217728',
                            '-o', '/assets/' + filename, base + filename], check=True, timeout=100)
        expected = [line.split()[0] for line in (assets / 'sha256sums').read_text().splitlines() if line.split()[-1].lstrip('*') == name]
        archive = assets / name
        if len(expected) != 1 or hashlib.sha256(archive.read_bytes()).hexdigest() != expected[0]:
            raise RuntimeError('Official image SHA256 mismatch')
        disk.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(archive, 'rb') as source, disk.open('xb') as target:
            shutil.copyfileobj(source, target)
    print('Prepared synthetic assets. Disk is always opened with snapshot=on: ' + str(disk))
    return 0


if __name__ == '__main__':
    sys.exit(main())
