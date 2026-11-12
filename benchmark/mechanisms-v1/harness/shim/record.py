# SPDX-License-Identifier: Apache-2.0
"""Byte-preserving Claude Code recorder. No model is called by installation."""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import time
import uuid

VERSION = "2.1.322"
ALLOWLIST = frozenset((
    "HOME", "PATH", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE",
    "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CONFIG_DIR", "HTTPS_PROXY", "HTTP_PROXY",
    "NO_PROXY", "https_proxy", "http_proxy", "no_proxy", "NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE",
))


def environment(source=None):
    return {key: value for key, value in (os.environ if source is None else source).items()
            if key in ALLOWLIST and not key.startswith("ANTHROPIC_")}


def resolve(executable):
    if os.path.isabs(executable):
        candidates = [Path(executable)]
    elif executable == "claude":
        candidates = [Path(folder) / executable for folder in os.environ.get("PATH", "").split(":")
                      if os.path.isabs(folder)]
    else:
        raise ValueError("use an absolute executable or claude on an absolute PATH entry")
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    raise ValueError("claude executable not found")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def record(executable, arguments, root, timeout=900, *, stdin=None, stdout=None, stderr=None, cwd=None):
    started = time.monotonic()
    stdin = sys.stdin.buffer if stdin is None else stdin
    stdout = sys.stdout.buffer if stdout is None else stdout
    stderr = sys.stderr.buffer if stderr is None else stderr
    old_handlers = {}
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    folder = root / str(uuid.uuid4())
    folder.mkdir(mode=0o700)
    receipt = {"kind": "mechanisms-v1.claude-receipt/1", "argv": arguments,
               "argvBytesBase64": [base64.b64encode(os.fsencode(arg)).decode("ascii") for arg in arguments],
               "status": "refused", "environmentNames": sorted(environment()), "exitCode": None,
               "startedUTC": datetime.now(timezone.utc).isoformat()}
    code = 125
    try:
        child_path = resolve(executable)
        receipt.update(executable=str(child_path), executableSha256=digest(child_path.read_bytes()))
        probe = subprocess.run([str(child_path), "--version"], env=environment(), stdin=subprocess.DEVNULL,
                               cwd=cwd, capture_output=True, timeout=min(timeout, 15))
        (folder / "version.stdout").write_bytes(probe.stdout)
        (folder / "version.stderr").write_bytes(probe.stderr)
        receipt["version"] = {"stdoutSha256": digest(probe.stdout), "stderrSha256": digest(probe.stderr),
                              "exitCode": probe.returncode}
        if probe.returncode or not re.fullmatch(rb"2\.1\.322(?: \(Claude Code\))?\r?\n?", probe.stdout):
            raise ValueError("resolved claude version is not exactly " + VERSION)
        if digest(child_path.read_bytes()) != receipt["executableSha256"]:
            raise ValueError("claude executable changed during version check")
        for index, argument in enumerate(arguments[:-1]):
            if argument == "--system-prompt-file":
                prompt = Path(arguments[index + 1]).read_bytes()
                (folder / "system-prompt.bin").write_bytes(prompt)
                receipt["systemPromptSha256"] = digest(prompt)
        child = subprocess.Popen([str(child_path), *arguments], env=environment(),
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 cwd=cwd, start_new_session=True)
        def terminate(signum, frame):
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

        for signum in (signal.SIGTERM, signal.SIGINT):
            old_handlers[signum] = signal.signal(signum, terminate)
        stats = {}
        failures = []

        def copy(source, destination, name, is_input=False):
            seen, forwarded = hashlib.sha256(), hashlib.sha256()
            count = sent = 0
            forwarding = True
            try:
                with (folder / (name + ".bin")).open("xb") as saved:
                    while True:
                        chunk = os.read(source.fileno(), 65536)
                        if not chunk:
                            break
                        saved.write(chunk)
                        seen.update(chunk)
                        count += len(chunk)
                        if forwarding:
                            try:
                                offset = 0
                                while offset < len(chunk):
                                    written = os.write(destination.fileno(), chunk[offset:])
                                    forwarded.update(chunk[offset:offset + written])
                                    sent += written
                                    offset += written
                            except BrokenPipeError:
                                forwarding = False
                    saved.flush()
                    os.fsync(saved.fileno())
                stats[name] = {"bytes": count, "sha256": seen.hexdigest(), "forwardedBytes": sent,
                               "forwardedSha256": forwarded.hexdigest(), "equal": count == sent and
                               seen.digest() == forwarded.digest()}
            except Exception as error:
                failures.append(name + ": " + str(error))
            finally:
                if is_input:
                    destination.close()

        threads = [threading.Thread(target=copy, args=(stdin, child.stdin, "stdin", True), daemon=True),
                   threading.Thread(target=copy, args=(child.stdout, stdout, "stdout"), daemon=True),
                   threading.Thread(target=copy, args=(child.stderr, stderr, "stderr"), daemon=True)]
        for thread in threads:
            thread.start()
        try:
            code = child.wait(timeout=max(0.001, timeout - (time.monotonic() - started)))
            receipt["status"] = "exited"
        except subprocess.TimeoutExpired:
            receipt["status"] = "timeout"
            code = 124
        finally:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
        for thread in threads:
            thread.join(timeout=2)
        child.stdout.close()
        child.stderr.close()
        receipt.update(streams=stats, errors=failures,
                       passThrough=all(stats.get(name, {}).get("equal", False) for name in ("stdout", "stderr")))
        if failures or any(thread.is_alive() for thread in threads):
            receipt["status"] = "recording-error"
            code = 125
        receipt["childExitCode"] = child.returncode
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        receipt["error"] = str(error)
    finally:
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)
        receipt.update(exitCode=code, seconds=time.monotonic() - started,
                       endedUTC=datetime.now(timezone.utc).isoformat())
        data = (json.dumps(receipt, indent=2, ensure_ascii=True) + "\n").encode()
        (folder / "receipt.json").write_bytes(data)
        (folder / "receipt.sha256").write_text(digest(data) + "\n")
    return code if code >= 0 else 128 - code


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", default="claude")
    parser.add_argument("--record-dir", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--install", type=Path, help="create a claude wrapper here for Marty's PATH")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if not 0 < args.timeout <= 900:
        parser.error("timeout must be in (0, 900]")
    if args.install:
        executable = resolve(args.executable)
        args.install.mkdir(parents=True, exist_ok=False)
        wrapper = args.install / "claude"
        fixed = ["--executable", str(executable), "--record-dir", str(args.record_dir.resolve()),
                 "--timeout", str(args.timeout), "--"]
        wrapper.write_text("#!" + sys.executable + "\n# SPDX-License-Identifier: Apache-2.0\n"
                           "import sys\nsys.path.insert(0, " + repr(str(Path(__file__).resolve().parent)) + ")\n"
                           "from record import main\nraise SystemExit(main(" + repr(fixed) + " + sys.argv[1:]))\n")
        wrapper.chmod(0o700)
        return 0
    arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
    return record(args.executable, arguments, args.record_dir.resolve(), args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
