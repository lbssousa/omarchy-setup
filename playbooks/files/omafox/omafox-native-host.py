#!/usr/bin/python3
# Managed by omarchy-setup (playbooks/user/omafox.yml). Do not edit.
#
# Native messaging host for the Omafox add-on: sends the theme state that
# `omafox sync` writes (the theme-set hook) to the browser, once at the start
# and again whenever it changes. Stands in for upstream's C host, which is
# built for the host system: the Firefox Flatpak can't see /usr/lib, so this
# runs on the Python its runtime ships, and the state directory reaches the
# sandbox through a read-only filesystem override.
import ctypes
import os
import select
import struct
import sys

STATE_DIR = os.path.expanduser("~/.local/state/omafox")
STATE_FILE = os.path.join(STATE_DIR, "theme.json")
MAX_STATE_BYTES = 65536
RETRY_MS = 1000
# IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE |
# IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF
WATCH_MASK = 0x4 | 0x8 | 0x40 | 0x80 | 0x100 | 0x200 | 0x400 | 0x800

libc = ctypes.CDLL(None, use_errno=True)


def read_state():
    """The state's JSON text, or None while it is missing or malformed."""
    try:
        with open(STATE_FILE, "rb") as state:
            data = state.read(MAX_STATE_BYTES + 1)
    except OSError:
        return None
    data = data.strip()
    if len(data) > MAX_STATE_BYTES or not (data.startswith(b"{") and data.endswith(b"}")):
        return None
    return data


def send(data):
    out = sys.stdout.buffer
    out.write(struct.pack("=I", len(data)) + data)
    out.flush()


def main():
    inotify = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    if inotify < 0:
        sys.exit("omafox native host: inotify initialization failed")

    poller = select.poll()
    poller.register(sys.stdin.fileno(), select.POLLIN)
    poller.register(inotify, select.POLLIN)

    last = None
    while True:
        # Watching the same directory again keeps the same watch, and this
        # also recovers from the directory being deleted or not there yet.
        watching = libc.inotify_add_watch(inotify, os.fsencode(STATE_DIR), WATCH_MASK) >= 0

        data = read_state()
        if data is not None and data != last:
            send(data)
            last = data

        for fd, events in poller.poll(None if watching else RETRY_MS):
            if fd == inotify:
                try:
                    os.read(inotify, 16384)
                except BlockingIOError:
                    pass
            elif events & select.POLLIN:
                # Omafox never sends anything: reading is only to see the end.
                if not os.read(fd, 4096):
                    return
            else:
                return


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
