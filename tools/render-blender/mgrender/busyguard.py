# SPDX-License-Identifier: Apache-2.0
"""Optional busy-host guard. Off unless configured. Read-only: it never signals,
locks or changes another process.

Some render hosts run other GPU work that must come first (for example a
simulator). Configure any of these; the host is busy while one of them reports busy:

    BUSY_LOCK_PATH        lock files (separated by os.pathsep): busy while some process
                          holds a lock on one (read from /proc/locks; Linux only)
    BUSY_PROCESS_PATTERN  Python regular expression: busy while a process command line
                          matches it (read from /proc; Linux only)
    BUSY_COMMAND          shell command: busy while it exits with status 0; its first
                          output line is shown as the reason (any OS)

render.py also takes --busy-lock PATH (repeatable), --busy-process REGEX and
--wait-for-command CMD, which add to the environment settings.

    python3 -m mgrender.busyguard     # exit 0: clear or not configured, 3: busy, 2: bad setting
"""
import os
import re
import subprocess
import sys


class Config:
    def __init__(self, locks=(), pattern=None, command=None):
        self.locks = [p for p in locks if p]
        self.pattern = pattern or None
        self.command = command or None

    @classmethod
    def from_env(cls, locks=(), pattern=None, command=None, env=None):
        env = os.environ if env is None else env
        env_locks = [p for p in env.get("BUSY_LOCK_PATH", "").split(os.pathsep) if p]
        return cls(env_locks + list(locks), pattern or env.get("BUSY_PROCESS_PATTERN"),
                   command or env.get("BUSY_COMMAND"))

    @property
    def enabled(self):
        return bool(self.locks or self.pattern or self.command)

    def describe(self):
        if not self.enabled:
            return "off (no BUSY_LOCK_PATH, BUSY_PROCESS_PATTERN or BUSY_COMMAND)"
        parts = []
        if self.locks:
            parts.append(f"{len(self.locks)} lock file(s)")
        if self.pattern:
            parts.append("process pattern")
        if self.command:
            parts.append("command")
        return "on: " + ", ".join(parts)

    def problems(self, proc="/proc"):
        """Settings that cannot be checked here. A configured check is never ignored silently."""
        out = []
        if self.pattern:
            try:
                re.compile(self.pattern)
            except re.error as e:
                out.append(f"bad process pattern: {e}")
        if (self.locks or self.pattern) and not os.path.isdir(proc):
            out.append(f"lock and process checks need {proc} (Linux); use a busy command instead")
        return out


def _read(path):
    try:
        with open(path, "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except OSError:
        return ""


def running_processes(pattern, proc="/proc"):
    """Return [(pid, command line)] for processes whose command line matches pattern."""
    rx = re.compile(pattern)
    me = os.getpid()
    hits = []
    for entry in os.listdir(proc):
        if not entry.isdigit() or int(entry) == me:
            continue
        cmd = _read(os.path.join(proc, entry, "cmdline"))
        if cmd and rx.search(cmd):
            hits.append((int(entry), cmd[:160]))
    return hits


def held_locks(paths, locks_file="/proc/locks"):
    """Return the lock files in paths that some process holds (from /proc/locks, no locking)."""
    try:
        with open(locks_file) as f:
            table = f.read()
    except OSError:
        return []
    held = set()
    for line in table.splitlines():
        m = re.search(r"\b([0-9a-f]+):([0-9a-f]+):(\d+)\b", line)
        if m:
            held.add((int(m.group(1), 16), int(m.group(2), 16), int(m.group(3))))
    out = []
    for p in paths:
        try:
            st = os.stat(p)
        except OSError:
            continue
        if (os.major(st.st_dev), os.minor(st.st_dev), st.st_ino) in held:
            out.append(p)
    return out


def command_busy(command, timeout=60):
    """(busy, reason): busy when the command exits 0."""
    try:
        r = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return True, f"busy command timed out after {timeout} s"
    first = (r.stdout.strip().splitlines() or ["(no output)"])[0]
    return r.returncode == 0, f"busy command: {first[:160]}"


def status(cfg, proc="/proc", locks_file="/proc/locks"):
    """(clear, reasons). Not configured: always clear."""
    reasons = []
    if cfg.pattern:
        reasons += [f"pid {pid}: {cmd}" for pid, cmd in running_processes(cfg.pattern, proc)]
    if cfg.locks:
        reasons += [f"lock held: {p}" for p in held_locks(cfg.locks, locks_file)]
    if cfg.command:
        busy, why = command_busy(cfg.command)
        if busy:
            reasons.append(why)
    return (not reasons), reasons


def main(argv=None):
    cfg = Config.from_env()
    bad = cfg.problems()
    if bad:
        print("busyguard: " + "; ".join(bad))
        return 2
    clear, reasons = status(cfg) if cfg.enabled else (True, [])
    if clear:
        print(f"busyguard: clear (guard {cfg.describe()})")
        return 0
    print("busyguard: HOST BUSY; heavy renders wait:")
    for r in reasons:
        print("  " + r)
    return 3


if __name__ == "__main__":
    sys.exit(main())
