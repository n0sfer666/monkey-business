"""Production HTTPS probe through a generated diagnostic Xray and a real VLESS upstream."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import time

USER = '0123456789abcdef0123456789abcdef'
PASSWORD = 'abcdef0123456789abcdef0123456789'
UUID = '11111111-2222-3333-4444-555555555555'


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass

    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/ok')
            self.end_headers()
            return
        body = b'x' * (4097 if self.path in ('/large', '/chunked') else 4096)
        self.send_response(200)
        if self.path == '/chunked':
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            self.wfile.write(f'{len(body):x}\r\n'.encode() + body + b'\r\n0\r\n\r\n')
        else:
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)


with tempfile.TemporaryDirectory(prefix='mb-https-') as directory:
    work = Path(directory)
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                    '-keyout', str(work / 'key.pem'), '-out', str(work / 'cert.pem'),
                    '-subj', '/CN=endpoint.example', '-addext', 'subjectAltName=DNS:endpoint.example'],
                   check=True, timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    web = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain(work / 'cert.pem', work / 'key.pem')
    web.socket = tls.wrap_socket(web.socket, server_side=True)
    thread = threading.Thread(target=web.serve_forever, daemon=True)
    thread.start()
    processes = []
    try:
        upstream = {
            'log': {'loglevel': 'warning'},
            'inbounds': [{'listen': '127.0.0.1', 'port': 18443, 'protocol': 'vless',
                          'settings': {'clients': [{'id': UUID}], 'decryption': 'none'}}],
            'dns': {'hosts': {'endpoint.example': '127.0.0.1'}},
            'outbounds': [{'protocol': 'freedom', 'settings': {'domainStrategy': 'UseIP', 'finalRules': [{'action': 'allow', 'ip': ['127.0.0.1/32']}]}}],
        }
        upstream_file = work / 'upstream.json'
        upstream_file.write_text(json.dumps(upstream))
        upstream_file.chmod(0o600)
        log = (work / 'xray.log').open('wb')
        processes.append(subprocess.Popen(['xray', 'run', '-c', str(upstream_file)], stdout=log, stderr=log))
        generate = work / 'generate.uc'
        generate.write_text("""import { generateDiagnostics } from '/w/src/generator/xray.uc';
print(sprintf('%%J', generateDiagnostics({ candidates: [{ port: 11801,
 credentials: { user: '%s', pass: '%s' }, server: {
 protocol: 'vless', address: '127.0.0.1', port: 18443, uuid: '%s',
 encryption: 'none', security: 'none', transport: { type: 'tcp' } } }] })));
""" % (USER, PASSWORD, UUID))
        config = work / 'diagnostic.json'
        config.write_bytes(subprocess.check_output(['ucode', str(generate)], timeout=5))
        config.chmod(0o600)
        diagnostic = subprocess.Popen(['xray', 'run', '-c', str(config)], stdout=log, stderr=log)
        processes.append(diagnostic)
        for port in (18443, 11801):
            deadline = time.monotonic() + 3
            while True:
                assert all(p.poll() is None for p in processes), (work / 'xray.log').read_text()
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                        break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.05)
        env = dict(os.environ, CURL_CA_BUNDLE=str(work / 'cert.pem'))
        for path, expected, state in [('/ok', 200, 'success'), ('/large', 200, 'failure'), ('/chunked', 200, 'failure'),
                                      ('/redirect', 200, 'failure'), ('/ok', 204, 'failure')]:
            helper = work / 'helper.uc'
            helper.write_text("""import { probeHttps } from '/w/src/runtime/https-probe.uc';
import { processIdentity } from '/w/src/runtime/listener.uc';
import * as sh from '/w/src/runtime/shell.uc';
print(sprintf('%%J', probeHttps(sh, { pid: %d, identity: processIdentity(%d), port: 11801,
 credentials: { user: '%s', pass: '%s' } },
 { url: 'https://endpoint.example:%d%s', expected_status: %d }, '%s')));
""" % (diagnostic.pid, diagnostic.pid, USER, PASSWORD, web.server_port, path, expected, work))
            response = json.loads(subprocess.check_output(['ucode', str(helper)], env=env, text=True, timeout=9))
            assert response['state'] == state, (path, response, (work / 'xray.log').read_text())
        # The same URL with an untrusted certificate must fail, with verification enabled.
        env.pop('CURL_CA_BUNDLE')
        response = json.loads(subprocess.check_output(['ucode', str(helper)], env=env, text=True, timeout=9))
        assert response['state'] == 'failure', response
        log.close()
    finally:
        for process in reversed(processes):
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        web.shutdown()
        web.server_close()
        thread.join(timeout=2)
print('PASS: real VLESS HTTPS, TLS verification, 4096-byte boundary, status mismatch and redirects')
