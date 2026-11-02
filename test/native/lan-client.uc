import * as socket from 'socket';
let udp = socket.create(socket.AF_INET, socket.SOCK_DGRAM, 0);
if (udp == null || !udp.connect({ address: '8.8.8.8', port: 18444 })) exit(1);
let payload = 'synthetic-lan-udp-' + time();
udp.send(payload);
if (!length(socket.poll(2000, [udp, socket.POLLIN]))) die('LAN UDP timeout');
let answer = udp.recv(4096); udp.close();
if (answer != payload) die('wrong LAN UDP response');
print('PASS: real LAN UDP through TPROXY, guarded Xray and VPN outbound\n');

let dns = socket.create(socket.AF_INET, socket.SOCK_DGRAM, 0);
if (dns == null || !dns.connect({ address: '9.9.9.9', port: 53 })) exit(1);
let query = '\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00' + '\x07fixture\x07example\x00\x00\x01\x00\x01';
dns.send(query);
if (!length(socket.poll(2000, [dns, socket.POLLIN]))) die('LAN DNS timeout');
let response = dns.recv(4096); dns.close();
if (substr(response, 0, 2) != '\x12\x34' || substr(response, -4) != '\xc0\x00\x02\x2a') die('wrong LAN DNS response');
print('PASS: real LAN DNS redirect and Xray DNS inbound coexist with diagnostic guard\n');
