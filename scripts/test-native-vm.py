#!/usr/bin/env python3
"""Bounded serial-only runner for a disposable, already prepared OpenWrt image.

No SSH authorization, existing dev-VM, or production machine is accessed.
The disk is opened with QEMU snapshot=on. MB_TEST_DISK must be a test image.
"""
import os
from pathlib import Path
import pty
import select
import signal
import shutil
import subprocess
import sys
import time
import tty


def main():
    disk = os.environ.get('MB_TEST_DISK')
    command = os.environ.get('MB_TEST_GUEST_COMMAND')
    if not disk or not command or '\n' in command:
        print('Set MB_TEST_DISK and a single-line MB_TEST_GUEST_COMMAND.', file=sys.stderr)
        return 2
    qemu = shutil.which('qemu-system-aarch64')
    firmware = Path(qemu).resolve().parent.parent / 'share/qemu/edk2-aarch64-code.fd'
    master, slave = pty.openpty()
    tty.setraw(slave)
    args = [qemu, '-name', 'mb-disposable-check', '-machine', 'virt,accel=hvf', '-cpu', 'host',
            '-smp', '2', '-m', '768', '-bios', str(firmware),
            '-drive', 'file=' + disk + ',if=virtio,format=raw,snapshot=on',
            '-device', 'virtio-net-pci,netdev=lan', '-netdev', 'user,id=lan',
            '-display', 'none', '-monitor', 'none', '-serial', 'stdio']
    def terminate(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, terminate)
    process = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    output = bytearray()
    deadline = time.monotonic() + int(os.environ.get('MB_TEST_VM_TIMEOUT', '360'))
    sent = False
    last_enter = 0
    try:
        while process.poll() is None and time.monotonic() < deadline:
            if not sent and b'Please press Enter' in output and time.monotonic() - last_enter > 2:
                os.write(master, b'\n')
                last_enter = time.monotonic()
            ready, _, _ = select.select([master], [], [], .2)
            if not ready:
                continue
            try:
                data = os.read(master, 65536)
            except OSError:
                break
            output.extend(data)
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
            if not sent and b'~# ' in output:
                time.sleep(8)
                os.write(master, ('  ' + command + '; rc=$?; echo MB_NATIVE_RESULT:$rc; poweroff\r').encode())
                sent = True
        if b'\nMB_NATIVE_RESULT:0\n' in output.replace(b'\r', b''):
            return 0
        print('\nNative VM check failed or exceeded its deadline.', file=sys.stderr)
        return 1
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        os.close(master)


if __name__ == '__main__':
    sys.exit(main())
