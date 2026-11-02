import { readJob, jobPath } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/jobs.uc';
import { atomicPrivate } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { monotonic } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
import * as socket from 'socket';
let end = monotonic() + 12;
while (monotonic() < end) {
 let job = readJob(ARGV[0]);
 if (job != null && job.rows[0].phase == 'extra') {
  socket.poll(300);
  if (!atomicPrivate(jobPath(ARGV[0]) + '/cancel', 'cancel')) die('cancel write failed');
  print('cancelled-extra'); exit(0);
 }
 socket.poll(20);
}
die('extra phase not observed');
