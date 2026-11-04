# SPDX-License-Identifier: Apache-2.0
"""Post-approval remote SPM smoke test; never creates a tag, release or status."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import socket
import subprocess
import sys


PUBLIC_URL = "https://github.com/morrowdock/martygraphics.git"
REPO = Path(__file__).resolve().parents[1]
NUMBER = r"(?:0|[1-9][0-9]*)"
IDENTIFIER = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
VERSION = rf"{NUMBER}\.{NUMBER}\.{NUMBER}(?:-{IDENTIFIER}(?:\.{IDENTIFIER})*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
CLIENT_SOURCE = '''// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

let envelope = try JSONSerialization.jsonObject(
    with: Data(MGGrammar.sceneExample.utf8)) as! [String: Any]
let patchEnvelope = try JSONSerialization.jsonObject(
    with: Data(MGGrammar.patchExample.utf8)) as! [String: Any]
let scene = try MGParser.scene(object: envelope["scene"]!).get()
let patch = try MGPatch.parse(object: patchEnvelope["patch"]!).get()
let updated = try scene.applying(patch).get()
precondition(updated.title == "Synthetic dot" && updated.revision == 1)
print("MartyGraphics remote scene/patch smoke passed")
'''


def release_tag(value):
    if not re.fullmatch("v?" + VERSION, value):
        raise argparse.ArgumentTypeError("Use an actual semantic version tag, optionally prefixed with v")
    return value


def commit_sha(value):
    if not re.fullmatch(r"[0-9a-fA-F]{40}", value):
        raise argparse.ArgumentTypeError("Use the full reviewed commit SHA")
    return value.lower()


def check_remote_tag(output, tag, expected):
    refs = dict(reversed(line.split()) for line in output.splitlines() if line.strip())
    ref = "refs/tags/" + tag
    if ref not in refs or refs.get(ref + "^{}", refs[ref]).lower() != expected:
        raise ValueError("Remote tag is absent or does not resolve to the reviewed commit")


def manifest(version):
    return f'''// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
import PackageDescription
let package = Package(
    name: "MGRemoteSmoke",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "{PUBLIC_URL}", exact: "{version}")],
    targets: [.executableTarget(name: "MGRemoteSmoke", dependencies: [
        .product(name: "MartyGraphics", package: "martygraphics")
    ])]
)
'''


def check_pin(path, version, expected):
    resolved = json.loads(path.read_text(encoding="utf-8"))
    pins = resolved.get("pins", [])
    if resolved.get("version") not in (2, 3) or len(pins) != 1:
        raise ValueError("Expected one remote dependency in a Swift 6 resolved file")
    pin = pins[0]
    state = pin.get("state", {})
    if (pin.get("identity") != "martygraphics" or pin.get("kind") != "remoteSourceControl"
            or pin.get("location") != PUBLIC_URL or state.get("version") != version
            or state.get("revision", "").lower() != expected):
        raise ValueError("Resolved dependency differs from the reviewed remote version/commit")


def main(args=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True, type=release_tag)
    parser.add_argument("--commit", required=True, type=commit_sha)
    parser.add_argument("--output", required=True, type=Path, help="NEW private directory outside this checkout")
    options = parser.parse_args(args)
    root = options.output.resolve()
    if root.is_relative_to(REPO) or root.exists():
        parser.error("Output must be a new private directory outside this checkout")
    if platform.system() != "Darwin":
        parser.error("The public package requires Apple frameworks; run this test on an approved Mac")
    version = options.tag.removeprefix("v")
    root.mkdir(parents=True, exist_ok=False)
    (root / "logs").mkdir()
    blocked = {"GH_TOKEN", "GITHUB_TOKEN", "GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG_COUNT",
               "GIT_CONFIG_PARAMETERS", "GIT_ASKPASS", "SSH_ASKPASS"}
    env = {key: value for key, value in os.environ.items() if key not in blocked}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT="0")
    receipt = {"repository": PUBLIC_URL, "tag": options.tag, "reviewedCommit": options.commit,
               "version": version, "host": socket.gethostname(), "platform": platform.platform(),
               "runnerSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "startedUTC": datetime.now(timezone.utc).isoformat(), "commands": [], "status": "INCOMPLETE",
               "scope": "Remote package smoke only; approval is external; no UI/device/adopter acceptance"}

    def save():
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")

    def run(argv):
        try:
            result = subprocess.run(argv, cwd=root, env=env, text=True, capture_output=True, timeout=600)
        except subprocess.TimeoutExpired as error:
            def decoded(value):
                return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else value or ""
            result = subprocess.CompletedProcess(argv, 124, decoded(error.stdout),
                                                 decoded(error.stderr) + "\nCommand exceeded 600 seconds")
        entry = {"argv": argv, "exit": result.returncode}
        for channel in ("stdout", "stderr"):
            raw = getattr(result, channel).encode("utf-8")
            relative = f"logs/{len(receipt['commands']):02d}-{channel}.txt"
            (root / relative).write_bytes(raw)
            entry[channel] = {"path": relative, "sha256": hashlib.sha256(raw).hexdigest()}
        receipt["commands"].append(entry)
        save()
        if result.returncode:
            raise RuntimeError("Command failed; inspect private command logs")
        return result.stdout

    try:
        ref_command = ["git", "-c", "credential.helper=", "ls-remote", "--exit-code", "--tags",
                       PUBLIC_URL, "refs/tags/" + options.tag, "refs/tags/" + options.tag + "^{}"]
        check_remote_tag(run(ref_command), options.tag, options.commit)
        (root / "Package.swift").write_text(manifest(version), encoding="utf-8")
        source = root / "Sources/MGRemoteSmoke/main.swift"
        source.parent.mkdir(parents=True)
        source.write_text(CLIENT_SOURCE, encoding="utf-8")
        run(["swift", "--version"])
        swift_options = ["--package-path", str(root), "--cache-path", str(root / "cache"),
                         "--config-path", str(root / "config"), "--security-path", str(root / "security"),
                         "--disable-netrc", "--disable-keychain", "--disable-dependency-cache"]
        run(["swift", "package", *swift_options, "resolve"])
        check_pin(root / "Package.resolved", version, options.commit)
        checkout = root / ".build/checkouts/martygraphics"
        actual = run(["git", "-C", str(checkout), "rev-parse", "HEAD"]).strip().lower()
        if actual != options.commit:
            raise ValueError("Dependency checkout differs from the reviewed commit")
        run(["swift", "build", *swift_options, "--force-resolved-versions"])
        run(["swift", "run", *swift_options, "--force-resolved-versions", "--skip-build", "MGRemoteSmoke"])
        check_pin(root / "Package.resolved", version, options.commit)
        check_remote_tag(run(ref_command), options.tag, options.commit)
        receipt["status"] = "PASS"
    except (OSError, ValueError, RuntimeError) as error:
        receipt["status"] = "FAIL"
        receipt["failure"] = str(error)
    receipt["finishedUTC"] = datetime.now(timezone.utc).isoformat()
    receipt["consumerFiles"] = {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                                for path in (root / "Package.swift", root / "Package.resolved",
                                             root / "Sources/MGRemoteSmoke/main.swift") if path.exists()}
    save()
    print(receipt["status"] + "; private evidence: " + str(root))
    return 0 if receipt["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
