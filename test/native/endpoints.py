"""Synthetic VPN/HTTPS endpoints for native job/observer checks; bounded lifetime."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import ssl
import socket
import subprocess
import threading
import time

ROOT = Path('/assets')
work = Path('/tmp/native-fixture')
work.mkdir(mode=0o700)
subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                '-keyout', str(work / 'key.pem'), '-out', '/assets/fixture-ca.pem',
                '-subj', '/CN=one.fixture.example', '-addext',
                'subjectAltName=DNS:one.fixture.example,DNS:two.fixture.example,IP:8.8.8.8'],
               check=True, timeout=8, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

counts = {}
count_lock = threading.Lock()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        with count_lock:
            counts[self.path] = counts.get(self.path, 0) + 1
            count = counts[self.path]
        if self.path == '/slow' or (self.path == '/extra-slow' and count % 3 == 0):
            time.sleep(8)
        self.send_response(204)
        self.send_header('Content-Length', '0')
        self.end_headers()

(ROOT / 'fixture-key.pem').write_bytes((work / 'key.pem').read_bytes())
web = ThreadingHTTPServer(('127.0.0.1', 18443), Handler)
tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
tls.load_cert_chain('/assets/fixture-ca.pem', work / 'key.pem')
web.socket = tls.wrap_socket(web.socket, server_side=True)
threading.Thread(target=web.serve_forever, daemon=True).start()
plain = ThreadingHTTPServer(('127.0.0.1', 18081), Handler)
threading.Thread(target=plain.serve_forever, daemon=True).start()
config = {
    'log': {'loglevel': 'none'},
    'inbounds': [{'listen': '0.0.0.0', 'port': 14080, 'protocol': 'vless',
                  'settings': {'clients': [{'id': '11111111-2222-3333-4444-555555555555'}], 'decryption': 'none'}}],
    'dns': {'hosts': {'one.fixture.example': '127.0.0.1', 'two.fixture.example': '127.0.0.1'}},
    'routing': {'rules': [{'type': 'field', 'ip': ['8.8.8.8'], 'port': '18081', 'outboundTag': 'test-plain'},{'type': 'field', 'ip': ['8.8.8.8'], 'port': '18443', 'outboundTag': 'test-tcp'},
                          {'type': 'field', 'ip': ['8.8.8.8'], 'port': '18444', 'outboundTag': 'test-udp'}]},
    'outbounds': [{'tag': 'test-plain', 'protocol': 'freedom', 'settings': {'redirect': '127.0.0.1:18081', 'finalRules': [{'action': 'allow', 'ip': ['127.0.0.1/32']}]}},{'tag': 'test-tcp', 'protocol': 'freedom', 'settings': {'redirect': '127.0.0.1:18443', 'finalRules': [{'action': 'allow', 'ip': ['127.0.0.1/32']}]}},
                  {'tag': 'test-udp', 'protocol': 'freedom', 'settings': {'redirect': '127.0.0.1:18444', 'finalRules': [{'action': 'allow', 'ip': ['127.0.0.1/32']}]}},
                  {'protocol': 'freedom', 'settings': {'domainStrategy': 'UseIP',
                   'finalRules': [{'action': 'allow', 'ip': ['127.0.0.1/32']}]}}],
}
config['outbounds'].insert(0, config['outbounds'].pop())
def echo_udp():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.bind(('127.0.0.1', 18444))
        while True:
            data, peer = udp.recvfrom(4096)
            udp.sendto(data, peer)
threading.Thread(target=echo_udp, daemon=True).start()
(work / 'xray.json').write_text(json.dumps(config))
with open('/etc/hosts', 'a') as hosts:
    hosts.write('\n127.0.0.1 one.fixture.example two.fixture.example\n')
hy_config = {'listen': ':14443', 'tls': {'cert': '/assets/fixture-ca.pem', 'key': str(work / 'key.pem')},
             'auth': {'type': 'password', 'password': 'synthetic'}}
(work / 'hysteria.json').write_text(json.dumps(hy_config))
hy = subprocess.Popen(['hysteria', 'server', '-c', str(work / 'hysteria.json')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
process = subprocess.Popen(['xray', 'run', '-c', str(work / 'xray.json')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    time.sleep(330)
finally:
    hy.terminate()
    hy.wait(timeout=3)
    process.terminate()
    process.wait(timeout=3)
    web.shutdown()
