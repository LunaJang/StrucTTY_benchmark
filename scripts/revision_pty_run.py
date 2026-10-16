#!/usr/bin/env python3
"""지정한 크기의 가짜 터미널(pty)에서 StrucTTY 를 한 프레임 돌리고 stdout 을 저장한다.

stdout 을 파일로 리다이렉트하면 Terminal::get_size() 의 ioctl 이 실패해 80x24 폴백이
걸린다(src/utils/Terminal.cpp:76-79). 터미널 크기에 따른 배치/클리핑을 보려면 pty 가
필요하다 -- print_screen_braille() 이 `row = ty - (y_offset/2) - 3` 으로 음수 행을
버리기 때문에(src/visualization/Screen.cpp:912-913) 작은 터미널에서는 상단이 잘린다.

종료 키('q')는 한 번만 써서는 안 된다 -- pty 는 처음엔 canonical 모드라 개행 없는
바이트가 라인 버퍼에 머물고, StrucTTY 가 `tcsetattr(..., TCSAFLUSH, ...)` 로 raw
모드에 들어갈 때 그 입력이 flush 되어 사라진다(src/utils/Terminal.cpp:53).
그래서 자식이 끝날 때까지 주기적으로 'q' 를 다시 보낸다.

사용법:
    revision_pty_run.py <cols> <rows> <out.ansi> <binary> [args...]
환경변수 PTY_TIMEOUT (기본 120초) 로 전체 제한 시간을 조절한다.
종료 코드는 자식 프로세스의 것을 그대로 돌려준다(시간 초과 시 124).
"""

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
        print(__doc__)
        return 2
    cols, rows, out_path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    argv = sys.argv[4:]

    pid, fd = pty.fork()
    if pid == 0:
        os.execv(argv[0], argv)
        os._exit(127)

    # 자식 pty 의 창 크기 지정
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
                    os.write(fd, b"q")      # raw 모드 진입 전후 어느 쪽이든 먹도록 반복
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
            except OSError:               # 자식 종료 시 EIO
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
