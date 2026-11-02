"""Real old/new Xray packet paths, including failed Apply and scoped guard precedence."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

if len(sys.argv) > 1 and sys.argv[1] == 'http':
    counter = Path(sys.argv[2])
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_GET(self):
            body = b'direct' if self.server.server_port == 18081 else b'via-vpn'
            if body == b'direct':
                with counter.open('ab') as stream:
                    stream.write(b'contact\n')
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    for port in [18081, 18082]:
        web = ThreadingHTTPServer(('0.0.0.0', port), Handler)
        threading.Thread(target=web.serve_forever, daemon=True).start()
    time.sleep(90)
    sys.exit(0)

ROOT = Path('/w')
NAMES = ['mbtrans-r', 'mbtrans-c', 'mbtrans-s']
children = []
def run(*args, ok=True, input=None):
    result = subprocess.run(args, input=input, text=True, capture_output=True, timeout=8)
    if ok and result.returncode:
        raise RuntimeError(str(args) + '\n' + result.stdout + result.stderr)
    return result

def spawn(namespace, *args):
    process = subprocess.Popen(['ip', 'netns', 'exec', namespace, *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    children.append(process)
    return process

with tempfile.TemporaryDirectory(prefix='mb-transition-') as temporary:
    work = Path(temporary)
    try:
        for name in NAMES:
            run('ip', 'netns', 'add', name)
            run('ip', '-n', name, 'link', 'set', 'lo', 'up')
        for left, right, ns_left, ns_right in [('tc', 'tr', NAMES[1], NAMES[0]), ('ts', 'tu', NAMES[2], NAMES[0])]:
            run('ip', 'link', 'add', left, 'type', 'veth', 'peer', 'name', right)
            run('ip', 'link', 'set', left, 'netns', ns_left)
            run('ip', 'link', 'set', right, 'netns', ns_right)
        for namespace, interface, address in [(NAMES[1], 'tc', '10.27.0.2/24'), (NAMES[0], 'tr', '10.27.0.1/24'),
                                               (NAMES[2], 'ts', '8.8.8.8/24'), (NAMES[0], 'tu', '8.8.8.1/24')]:
            run('ip', '-n', namespace, 'addr', 'add', address, 'dev', interface)
            run('ip', '-n', namespace, 'link', 'set', interface, 'up')
        run('ip', '-n', NAMES[2], 'addr', 'add', '172.27.0.9/32', 'dev', 'lo')
        run('ip', '-n', NAMES[0], 'route', 'add', '172.27.0.9/32', 'via', '8.8.8.8')
        run('ip', '-n', NAMES[1], 'route', 'add', 'default', 'via', '10.27.0.1')
        run('ip', '-n', NAMES[2], 'route', 'add', 'default', 'via', '8.8.8.1')
        run('ip', 'netns', 'exec', NAMES[0], 'sysctl', '-wq', 'net.ipv4.ip_forward=1', 'net.ipv4.conf.all.route_localnet=1', 'net.ipv4.conf.all.rp_filter=0', 'net.ipv4.conf.tr.rp_filter=0', 'net.ipv4.conf.tu.rp_filter=0')
        counter = work / 'direct-count'; counter.write_bytes(b'')
        spawn(NAMES[2], 'python3', str(ROOT / 'test/integ/corporate_transition.py'), 'http', str(counter))
        upstream = {'log': {'loglevel': 'none'}, 'inbounds': [{'port': 14080, 'protocol': 'vless', 'settings': {
            'clients': [{'id': '11111111-2222-3333-4444-555555555555'}], 'decryption': 'none'}}],
            'outbounds': [{'protocol': 'freedom', 'settings': {'redirect': '8.8.8.8:18082'}}]}
        (work / 'upstream.json').write_text(json.dumps(upstream))
        spawn(NAMES[2], 'xray', 'run', '-c', str(work / 'upstream.json'))
        generator = work / 'generate.uc'
        generator.write_text("""import { readfile } from 'fs';
