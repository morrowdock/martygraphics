# SPDX-License-Identifier: Apache-2.0
"""Simulator-priority guard. Read-only: it never signals, locks or changes another process.

The landing-lab simulator (ArduPilot SITL, Gazebo, MAVProxy, its lab runner)
has priority on the render host. This module looks for those processes in
/proc and for a held sitl-up flock in /proc/locks. The distrobox container
shares the host PID namespace, so its processes are visible here.

    python3 -m mgrender.simguard        # exit 0: clear, exit 3: simulator running
"""
import os
import re
import sys

# Matched against the executable name and the full command line.
PATTERNS = [
    r"(^|/)arducopter\b", r"(^|/)arduplane\b", r"(^|/)ardurover\b", r"(^|/)ardusub\b",
    r"\bsim_vehicle\.py\b", r"(^|/)mavproxy(\.py)?\b", r"\bMAVProxy\b",
    r"(^|/)gzserver\b", r"(^|/)gzclient\b", r"(^|/)gazebo\b", r"(^|[/ ])gz sim\b",
    r"\bgz-sim\b", r"\bruby\b.*\bgz\b.*\bsim\b",
    r"(^|/)sitl-up\b", r"\b-m lab\.run\b", r"\blab/run\.py\b",
]
_RE = re.compile("|".join(PATTERNS))


def lock_paths():
    paths = []
    if os.environ.get("SITL_LOCK_FILE"):
        paths.append(os.environ["SITL_LOCK_FILE"])
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    paths += [os.path.join(runtime, "sitl-up.lock"), os.path.expanduser("~/.cache/sitl-up.lock")]
    return paths


def _cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except OSError:
        return ""


def running_simulators(proc="/proc"):
    """Return [(pid, command line)] for simulator processes."""
    me = os.getpid()
    hits = []
    for entry in os.listdir(proc):
        if not entry.isdigit() or int(entry) == me:
            continue
        cmd = _cmdline(entry) if proc == "/proc" else _read(os.path.join(proc, entry, "cmdline"))
        if cmd and _RE.search(cmd):
            hits.append((int(entry), cmd[:160]))
    return hits


def _read(path):
    try:
        with open(path, "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except OSError:
        return ""


def held_locks(paths=None, locks_file="/proc/locks"):
    """Return the sitl-up lock files that some process holds (from /proc/locks, no locking)."""
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
    for p in paths if paths is not None else lock_paths():
        try:
            st = os.stat(p)
        except OSError:
            continue
        if (os.major(st.st_dev), os.minor(st.st_dev), st.st_ino) in held:
            out.append(p)
    return out


def status():
    procs = running_simulators()
    locks = held_locks()
    reasons = [f"pid {pid}: {cmd}" for pid, cmd in procs] + [f"lock held: {p}" for p in locks]
    return (not reasons), reasons


def main():
    clear, reasons = status()
    if clear:
        print("simguard: clear (no landing-lab simulator process or lock)")
        return 0
    print("simguard: SIMULATOR RUNNING; heavy renders wait:")
    for r in reasons:
        print("  " + r)
    return 3


if __name__ == "__main__":
    sys.exit(main())
