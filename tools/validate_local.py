# SPDX-License-Identifier: Apache-2.0
"""Offline candidate checks and a private receipt. Never publishes commit statuses."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import re
import socket
import subprocess
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def full_sha(value):
    if not re.fullmatch(r"[0-9a-fA-F]{40}", value):
        raise argparse.ArgumentTypeError("Use a full commit SHA")
    return value.lower()


def check_files():
    paths = [p for p in git("ls-files", "-z").decode().split("\0") if p]
    expected = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
                for p in paths if p != "FILES.json"}
    actual = json.loads((ROOT / "FILES.json").read_text(encoding="utf-8"))
    if {f["path"]: f["sha256"] for f in actual["files"]} != expected:
        raise ValueError("FILES.json does not match the candidate")
    for name in paths:
        path = ROOT / name
        if path.suffix == ".json":
            json.loads(path.read_text(encoding="utf-8"))
        if path.suffix in (".swift", ".py"):
            if "SPDX-License-Identifier: Apache-2.0" not in "\n".join(path.read_text(encoding="utf-8").splitlines()[:3]):
                raise ValueError("Missing source license: " + name)
        if path.suffix != ".md":
            continue
        text = path.read_text(encoding="utf-8")
        links = re.findall(r'\]\(([^\s)]+)(?:\s+"[^"]*")?\)', text)
        links += re.findall(r'(?:src|href)="([^"]+)"', text)
        for link in links:
            split = urlsplit(link)
            if split.scheme or link.startswith("#"):
                continue
            target = (path.parent / unquote(split.path)).resolve()
            if not target.is_relative_to(ROOT) or not target.exists():
                raise ValueError("Broken or escaping relative link in " + name)
    print("PASS: manifest, JSON, source licenses and relative file links")


def main():
    if sys.argv[1:] == ["--check-files"]:
        check_files()
        return 0
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, type=full_sha)
    parser.add_argument("--head", required=True, type=full_sha)
    parser.add_argument("--gitleaks", required=True, help="Path to an installed portable Gitleaks binary")
    parser.add_argument("--receipt", required=True, type=Path, help="NEW private JSON path outside the checkout")
    parser.add_argument("--native-source", type=full_sha, help="Previously tested native source; check byte equivalence")
    args = parser.parse_args()
    receipt_path = args.receipt.resolve()
    if receipt_path.is_relative_to(ROOT) or receipt_path.exists():
        parser.error("Receipt must be a new path outside the checkout")
    if git("rev-parse", "HEAD").decode().strip() != args.head:
        parser.error("Checkout HEAD differs from the pinned candidate")
    if git("status", "--porcelain").strip():
        parser.error("Candidate checkout must be clean, including untracked files")
    for sha in (args.base, args.head):
        git("cat-file", "-e", sha + "^{commit}")
    leak_report = receipt_path.with_suffix(".gitleaks.json")
    if leak_report.exists():
        parser.error("Gitleaks report path already exists")
    commands = [
        ["git", "diff", "--check", args.base, args.head],
        [sys.executable, "-m", "unittest", "discover", "-s", "tools/tests", "-v"],
        [sys.executable, "tools/check_dco.py", args.base, args.head],
        [sys.executable, "tools/validate_local.py", "--check-files"],
        [args.gitleaks, "git", ".", "--log-opts=--all", "--redact", "--report-format", "json", "--report-path", str(leak_report)],
    ]
    if args.native_source:
        commands.append(["git", "diff", "--exit-code", args.native_source, args.head, "--",
                         "Sources", "Tests", "Package.swift", "Examples/Showcase/Package.swift",
                         "Examples/Showcase/Sources", "docs/fixtures", "Examples/UnitCircle/Package.swift",
                         "Examples/UnitCircle/Sources", "tools/SceneValidator/Package.swift",
                         "tools/SceneValidator/Sources", "tools/SceneValidator/Tests"])
    receipt = {"head": args.head, "base": args.base, "capturedUTC": datetime.now(timezone.utc).isoformat(),
               "host": socket.gethostname(), "platform": platform.platform(), "python": sys.version,
               "nativeSource": args.native_source, "nativeEvidence": "Separate Mac build/test/export receipt required",
               "scope": "Local hygiene only; no hosted check, accessibility/performance acceptance or status publication",
               "commands": []}
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    for command in commands:
        result = subprocess.run(command, cwd=ROOT)
        receipt["commands"].append({"argv": command, "exit": result.returncode})
    receipt["status"] = "PASS" if all(c["exit"] == 0 for c in receipt["commands"]) else "FAIL"
    with receipt_path.open("x", encoding="utf-8") as stream:
        json.dump(receipt, stream, indent=2)
        stream.write("\n")
    print("Private receipt:", receipt_path)
    return 0 if receipt["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