import { generateJson } from '/w/src/generator/xray.uc';
import { declarations } from '/w/src/generator/corporate-nft.uc';
import { transitionDocument, scope } from '/w/src/runtime/corporate-transition.uc';
let value = json(readfile(ARGV[1]));
if (ARGV[0] == 'xray') print(generateJson(value));
if (ARGV[0] == 'sets') print(declarations(value.rules, value.policies));
if (ARGV[0] == 'guard') print(transitionDocument(value));
""")
        def generate(kind, value, name):
            source = work / (name + '.input.json'); source.write_text(json.dumps(value))
            target = work / name
            target.write_text(run('ucode', str(generator), kind, str(source)).stdout); target.chmod(0o600)
            return target
        rule = {'id': 'gateway', 'name': 'Synthetic', 'address': '8.8.8.8', 'port': '18081', 'enabled': True, 'requires_udp': False}
        config = {'global': {'routing_mode': 'gfwlist', 'local_region': 'other', 'ipv6_block': '1'},
                  'server': {'protocol': 'vless', 'tag': 'synthetic', 'address': '172.27.0.9', 'port': 14080,
                             'uuid': '11111111-2222-3333-4444-555555555555', 'security': 'none', 'encryption': 'none', 'transport': {'type': 'tcp'}},
                  'corporate_rules': []}
        engine = None
        def engine_rules(rules):
            nonlocal_config = dict(config, corporate_rules=rules)
            path = generate('xray', nonlocal_config, 'main.json')
            run('ip', 'netns', 'exec', NAMES[0], 'xray', 'run', '-test', '-c', str(path))
            return spawn(NAMES[0], 'xray', 'run', '-c', str(path))
        def replace(rules):
            global engine
            if engine is not None:
                engine.terminate(); engine.wait(timeout=3)
            engine = engine_rules(rules)
            time.sleep(.12)
        def firewall(rules, policies):
            sets = generate('sets', {'rules': rules, 'policies': policies}, 'sets.nft')
            run('ip', 'netns', 'exec', NAMES[0], 'env', 'MB_LAN_IFACE=tr', 'MB_KILL_SWITCH=0', 'MB_DIRECT_BYPASS=0',
                'MB_CORPORATE_SETS=' + str(sets), 'sh', '/w/scripts/firewall/apply.sh')
        def request(port=18081):
            return run('ip', 'netns', 'exec', NAMES[1], 'curl', '--disable', '--noproxy', '*', '-sS', '--max-time', '0.4',
                       'http://8.8.8.8:' + str(port), ok=False)
        def guard(scopes):
            path = generate('guard', scopes, 'guard.nft')
            run('ip', 'netns', 'exec', NAMES[0], 'nft', '-f', str(path))
        def release():
            run('ip', 'netns', 'exec', NAMES[0], 'nft', 'delete', 'table', 'inet', 'mb_corporate_transition')
        proxy = {'gateway': {'route': 'proxy'}}
        scope_ = {'lan': 'tr', 'rules': [rule], 'policies': proxy}
        replace([]); firewall([rule], proxy)
        negative = request()
        assert negative.stdout == 'direct', 'negative control: ' + repr([negative.returncode, negative.stdout, negative.stderr])
        before = counter.read_bytes()
        guard([scope_])
        assert request().returncode == 28, 'old Xray escaped transitional ingress DROP'
        replace([rule]); firewall([rule], proxy)
        assert request().returncode == 28, 'guard released before final publication'
        release(); assert request().stdout == 'via-vpn'
        guard([scope_]); replace([])
        invalid = work / 'invalid.nft'; invalid.write_text('flush set inet monkey_business corp_exact_proxy\ninvalid syntax\n')
        assert run('ip', 'netns', 'exec', NAMES[0], 'nft', '-f', str(invalid), ok=False).returncode
        assert request().returncode == 28, 'failed Apply removal contacted direct upstream'
        replace([rule]); firewall([rule], proxy); release()
        assert request().stdout == 'via-vpn'
        assert counter.read_bytes() == before, 'direct contact occurred during Apply or rollback'
        wildcard = dict(rule, id='wild', port='')
        exact = dict(rule, id='off', enabled=False)
        policies = {'wild': {'route': 'proxy'}}
        guard([{'lan': 'tr', 'rules': [wildcard, exact], 'policies': policies}])
        firewall([wildcard, exact], policies)
        assert request().stdout == 'direct', 'exact off exception was blocked by wildcard guard'
        assert request(18082).returncode == 28, 'wildcard guard failed'
        assert request(53).returncode == 28, 'port 53 escaped guard before DNS redirect'
        release()
        print('PASS: negative direct-leak control; guarded old/new Xray, failed Apply/rollback, exact off and :53 packet paths')
    finally:
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try: child.wait(timeout=2)
                except subprocess.TimeoutExpired: child.kill(); child.wait(timeout=2)
        for name in NAMES:
            run('ip', 'netns', 'del', name, ok=False)
