#!/usr/bin/env python3
"""Native OpenWrt RPC checks with a bounded, automatically removed container."""
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parent.parent
IMAGE = 'monkey-business-rpc'


def main():
    present = subprocess.run(['docker', 'image', 'inspect', IMAGE], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, timeout=10).returncode == 0
    if not present:
        with (ROOT / 'Dockerfile.rpc').open('rb') as dockerfile:
            subprocess.run(['docker', 'build', '-t', IMAGE, '-'], stdin=dockerfile, check=True,
                           cwd=ROOT, timeout=180)
    name = 'mb-rpc-' + uuid.uuid4().hex[:16]
    try:
        result = subprocess.run(['docker', 'run', '--rm', '--name', name,
                                 '--label', 'monkey-business.check=1',
                                 '-v', str(ROOT) + ':/w:ro', '-w', '/w', IMAGE,
                                 'sh', 'test/rpc/access.sh'], timeout=40)
        return result.returncode
    except subprocess.TimeoutExpired:
        subprocess.run(['docker', 'kill', name], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=5)
        print('Native RPC checks exceeded 40 seconds; own container stopped.', file=sys.stderr)
        return 124


if __name__ == '__main__':
    sys.exit(main())
