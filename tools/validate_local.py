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
# Natively verified tools without a Package.swift (docs/LOCAL-VALIDATION.md, "Native evidence").
NATIVE_TOOLS = ("tools/render-blender",)
# What the root package builds and tests; its other top-level folders are not part of it.
ROOT_PACKAGE = ("Package.swift", "Package.resolved", "Sources/", "Tests/")
# A repository path named in a Swift string literal, up to the first character that cannot be in one.
SWIFT_PATH_LITERAL = re.compile(r'"((?:docs|Examples|tools|benchmark)/[A-Za-z0-9_./+-]*)')


def git(*args, cwd=None):
    return subprocess.check_output(["git", *args], cwd=cwd or ROOT)


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


def tree(sha, root=None):
    return [p for p in git("ls-tree", "-r", "-z", "--name-only", sha, cwd=root).decode().split("\0") if p]


def native_packages(paths):
    """Every folder with a Package.swift ("." is the root package), plus each native tool that is present."""
    packages = {p.rpartition("/")[0] or "." for p in paths if p.rpartition("/")[2] == "Package.swift"}
    packages.update(t for t in NATIVE_TOOLS if any(p.startswith(t + "/") for p in paths))
    return sorted(packages)


def native_inputs(paths, swift_sources, packages=()):
    """Files outside the packages that native builds and tests read: every Examples/ folder without a
    Package.swift, docs/fixtures, and each existing repository file or folder named in a Swift string literal."""
    paths = set(paths)
    folders = {p.rsplit("/", n)[0] for p in paths for n in range(1, p.count("/") + 1)}
    inputs = {"docs/fixtures"} & folders
    inputs.update(f for f in folders if f.count("/") == 1 and f.startswith("Examples/")
                  and f + "/Package.swift" not in paths)
    for text in swift_sources:
        for literal in SWIFT_PATH_LITERAL.findall(text):
            candidate = literal.rstrip("/")
            while candidate.count("/") >= 1 and candidate not in paths and candidate not in folders:
                candidate = candidate.rpartition("/")[0]
            if candidate.count("/") >= 1:
                inputs.add(candidate)
    # Leave out what a package or another input already covers, so the receipt lists each input once.
    return sorted(i for i in inputs if i.endswith(".md") or not covers(i + "/x", packages, inputs - {i}))


def covers(path, packages, inputs):
    """Whether native evidence depends on these bytes. Markdown outside Sources/ and Tests/ is documentation,
    unless a Swift literal names that exact file (a test reads it)."""
    if path in inputs:
        return True
    for package in packages:
        if package == ".":
            if path in ROOT_PACKAGE or path.startswith(ROOT_PACKAGE[2:]):
                return True
        elif path.startswith(package + "/"):
            if not path.endswith(".md") or path.startswith((package + "/Sources/", package + "/Tests/")):
                return True
    return any(path.startswith(folder + "/") and not path.endswith(".md") for folder in inputs)


def read_native_receipt(path, source):
    """A native receipt names each package it built and tested, with that package's overall exit code."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict) or str(data.get("source", "")).lower() != source:
        raise ValueError("Native receipt does not name the tested native source " + source)
    entries = data.get("packages")
    if not isinstance(entries, list) or not all(
            isinstance(e, dict) and isinstance(e.get("path"), str) and type(e.get("exit")) is int for e in entries):
        raise ValueError('Native receipt needs "packages": [{"path": ..., "exit": ...}, ...]')
    names = [e["path"] for e in entries]
    if len(set(names)) != len(names):
        raise ValueError("Native receipt names a package twice")
    return {e["path"]: e["exit"] for e in entries}


def native_reuse(source, head, receipt, root=None):
    """Whether a native receipt from `source` can vouch for `head`, whose checkout is `root`.

    It cannot when any native byte (package or input) differs between the two trees, including added and removed
    files and packages, or when the receipt does not name every package present at `head` with exit 0."""
    root = root or ROOT
    old, new = tree(source, root), tree(head, root)
    union = set(old) | set(new)
    packages = native_packages(union)
    present = native_packages(new)
    swift = [(root / p).read_text(encoding="utf-8") for p in new if p.endswith(".swift")]
    inputs = native_inputs(union, swift, packages)
    changed = [p for p in git("diff", "--name-only", "-z", "--no-renames", source, head, cwd=root).decode().split("\0")
               if p and covers(p, packages, inputs)]
    uncovered = [p for p in present if receipt.get(p) != 0]
    return {"source": source, "packages": present, "inputs": inputs, "changed": changed, "uncovered": uncovered,
            "status": "FAIL" if changed or uncovered else "PASS"}


def main():
    if sys.argv[1:] == ["--check-files"]:
        check_files()
        return 0
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, type=full_sha)
    parser.add_argument("--head", required=True, type=full_sha)
    parser.add_argument("--gitleaks", required=True, help="Path to an installed portable Gitleaks binary")
    parser.add_argument("--receipt", required=True, type=Path, help="NEW private JSON path outside the checkout")
    parser.add_argument("--native-source", type=full_sha, help="Previously tested native source; check reuse")
    parser.add_argument("--native-receipt", type=Path, help="That source's native receipt naming each package")
    args = parser.parse_args()
    if bool(args.native_source) != bool(args.native_receipt):
        parser.error("--native-source and --native-receipt go together")
    receipt_path = args.receipt.resolve()
    if receipt_path.is_relative_to(ROOT) or receipt_path.exists():
        parser.error("Receipt must be a new path outside the checkout")
    if git("rev-parse", "HEAD").decode().strip() != args.head:
        parser.error("Checkout HEAD differs from the pinned candidate")
    if git("status", "--porcelain").strip():
        parser.error("Candidate checkout must be clean, including untracked files")
    for sha in filter(None, (args.base, args.head, args.native_source)):
        git("cat-file", "-e", sha + "^{commit}")
    native = None
    if args.native_source:
        try:
            native = native_reuse(args.native_source, args.head, read_native_receipt(args.native_receipt, args.native_source))
        except (OSError, ValueError) as error:
            parser.error(str(error))
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
    receipt = {"head": args.head, "base": args.base, "capturedUTC": datetime.now(timezone.utc).isoformat(),
               "host": socket.gethostname(), "platform": platform.platform(), "python": sys.version,
               "nativeSource": args.native_source, "nativeReuse": native,
               "nativeEvidence": "A separate native receipt naming each package is required",
               "scope": "Local hygiene only; no hosted check, accessibility/performance acceptance or status publication",
               "commands": []}
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    for command in commands:
        result = subprocess.run(command, cwd=ROOT)
        receipt["commands"].append({"argv": command, "exit": result.returncode})
    passed = all(c["exit"] == 0 for c in receipt["commands"]) and (native is None or native["status"] == "PASS")
    receipt["status"] = "PASS" if passed else "FAIL"
    with receipt_path.open("x", encoding="utf-8") as stream:
        json.dump(receipt, stream, indent=2)
        stream.write("\n")
    if native and native["status"] == "FAIL":
        print("Native receipt cannot be reused. Changed:", native["changed"], "Not covered:", native["uncovered"])
    print("Private receipt:", receipt_path)
    return 0 if receipt["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
