# SPDX-License-Identifier: Apache-2.0
"""Post-approval remote SPM smoke test; never creates a tag, release or status."""

import argparse
from dataclasses import dataclass
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
APPROVED_DEVELOPERS = {
    Path("/Applications/Xcode.app/Contents/Developer"): (
        "Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
        "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"),
    Path("/Library/Developer/CommandLineTools"): ("usr/bin/swift", "SDKs/MacOSX.sdk"),
}
GIT_OVERRIDES = (
    ("credential.helper", ""), ("credential.interactive", "false"),
    ("core.askPass", "/usr/bin/false"), ("http.extraHeader", ""),
    ("http.cookieFile", ""), ("http.saveCookies", "false"), ("http.proxy", ""),
    ("protocol.allow", "never"), ("protocol.https.allow", "always"),
)
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


@dataclass(frozen=True)
class AppleTools:
    git: Path
    swift: Path
    developer: Path
    sdk: Path
    git_exec: Path


def resolve_apple_tools(developer):
    """Use fixed approved installation roots, not PATH/xcrun/environment discovery."""
    if developer not in APPROVED_DEVELOPERS or developer.resolve(strict=True) != developer:
        raise ValueError("Select a canonical approved Apple developer installation")
    swift_relative, sdk_relative = APPROVED_DEVELOPERS[developer]

    def inside(relative, directory=False):
        path = (developer / relative).resolve(strict=True)
        if not path.is_relative_to(developer) or not (path.is_dir() if directory else path.is_file()):
            raise ValueError("Apple installation path escapes its approved root or has the wrong type")
        if not directory and not os.access(path, os.X_OK):
            raise ValueError("Apple installation executable is unavailable")
        return path

    swift = inside(swift_relative)
    sdk = inside(sdk_relative, directory=True)
    git_exec = inside("usr/libexec/git-core", directory=True)
    inside("usr/libexec/git-core/git-remote-https")
    git = Path("/usr/bin/git")
    for executable in (git, Path("/usr/bin/false")):
        if executable.resolve(strict=True) != executable or not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError("Expected canonical system executable unavailable")
    return AppleTools(git, swift, developer, sdk, git_exec)


def isolated_environment(root, tools):
    """Construct the complete child environment; copy nothing from os.environ."""
    for relative in ("home", "home/.ssh", "config", "cache", "data", "state", "security", "tmp"):
        (root / relative).mkdir(mode=0o700, parents=True, exist_ok=True)
    for relative in ("home/.netrc", "home/.gitconfig", "home/.curlrc", "config/gitconfig", "config/git-system"):
        path = root / relative
        with path.open("x", encoding="utf-8"):
            pass
        path.chmod(0o600)
    home = str(root / "home")
    env = {
        "HOME": home, "CFFIXED_USER_HOME": home, "CURL_HOME": home,
        "XDG_CONFIG_HOME": str(root / "config"), "XDG_CACHE_HOME": str(root / "cache"),
        "XDG_DATA_HOME": str(root / "data"), "XDG_STATE_HOME": str(root / "state"),
        "TMPDIR": str(root / "tmp") + os.sep,
        "PATH": os.pathsep.join(("/usr/bin", "/bin", "/usr/sbin", "/sbin", str(tools.swift.parent))),
        "LANG": "C", "LC_ALL": "C", "DEVELOPER_DIR": str(tools.developer), "SDKROOT": str(tools.sdk),
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_SYSTEM": str(root / "config/git-system"),
        "GIT_CONFIG_GLOBAL": str(root / "config/gitconfig"), "GIT_CONFIG_COUNT": str(len(GIT_OVERRIDES)),
        "GIT_EXEC_PATH": str(tools.git_exec), "GIT_TERMINAL_PROMPT": "0",
        "GIT_ASKPASS": "/usr/bin/false", "SSH_ASKPASS": "/usr/bin/false",
    }
    for index, (key, value) in enumerate(GIT_OVERRIDES):
        env[f"GIT_CONFIG_KEY_{index}"] = key
        env[f"GIT_CONFIG_VALUE_{index}"] = value
    return env


def main(args=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True, type=release_tag)
    parser.add_argument("--commit", required=True, type=commit_sha)
    parser.add_argument("--output", required=True, type=Path, help="NEW private directory outside this checkout")
    parser.add_argument("--developer-dir", type=Path, default=Path("/Applications/Xcode.app/Contents/Developer"),
                        help="Canonical Xcode.app developer directory (default), or /Library/Developer/CommandLineTools")
    options = parser.parse_args(args)
    root = options.output.resolve()
    if root.is_relative_to(REPO) or root.exists():
        parser.error("Output must be a new private directory outside this checkout")
    if platform.system() != "Darwin":
        parser.error("The public package requires Apple frameworks; run this test on an approved Mac")
    try:
        tools = resolve_apple_tools(options.developer_dir)
    except (OSError, ValueError) as error:
        parser.error("Approved Apple tools unavailable: " + str(error))
    version = options.tag.removeprefix("v")
    root.mkdir(mode=0o700, parents=True, exist_ok=False)
    (root / "logs").mkdir()
    env = isolated_environment(root, tools)
    receipt = {"repository": PUBLIC_URL, "tag": options.tag, "reviewedCommit": options.commit,
               "version": version, "host": socket.gethostname(), "platform": platform.platform(),
               "runnerSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "runtime": {"git": str(tools.git), "swift": str(tools.swift), "developer": str(tools.developer),
                           "sdk": str(tools.sdk), "gitExec": str(tools.git_exec), "environmentKeys": sorted(env)},
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
        ref_command = [str(tools.git), "ls-remote", "--exit-code", "--tags",
                       PUBLIC_URL, "refs/tags/" + options.tag, "refs/tags/" + options.tag + "^{}"]
        check_remote_tag(run(ref_command), options.tag, options.commit)
        (root / "Package.swift").write_text(manifest(version), encoding="utf-8")
        source = root / "Sources/MGRemoteSmoke/main.swift"
        source.parent.mkdir(parents=True)
        source.write_text(CLIENT_SOURCE, encoding="utf-8")
        run([str(tools.swift), "--version"])
        swift_options = ["--package-path", str(root), "--cache-path", str(root / "cache"),
                         "--config-path", str(root / "config"), "--security-path", str(root / "security"),
                         "--disable-netrc", "--disable-keychain", "--disable-dependency-cache"]
        run([str(tools.swift), "package", *swift_options, "resolve"])
        check_pin(root / "Package.resolved", version, options.commit)
        checkout = root / ".build/checkouts/martygraphics"
        actual = run([str(tools.git), "-C", str(checkout), "rev-parse", "HEAD"]).strip().lower()
        if actual != options.commit:
            raise ValueError("Dependency checkout differs from the reviewed commit")
        run([str(tools.swift), "build", *swift_options, "--force-resolved-versions"])
        run([str(tools.swift), "run", *swift_options, "--force-resolved-versions", "--skip-build", "MGRemoteSmoke"])
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
