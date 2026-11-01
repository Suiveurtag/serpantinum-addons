#!/usr/bin/env python3
"""Own a CLI process tree even when Quickshell abruptly kills the Node sidecar."""
import ctypes
import os
import signal
import subprocess
import sys

parent = int(sys.argv[1])
child = None

def stop(signum, frame):
    if child and child.poll() is None:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
ctypes.CDLL(None).prctl(1, signal.SIGTERM, 0, 0, 0)  # Linux PR_SET_PDEATHSIG
if os.getppid() != parent:
    sys.exit(125)
signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
child = subprocess.Popen(sys.argv[2:], start_new_session=True)
signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGTERM, signal.SIGINT})
# Parent death between Popen and assignment is caught by this second check.
if os.getppid() != parent:
    stop(signal.SIGTERM, None)
sys.exit(child.wait())
