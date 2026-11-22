#!/usr/bin/env python3
"""Runs one command of security-key-omarchy's key-helper, for the security key
wizard (playbooks/user/security-key-wizard.yml).

The overlay keeps the helper running and speaks to it in JSON lines; the
wizard, one Ansible task at a time, starts it for each command instead. This
waits for the helper's first look at the key, sends the command (one JSON
object read from stdin, PIN included, so it is never in a command line), waits
for its outcome and for the key's state after it, and prints both:

  {"result": <the helper's done/error/cancelled event; null for refresh>,
   "state": <its last state event>}

The helper runs every program without a terminal (pamu2fcfg, ssh-keygen and
fido2-token take the PIN from it), and pkexec's authentications go to the
session's polkit agent, as from the overlay.

Usage: helper-call.py HELPER < command.json
"""

import json
import os
import selectors
import subprocess
import sys
import time

# Longer than any of the helper's own timeouts (a touch, a polkit dialog, a
# resident key made twice), so it is the helper that gives up first.
COMMAND_TIMEOUT_S = 300
# A state normally follows a command's outcome; when it doesn't, a refresh is
# asked for, again every few seconds while a running one swallows it.
STATE_WAIT_S = 3
STARTUP_TIMEOUT_S = 60


class Events:
    def __init__(self, proc):
        self.proc = proc
        self.selector = selectors.DefaultSelector()
        self.selector.register(proc.stdout, selectors.EVENT_READ)
        self.buffer = b""
        self.closed = False

    def next(self, deadline):
        """The next JSON event, or None once the deadline passes."""
        while b"\n" not in self.buffer:
            left = deadline - time.monotonic()
            if left <= 0 or self.closed:
                return None
            if not self.selector.select(left):
                continue
            chunk = os.read(self.proc.stdout.fileno(), 65536)
            if not chunk:
                self.closed = True
                return None
            self.buffer += chunk
        line, self.buffer = self.buffer.split(b"\n", 1)
        try:
            event = json.loads(line)
        except ValueError:
            return {}
        return event if isinstance(event, dict) else {}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        command = json.loads(sys.stdin.readline() or "null")
    except ValueError:
        command = None
    if not isinstance(command, dict) or not isinstance(command.get("cmd"), str):
        sys.exit("helper-call.py: expected one JSON command on stdin")
    name = command["cmd"]

    proc = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    events = Events(proc)

    def send(obj):
        proc.stdin.write((json.dumps(obj) + "\n").encode())
        proc.stdin.flush()

    def wait_state(deadline, nudge):
        """The next state event; with nudge, asks for one when none comes."""
        while time.monotonic() < deadline:
            event = events.next(min(deadline, time.monotonic() + STATE_WAIT_S) if nudge else deadline)
            if event is None:
                if events.closed:
                    return None
                send({"cmd": "refresh"})
                continue
            if event.get("type") == "state":
                return event
        return None

    try:
        state = wait_state(time.monotonic() + STARTUP_TIMEOUT_S, nudge=False)
        if state is None:
            sys.exit("helper-call.py: the helper never described the key")
        result = None
        if name != "refresh":
            send(command)
            deadline = time.monotonic() + COMMAND_TIMEOUT_S
            while result is None:
                event = events.next(deadline)
                if event is None:
                    if not events.closed:
                        send({"cmd": "cancel"})
                    result = {"type": "error", "op": name, "code": "timeout", "detail": ""}
                elif event.get("type") == "state":
                    state = event
                elif event.get("type") in ("done", "error", "cancelled") and event.get("op") == name:
                    result = event
            after = wait_state(time.monotonic() + COMMAND_TIMEOUT_S, nudge=True)
            state = after or state
        print(json.dumps({"result": result, "state": state}))
    finally:
        try:
            proc.stdin.close()
        except OSError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.terminate()
            proc.wait()


if __name__ == "__main__":
    main()
