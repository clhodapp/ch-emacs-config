# SPDX-License-Identifier: MIT
"""Run a command on a fresh pseudo-terminal and hold the master side open.

emacsclient -t refuses to run without a terminal on stdin; this gives it
one inside a batch job (a nix build sandbox, a CI runner) so a daemon check
can open real tty client frames.  Output from the slave is drained and
discarded; the process ends when the command exits.
"""

import fcntl
import os
import pty
import select
import struct
import sys
import termios

pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm"
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    os.execvp(sys.argv[1], sys.argv[1:])
while True:
    try:
        ready, _, _ = select.select([fd], [], [], 1)
        if ready and not os.read(fd, 4096):
            break
    except OSError:
        break
