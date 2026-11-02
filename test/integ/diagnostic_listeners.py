"""Qualify real SOCKS authentication, UDP bind and permanent guard on this Xray."""
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time
import threading

USER = '0123456789abcdef0123456789abcdef'
PASSWORD = 'abcdef0123456789abcdef0123456789'
PORT = 11800


def receive(sock, count):
    value = b''
    while len(value) < count:
        piece = sock.recv(count - len(value))
        if not piece:
            raise AssertionError('short SOCKS response')
        value += piece
    return value


def authenticate(sock):
    sock.sendall(b'\x05\x01\x02')
    assert receive(sock, 2) == b'\x05\x02', 'password method required'
    sock.sendall(b'\x01' + bytes([len(USER)]) + USER.encode() + bytes([len(PASSWORD)]) + PASSWORD.encode())
    assert receive(sock, 2) == b'\x01\x00', 'generated credentials rejected'


with tempfile.TemporaryDirectory(prefix='mb-listeners-') as directory:
    work = Path(directory)
    generate = work / 'generate.uc'
    generate.write_text('''import { buildDiagnosticInbound } from '/w/src/generator/inbounds.uc';
print(sprintf('%%J', { log: { loglevel: 'warning' },
 inbounds: [buildDiagnosticInbound('health', 11800,
 { user: '%s', pass: '%s' })],
 outbounds: [{ protocol: 'freedom', tag: 'proxy', settings: {} }] }));
''' % (USER, PASSWORD))
    config = work / 'xray.json'
    config.write_bytes(subprocess.check_output(['ucode', str(generate)], timeout=5))
    config.chmod(0o600)
    # This Docker kernel lacks nft_socket; production cgroup isolation is tested
    # separately on the native OpenWrt kernel. Here we qualify auth/source pin.
    with (work / 'xray.log').open('wb') as log:
        process = subprocess.Popen(['xray', 'run', '-c', str(config)], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 3
            while True:
                assert process.poll() is None, (work / 'xray.log').read_text()
                try:
                    control = socket.create_connection(('127.0.0.1', PORT), timeout=0.2)
                    break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise AssertionError('listener readiness timeout')
                    time.sleep(0.05)
            with control:
                control.settimeout(2)
                authenticate(control)
                client_udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                client_udp.bind(('127.0.0.1', 0))
                client_udp.settimeout(1)
                client_port = client_udp.getsockname()[1]
                control.sendall(b'\x05\x03\x00\x01' + socket.inet_aton('127.0.0.1') + struct.pack('!H', client_port))
                reply = receive(control, 10)
                assert reply[:4] == b'\x05\x00\x00\x01', repr(reply)
                relay = socket.inet_ntoa(reply[4:8])
                relay_port = struct.unpack('!H', reply[8:10])[0]
                assert relay == '127.0.0.1', (relay, relay_port)
                listeners = subprocess.check_output(['ss', '-lnup'], text=True, timeout=3)
                assert f'127.0.0.1:{relay_port}' in listeners, listeners
                assert f'0.0.0.0:{relay_port}' not in listeners, listeners
                print('Xray UDP relay:', relay, relay_port)
                # Equivalent isolation for dynamic relay ports: bind the privileged
                # helper first and pin both source IP and port in UDP ASSOCIATE.
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as target:
                    target.bind(('127.0.0.1', 0))
                    target.settimeout(0.3)
                    packet = b'\x00\x00\x00\x01' + socket.inet_aton('127.0.0.1') + struct.pack('!H', target.getsockname()[1]) + b'synthetic'
                    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as stranger:
                        stranger.sendto(packet, (relay, relay_port))
                    try:
                        target.recvfrom(1024)
                        raise AssertionError('foreign UDP source accepted before first real datagram')
                    except socket.timeout:
                        pass
                    client_udp.sendto(packet, (relay, relay_port))
                    target.settimeout(1)
                    data, peer = target.recvfrom(1024)
                    assert data == b'synthetic'
                    target.sendto(data, peer)
                    assert client_udp.recv(1024).endswith(b'synthetic')
                bind_code = f"""import socket
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
try:
 s.bind(('127.0.0.1',{client_port}))
except OSError:
 raise SystemExit(0)
raise SystemExit(1)
"""
                subprocess.run(['python3', '-c', bind_code], preexec_fn=lambda: os.setuid(65534), check=True, timeout=3)
                client_udp.close()
                code = '''import socket
try:
 s=socket.create_connection(('127.0.0.1',11800),timeout=1)
 s.sendall(b'\\x05\\x01\\x00')
 reply=s.recv(2)
except OSError:
 raise SystemExit(0)
raise SystemExit(1 if reply==b'\\x05\\x00' else 0)
'''
                subprocess.run(['python3', '-c', code], preexec_fn=lambda: os.setuid(65534), check=True, timeout=3)
            # The production ucode helper must traverse the real SOCKS UDP path.
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as stun:
                stun.bind(('127.0.0.1', 0))
                stun.settimeout(4)
                def respond():
                    for _ in range(2):
                        request, peer = stun.recvfrom(4096)
                        assert len(request) == 20 and request[:2] == b'\x00\x01'
                        # A wrong transaction must not count as success.
                        bad = b'\x01\x01\x00\x0c' + request[4:8] + b'xxxxxxxxxxxx' + b'\x00\x20\x00\x08\x00\x01\x00\x01\x01\x02\x03\x04'
                        stun.sendto(bad, peer)
                        good = b'\x01\x01\x00\x0c' + request[4:20] + b'\x00\x20\x00\x08\x00\x01\x00\x01\x01\x02\x03\x04'
                        stun.sendto(good, peer)
                responder = threading.Thread(target=respond, daemon=True)
                responder.start()
                helper = work / 'udp.uc'
                helper.write_text("""import { probeUdp } from '/w/src/runtime/udp-probe.uc';
import { processIdentity } from '/w/src/runtime/listener.uc';
let targets = [{ host: 'localhost', port: %d }, { host: 'localhost', port: %d }];
print(sprintf('%%J', probeUdp({ pid: %d, identity: processIdentity(%d), port: 11800,
 credentials: { user: '%s', pass: '%s' } }, targets)));
""" % (stun.getsockname()[1], stun.getsockname()[1], process.pid, process.pid, USER, PASSWORD))
                answer = subprocess.check_output(['ucode', str(helper)], timeout=4, text=True)
                responder.join(timeout=1)
                assert json.loads(answer)['state'] == 'success', answer
                assert not responder.is_alive(), 'STUN target did not receive both attempts'
                print('Production ucode helper: two valid STUN responses through Xray')
            with socket.create_connection(('127.0.0.1', PORT), timeout=1) as unauth:
                unauth.sendall(b'\x05\x01\x00')
                try:
                    reply = unauth.recv(2)
                except OSError:
                    reply = b''
                assert reply != b'\x05\x00', 'unauthenticated SOCKS accepted'
        finally:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
print('PASS: auth, loopback UDP relay, source pin before first datagram, non-root isolation')
