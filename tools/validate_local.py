# SPDX-License-Identifier: Apache-2.0
"""Offline candidate checks and a private receipt. Never publishes commit statuses."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import posixpath
import re
import shlex
import socket
import subprocess
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
# Natively verified tools without a Package.swift (docs/LOCAL-VALIDATION.md, "Native evidence").
NATIVE_TOOLS = ("tools/render-blender",)
# The native command sequence of each package, in order. docs/VERIFY-ON-MAC.md quotes this table verbatim and
# tools/write_native_receipt.py runs it. A package missing from it runs `swift test --jobs 2 --package-path P` when it
# has a Tests/ folder and `swift build --jobs 2 --package-path P` otherwise. EXPORT_DIR stands for a new directory
# outside the checkout.
EXPORT_DIR = "NEW_EXPORT_DIR"
PACKAGE_COMMANDS = {
    ".": ["swift build", "swift test"],
    "Examples/KeySwitch3D": ["swift test --jobs 2 --package-path Examples/KeySwitch3D"],
    "Examples/LessonDemo": ["swift test --jobs 2 --package-path Examples/LessonDemo"],
    "Examples/PathTrace": ["swift build --jobs 2 --package-path Examples/PathTrace"],
    "Examples/Showcase": ["swift build --jobs 2 --package-path Examples/Showcase",
                          "swift run --skip-build --package-path Examples/Showcase marty-showcase --verify",
                          "swift run --skip-build --package-path Examples/Showcase marty-showcase --export "
                          + EXPORT_DIR],
    "Examples/Solid3D": ["swift test --jobs 2 --package-path Examples/Solid3D"],
    "Examples/Turbofan": ["swift test --jobs 2 --package-path Examples/Turbofan"],
    "tools/SceneValidator": ["swift test --jobs 2 --package-path tools/SceneValidator",
                             "swift build -c release --jobs 2 --package-path tools/SceneValidator"],
    "tools/render-blender": ["tools/render-blender/selftest.sh"],
}
# Top-level folders of third-party code. A Package.swift there is not one of this repository's packages, and neither
# is one under a `.build` folder. A package that depends on vendored code still covers it (see manifest_inputs).
VENDOR_ROOTS = ("vendor", "third_party")
# What the root package builds and tests besides the folders its manifest names; its other top-level folders are not
# part of it.
ROOT_PACKAGE = ("Package.swift", "Package.resolved", "Sources/", "Tests/")
ROOT_MANIFEST = re.compile(r"Package@swift-[0-9.]+\.swift")
# A string literal that may name a repository path, up to the first character that cannot be in one.
SWIFT_PATH_LITERAL = re.compile(r'"([A-Za-z0-9_.+-][A-Za-z0-9_./+-]*)')
# Every complete one-line string literal of a package manifest.
MANIFEST_LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
MANIFEST_PATH_ARGUMENT = re.compile(r'\bpath\s*:\s*"((?:[^"\\\n]|\\.)*)"')
SYMLINK_MODE = "120000"
GITLINK_MODE = "160000"
REGULAR_MODES = ("100644", "100755")


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


def tree_entries(sha, root=None):
    """The committed tree of `sha` as {path: (mode, object id)}; never the working tree."""
    entries = {}
    for record in git("ls-tree", "-r", "-z", "--full-tree", sha, cwd=root).decode("utf-8", "surrogateescape").split("\0"):
        if record:
            meta, _, path = record.partition("\t")
            mode, _, oid = meta.split(" ")
            entries[path] = (mode, oid)
    return entries


def tree(sha, root=None):
    return sorted(tree_entries(sha, root))


def read_blobs(oids, root=None):
    """The bytes of each Git object id, read from the object database in one `git cat-file --batch`."""
    oids = sorted(set(oids))
    if not oids:
        return {}
    data = subprocess.run(["git", "cat-file", "--batch"], input="".join(o + "\n" for o in oids).encode(),
                          stdout=subprocess.PIPE, cwd=root or ROOT, check=True).stdout
    blobs, position = {}, 0
    for oid in oids:
        end = data.index(b"\n", position)
        header = data[position:end].split()
        if len(header) != 3:
            raise ValueError("Git object is missing: " + oid)
        size = int(header[2])
        blobs[oid] = data[end + 1:end + 1 + size]
        position = end + 1 + size + 1
    return blobs


def folders_of(paths):
    return {p.rsplit("/", n)[0] for p in paths for n in range(1, p.count("/") + 1)}


def discovered(path):
    """Whether package discovery looks at this path: never under a `.build` folder or a designated vendor root."""
    return ".build" not in path.split("/") and not any(path == v or path.startswith(v + "/") for v in VENDOR_ROOTS)


def native_packages(paths):
    """Every folder with a Package.swift ("." is the root package), plus each native tool that is present."""
    packages = {p.rpartition("/")[0] or "." for p in paths
                if p.rpartition("/")[2] == "Package.swift" and discovered(p)}
    packages.update(t for t in NATIVE_TOOLS if any(p.startswith(t + "/") for p in paths))
    return sorted(packages)


def default_command(package, paths):
    verb = "test" if any(p.startswith(package + "/Tests/") for p in paths) else "build"
    return "swift %s --jobs 2 --package-path %s" % (verb, package)


def native_commands(package, paths):
    """The documented command sequence (PACKAGE_COMMANDS) for one package of a tree with these paths."""
    return [shlex.split(c) for c in PACKAGE_COMMANDS.get(package, [default_command(package, paths)])]


def literal_inputs(paths, swift_sources):
    """Each existing repository file or folder that a Swift string literal names from the repository root.

    A literal names a path when its first component is a top-level file or folder of the tree and it is a whole
    top-level file name or has a slash. It is cut back to the deepest existing path, so a literal that ends in
    interpolation names the folder it starts in."""
    paths = set(paths)
    folders = folders_of(paths)
    top = {p.partition("/")[0] for p in paths}
    inputs = set()
    for text in swift_sources:
        for literal in SWIFT_PATH_LITERAL.findall(text):
            candidate = literal[2:] if literal.startswith("./") else literal
            candidate = candidate.rstrip("/")
            if candidate.partition("/")[0] not in top or ("/" not in literal and candidate not in paths):
                continue
            while candidate not in paths and candidate not in folders and "/" in candidate:
                candidate = candidate.rpartition("/")[0]
            inputs.add(candidate)
    return inputs


def manifest_inputs(package, manifest, paths, packages):
    """What a package manifest names outside the package's default layout: custom target paths, resources and local
    dependencies. Returns (inputs, external), where `external` lists `path:` arguments that leave the repository."""
    folders = folders_of(paths)
    exists = set(paths) | folders
    custom = MANIFEST_PATH_ARGUMENT.findall(manifest)
    base = "" if package == "." else package
    bases = [base] + sorted(f for f in folders if posixpath.dirname(f) in (
        posixpath.join(base, "Sources"), posixpath.join(base, "Tests")))
    bases += [posixpath.normpath(posixpath.join(base, c)) for c in custom]
    inputs, external = set(), set()
    for literal in MANIFEST_LITERAL.findall(manifest):
        if not literal or "://" in literal:
            continue
        for start in bases:
            if literal.startswith("/"):
                resolved = literal
            else:
                resolved = posixpath.normpath(posixpath.join(start, literal))
            if resolved.startswith("/") or resolved == ".." or resolved.startswith("../"):
                if start == base and literal in custom:
                    external.add(package + ": " + literal)
                continue
            if resolved in packages:
                continue  # a local dependency on one of the packages, which is covered as a package
            if resolved in exists:
                inputs.add(resolved)
    return inputs, external


def resolve_link(path, entries, folders, blobs, limit=32):
    """(target, reason, links): the repository path a committed symlink resolves to in its own tree, following
    chained links, or None with the reason ("external" or "unresolved") when it leaves the repository or names
    nothing in that tree; `links` are the other symlinks it passes through."""
    stack, pending, hops, via = path.split("/")[:-1], [], 0, []
    target = blobs[entries[path][1]].decode("utf-8", "surrogateescape")
    while True:
        if target.startswith("/"):
            return None, "external", via
        pending = target.split("/") + pending
        while pending:
            part = pending.pop(0)
            if part in ("", "."):
                continue
            if part == "..":
                if not stack:
                    return None, "external", via
                stack.pop()
                continue
            link = "/".join(stack + [part])
            entry = entries.get(link)
            if entry and entry[0] == SYMLINK_MODE:
                break
            stack.append(part)
        else:
            resolved = "/".join(stack) or "."
            if resolved == "." or resolved in entries or resolved in folders:
                return resolved, None, via
            return None, "unresolved", via
        hops += 1
        via.append(link)
        if hops > limit:
            return None, "unresolved", via
        target = blobs[entry[1]].decode("utf-8", "surrogateescape")


def native_inputs(paths, swift_sources, packages=(), manifests=()):
    """Files outside the packages that native builds and tests read: every Examples/ folder without a
    Package.swift, docs/fixtures, each existing repository file or folder named in a Swift string literal, and what a
    package manifest names outside its package. `manifests` is a sequence of (package, manifest text)."""
    paths = set(paths)
    folders = folders_of(paths)
    inputs = {"docs/fixtures"} & folders
    inputs.update(f for f in folders if f.count("/") == 1 and f.startswith("Examples/")
                  and f + "/Package.swift" not in paths)
    inputs |= literal_inputs(paths, swift_sources)
    for package, manifest in manifests:
        inputs |= manifest_inputs(package, manifest, paths, packages)[0]
    return dedupe(inputs, packages)


def dedupe(inputs, packages=()):
    """Leave out an input inside another input folder or inside a package's Sources/ or Tests/, each of which covers
    all of it, so the receipt lists each input once."""
    if "." in inputs:
        return ["."]
    whole = {posixpath.join("" if p == "." else p, f) for p in packages if p not in NATIVE_TOOLS for f in ("Sources", "Tests")}
    return sorted(i for i in inputs if not any(i.startswith(o + "/") for o in inputs)
                  and not any(i == w or i.startswith(w + "/") for w in whole))


def covers(path, packages, inputs):
    """Whether native evidence depends on these bytes. An input covers itself and, as a folder, everything in it.
    Markdown in a package outside its Sources/ and Tests/ is documentation, unless an input covers it."""
    if path in inputs or "." in inputs or any(path.startswith(i + "/") for i in inputs):
        return True
    for package in packages:
        if package == ".":
            if path in ROOT_PACKAGE or ROOT_MANIFEST.fullmatch(path) or path.startswith(ROOT_PACKAGE[2:]):
                return True
        elif path.startswith(package + "/"):
            if not path.endswith(".md") or path.startswith((package + "/Sources/", package + "/Tests/")):
                return True
    return False


def native_scope(trees, blobs):
    """The packages, inputs and symlink problems of the union of these committed trees.

    `trees` maps a label to {path: (mode, oid)}; `blobs` maps an object id to its bytes. Swift sources and package
    manifests come from these trees only. A covered symlink adds its tracked target as an input (as many times as
    needed to reach a fixed point); a covered symlink whose target leaves the repository or does not exist in its
    tree is a problem. A `.swift` symlink is scanned as the text of its target, whatever that is called; a symlinked
    manifest is read as a manifest of the link's package, and its target file is an input. A submodule
    (gitlink) at or under a covered path or a package folder is a problem: its files are not in either tree."""
    union = set().union(*(set(t) for t in trees.values()))
    packages = native_packages(union)
    swift, manifests, external, linked_manifests = [], [], set(), set()
    for entries in trees.values():
        folders = folders_of(entries)
        for path, (mode, oid) in entries.items():
            folder, _, name = path.rpartition("/")
            manifest = (name == "Package.swift" or ROOT_MANIFEST.fullmatch(name)) and (folder or ".") in packages
            if mode == SYMLINK_MODE and path.endswith(".swift"):
                target, oid = swift_link_target(path, entries, folders, blobs)
                if not oid:
                    continue
                if manifest:  # SwiftPM evaluates a linked manifest in the link's package folder
                    linked_manifests.add(target)
            elif mode not in REGULAR_MODES or not path.endswith(".swift"):
                continue
            text = blobs[oid].decode("utf-8", "replace")
            swift.append(text)
            if manifest:
                manifests.append((folder or ".", text))
    for package, manifest in manifests:
        external |= manifest_inputs(package, manifest, union, packages)[1]
    inputs = set(native_inputs(union, swift, packages, manifests)) | linked_manifests
    problems, seen = set(), None
    while seen != inputs:
        seen = set(inputs)
        for label, entries in trees.items():
            folders = folders_of(entries)
            for path, (mode, _) in entries.items():
                if mode == SYMLINK_MODE and covers(path, packages, inputs):
                    target, reason, via = resolve_link(path, entries, folders, blobs)
                    if target is None:
                        problems.add("%s -> %s (%s at %s)" % (
                            path, blobs[entries[path][1]].decode("utf-8", "replace"), reason, label))
                    inputs.update([p for p in via + [target] if p and not covers(p, packages, inputs)])
        inputs = set(dedupe(inputs, packages))
    problems |= {"%s (dependency outside the repository)" % e for e in external}
    for label, entries in trees.items():
        problems |= {"%s (submodule; its files are not in the tree at %s)" % (path, label)
                     for path, (mode, _) in entries.items() if mode == GITLINK_MODE and (
                         covers(path, packages, inputs) or any(path == p or path.startswith(p + "/") or p == "."
                                                               for p in packages))}
    return {"packages": packages, "inputs": sorted(inputs), "problems": sorted(problems)}


def swift_link_target(path, entries, folders, blobs):
    """(path, object id) of the regular file a `.swift` symlink resolves to in its tree, or (None, None)."""
    target = resolve_link(path, entries, folders, blobs)[0]
    entry = entries.get(target)
    return (target, entry[1]) if entry and entry[0] in REGULAR_MODES else (None, None)


def scope_blobs(trees, root):
    """Every blob native_scope reads: Swift sources, package manifests, symlinks and what `.swift` symlinks name."""
    wanted = []
    for entries in trees.values():
        wanted += [oid for path, (mode, oid) in entries.items()
                   if mode == SYMLINK_MODE or (mode in REGULAR_MODES and path.endswith(".swift"))]
    blobs = read_blobs(wanted, root)
    targets = []
    for entries in trees.values():
        folders = folders_of(entries)
        targets += [swift_link_target(path, entries, folders, blobs)[1] for path, (mode, _) in entries.items()
                    if mode == SYMLINK_MODE and path.endswith(".swift")]
    blobs.update(read_blobs([t for t in targets if t and t not in blobs], root))
    return blobs


def head_scope(sha, root=None):
    """The scope of one commit (what tools/write_native_receipt.py runs): its packages and their commands."""
    entries = tree_entries(sha, root)
    packages = native_packages(entries)
    return {p: native_commands(p, entries) for p in packages}


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


def receipt_mismatch(expected, receipt):
    """A receipt must name exactly the expected package paths, each with exit 0."""
    return {"missing": sorted(set(expected) - set(receipt)),
            "unexpected": sorted(set(receipt) - set(expected)),
            "failed": sorted(p for p, code in receipt.items() if code != 0)}


def native_reuse(source, head, receipt, root=None):
    """Whether a native receipt from `source` can vouch for `head`, both read from the Git objects of `root`.

    It cannot when any native byte (package or input) differs between the two trees, including added, removed and
    renamed files and packages; when a covered symlink leaves the repository or names nothing; or when the receipt
    does not name exactly the packages present at `head`, each with exit 0."""
    root = root or ROOT
    trees = {"source": tree_entries(source, root), "head": tree_entries(head, root)}
    scope = native_scope(trees, scope_blobs(trees, root))
    packages, inputs = scope["packages"], scope["inputs"]
    present = native_packages(trees["head"])
    diff = git("diff-tree", "-r", "-z", "--name-only", "--no-renames", source, head, cwd=root)
    changed = [p for p in diff.decode("utf-8", "surrogateescape").split("\0") if p and covers(p, packages, inputs)]
    mismatch = receipt_mismatch(present, receipt)
    failing = changed or scope["problems"] or any(mismatch.values())
    return {"source": source, "packages": present, "inputs": inputs, "changed": changed, **mismatch,
            "links": scope["problems"], "status": "FAIL" if failing else "PASS"}


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
        print(refusal(native, args.head))
    print("Private receipt:", receipt_path)
    return 0 if receipt["status"] == "PASS" else 1


def refusal(native, head):
    """Why a native receipt cannot vouch for `head`, and how to get one that can."""
    lines = ["Native receipt from %s cannot be reused for %s." % (native["source"], head)]
    for key, label in (("changed", "Changed native paths"), ("links", "Symlinks or dependencies outside the tree"),
                       ("missing", "Packages the receipt does not name"),
                       ("unexpected", "Receipt entries that are not packages at HEAD"),
                       ("failed", "Receipt entries with a non-zero exit")):
        if native[key]:
            lines.append("  %s: %s" % (label, ", ".join(native[key])))
    lines.append("Run the native checks in docs/VERIFY-ON-MAC.md at %s (python3 tools/write_native_receipt.py "
                 "/absolute/path/native-receipt.json), then rerun with --native-source %s and --native-receipt "
                 "/absolute/path/native-receipt.json." % (head, head))
    return "\n".join(lines)


if __name__ == "__main__":
    raise SystemExit(main())
