import json,subprocess,tempfile,pathlib,socket,time
with tempfile.TemporaryDirectory() as d:
 d=pathlib.Path(d)
 subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(d/'key.pem'),'-out',str(d/'cert.pem'),'-days','1','-subj','/CN=localhost'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5)
 server=d/'server.json';server.write_text(json.dumps({'listen':'127.0.0.1:14443','tls':{'cert':str(d/'cert.pem'),'key':str(d/'key.pem')},'auth':{'type':'password','password':'synthetic'}}));server.chmod(0o600)
 client=d/'client.json';client.write_text(json.dumps({'server':'127.0.0.1:14443','auth':'synthetic','tls':{'sni':'localhost','insecure':True},'lazy':True,'fastOpen':True,'socks5':{'listen':'127.0.0.1:12001','username':'synthetic','password':'synthetic'}}));client.chmod(0o600)
 with open(d/'log','w+') as log:
  upstream=subprocess.Popen(['hysteria','server','-c',str(server)],stdout=log,stderr=log)
  proc=subprocess.Popen(['hysteria','client','-c',str(client)],stdout=log,stderr=log)
  try:
   deadline=time.monotonic()+5
   while True:
    if proc.poll() is not None: log.seek(0);raise Exception(log.read())
    try:s=socket.create_connection(('127.0.0.1',12001),timeout=.5);break
    except OSError:
     if time.monotonic()>deadline:raise
     time.sleep(.05)
   with s:
    s.settimeout(5);s.sendall(b'\x05\x01\x02');print('method',s.recv(2).hex());s.sendall(b'\x01\x09synthetic\x09synthetic');print('auth',s.recv(2).hex());s.sendall(b'\x05\x03\x00\x01'+b'\x00'*6);reply=s.recv(256); print('assoc',reply.hex()); print(subprocess.check_output(['ss','-lnup'],text=True))
    import struct,os
    relay_port=struct.unpack('!H',reply[8:10])[0]
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as target:
     target.bind(('127.0.0.1',0)); target.settimeout(2)
     packet=b'\x00\x00\x00\x01'+socket.inet_aton('127.0.0.1')+struct.pack('!H',target.getsockname()[1])+b'synthetic-injection'
     code='import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.sendto('+repr(packet)+',("127.0.0.1",'+str(relay_port)+'))'
     subprocess.run(['python3','-c',code],preexec_fn=lambda:os.setuid(65534),check=True,timeout=3)
     try: print('FOREIGN_SOURCE_RESULT',target.recvfrom(1024)[0])
     except socket.timeout: print('FOREIGN_SOURCE_RESULT rejected')
  finally:
   for p in [proc,upstream]:
    p.terminate()
    try:p.wait(2)
    except subprocess.TimeoutExpired:p.kill();p.wait()
