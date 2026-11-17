#!/usr/bin/env python3
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

def main():
    if len(sys.argv) < 5:
        print("usage: pty_run.py <cols> <rows> <out.ansi> <binary> [args...]")
        return 2
    cols, rows, out_path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    argv = sys.argv[4:]

    pid, fd = pty.fork()
    if pid == 0:
        os.execv(argv[0], argv)
        os._exit(127)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    timeout = float(os.environ.get("PTY_TIMEOUT", "120"))
    deadline = time.monotonic() + timeout
    next_quit = 0.0
    chunks = []
    timed_out = False

    try:
        while True:
            now = time.monotonic()
            if now > deadline:
                timed_out = True
                os.kill(pid, signal.SIGKILL)
                break
            if now >= next_quit:
                try:
                    os.write(fd, b"q")
                except OSError:
                    break
                next_quit = now + 0.3

            try:
                ready, _, _ = select.select([fd], [], [], 0.1)
            except OSError:
                break
            if not ready:
                if os.waitpid(pid, os.WNOHANG)[0] == pid:
                    break
                continue
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            chunks.append(data)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            _, status = os.waitpid(pid, 0)
        except ChildProcessError:
            status = 0

    with open(out_path, "wb") as fh:
        fh.write(b"".join(chunks))

    if timed_out:
        print(f"TIMEOUT after {timeout}s: {' '.join(argv)}", file=sys.stderr)
        return 124
    return os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else 0

if __name__ == "__main__":
    sys.exit(main())
