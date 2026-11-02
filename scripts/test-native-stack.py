#!/usr/bin/env python3
"""Run the native fixture, asset HTTP server and VM under one bounded owner."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
import re
from pathlib import Path
import signal
import subprocess
import sys
import tarfile
import threading
import uuid

ROOT = Path(__file__).resolve().parent.parent


def main():
    assets = Path(os.environ.get('MB_TEST_ASSETS', '/private/tmp/mb-cgroup-vm/assets'))
    if not os.environ.get('MB_TEST_DISK') or not assets.is_dir():
        print('Prepared disposable MB_TEST_DISK and MB_TEST_ASSETS required.', file=sys.stderr)
        return 2
    with tarfile.open(assets / 'project.tgz', 'w:gz') as bundle:
        for directory in ['src', 'root/usr/share/monkey-business', 'test/native', 'root/etc/init.d', 'scripts/firewall']:
            bundle.add(ROOT / directory, arcname='mb-native/' + directory)
    case = os.environ.get('MB_TEST_CASE', 'all')
    if case not in ['all', 'apply', 'guard']:
        return 2
    (assets / 'guest.sh').write_text('export MB_TEST_CASE=' + case + '\n' + (ROOT / 'test/native/guest.sh').read_text())
    class Assets(SimpleHTTPRequestHandler):
        def do_GET(self):
            if self.path.startswith('/openwrt/'):
                relative = self.path[len('/openwrt/'):]
                if not re.fullmatch(r'releases/25\.12\.4/[A-Za-z0-9/._~-]+', relative) or '..' in relative:
                    self.send_error(400)
                    return
                cached = assets / 'openwrt' / relative
                cached.parent.mkdir(parents=True, exist_ok=True)
                if not cached.is_file():
                    temporary = cached.with_name(cached.name + '.' + uuid.uuid4().hex)
                    result = subprocess.run(['docker', 'run', '--rm', '--label', 'monkey-business.check=1',
                                             '-v', str(assets) + ':/assets', 'monkey-business-integ',
                                             'timeout', '28', 'curl', '--disable', '-fsSL', '--proto', '=https',
                                             '--proto-redir', '=https', '--max-time', '25',
                                             '--max-filesize', '33554432', '-o', '/assets/' + str(temporary.relative_to(assets)),
                                             'https://downloads.openwrt.org/' + relative], timeout=32)
                    if result.returncode:
                        temporary.unlink(missing_ok=True)
                        self.send_error(502)
                        return
                    temporary.replace(cached)
            super().do_GET()

    server = ThreadingHTTPServer(('127.0.0.1', 18981), partial(Assets, directory=str(assets)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    name = 'mb-native-' + uuid.uuid4().hex[:12]
    fixture = None
    vm = None
    try:
        fixture = subprocess.Popen(['docker', 'run', '--rm', '--name', name, '--label', 'monkey-business.check=1',
                                    '-v', str(ROOT) + ':/w:ro', '-v', str(assets) + ':/assets',
                                    '-p', '127.0.0.1:14443:14443/udp', '-p', '127.0.0.1:14080:14080', 'monkey-business-integ',
                                    'timeout', '355', 'python3', '/w/test/native/endpoints.py'])
        env = dict(os.environ, MB_TEST_VM_TIMEOUT='330', MB_TEST_GUEST_COMMAND=(
            'ip link set eth0 nomaster; ip addr flush dev eth0; ip addr add 10.0.2.15/24 dev eth0; '
            'ip link set eth0 up; ip route replace default via 10.0.2.2; '
            'wget -q -T 10 -O /tmp/mb-native-guest.sh http://10.0.2.2:18981/guest.sh && sh /tmp/mb-native-guest.sh'))
        vm = subprocess.Popen([sys.executable, str(ROOT / 'scripts/test-native-vm.py')], env=env)
        return vm.wait(timeout=345)
    finally:
        if vm is not None and vm.poll() is None:
            vm.send_signal(signal.SIGINT)
            try:
                vm.wait(timeout=8)
            except subprocess.TimeoutExpired:
                vm.kill()
                vm.wait(timeout=3)
        subprocess.run(['docker', 'kill', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8)
        if fixture is not None:
            fixture.wait(timeout=8)
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    sys.exit(main())
