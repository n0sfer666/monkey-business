import { readfile } from 'fs';
import * as socket from 'socket';
let id = ARGV[0];
if (match(id || '', /^[a-f0-9]{32}$/) == null) exit(1);
let path = '/sys/fs/cgroup/monkey-business-engines/job-' + id + '/node-0';
for (let tick = 0; tick < 160; tick++) {
 let members = split(readfile(path + '/cgroup.procs') || '', '\n');
 if (length(members) >= 6) {
  for (let raw in members) {
   let pid = int(raw), cmd = readfile('/proc/' + pid + '/cmdline') || '';
   if (index(cmd, 'ucode\u0000/usr/share/monkey-business/job-node.uc\u0000' + id + '\u00000\u0000') == 0) {
    system('kill -KILL ' + pid); print('killed-owned-node'); exit(0);
   }
  }
 }
 socket.poll(50);
}
exit(1);
