# SPDX-License-Identifier: Apache-2.0
"""Offline checks only. Synthetic versions/hashes are not real release evidence."""

import argparse
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("release_install", Path(__file__).resolve().parents[1] / "verify_release_install.py")
SMOKE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SMOKE)
REAL_RESOLVER = SMOKE.resolve_apple_tools
SYNTHETIC_TAG = "1.2.3-fixture"
SYNTHETIC_SHA = "a" * 40


class ReleaseInstallTests(unittest.TestCase):
    def setUp(self):
        self.tools = SMOKE.AppleTools(
            Path("/usr/bin/git"), Path("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"),
            Path("/Applications/Xcode.app/Contents/Developer"),
            Path("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"),
            Path("/Applications/Xcode.app/Contents/Developer/usr/libexec/git-core"))
        resolver = patch.object(SMOKE, "resolve_apple_tools", return_value=self.tools)
        resolver.start()
        self.addCleanup(resolver.stop)
        # Keep host metadata probes outside the mocked release-command boundary.
        # Cold macOS platform.platform() itself can invoke uname and file.
        metadata = patch.object(SMOKE.platform, "platform", return_value="synthetic-offline-host")
        metadata.start()
        self.addCleanup(metadata.stop)

    def test_poisoned_environment_is_not_inherited(self):
        with tempfile.TemporaryDirectory() as directory:
            poison = Path(directory) / "personal-home"
            poison.mkdir()
            (poison / ".netrc").write_text("synthetic fixture, no credentials\n")
            (poison / ".gitconfig").write_text("[credential]\nhelper = synthetic-helper\n")
            output = Path(directory) / "new"
            inherited = {"HOME": str(poison), "PATH": str(poison / "bin"),
                         "GIT_TRACE": str(poison / "trace"), "GIT_TRACE_CURL": "1",
                         "GIT_EXEC_PATH": str(poison / "git-core"), "NETRC": str(poison / ".netrc"),
                         "CURL_HOME": str(poison), "XDG_CONFIG_HOME": str(poison / "config"),
                         "GIT_CONFIG_PARAMETERS": "synthetic configuration", "SDKROOT": str(poison / "sdk")}
            def inspect(argv, **kwargs):
                env = kwargs["env"]
                self.assertNotEqual(env.get("HOME"), str(poison))
                self.assertNotEqual(env.get("PATH"), inherited["PATH"])
                self.assertNotIn("GIT_TRACE", env)
                self.assertNotIn("GIT_TRACE_CURL", env)
                self.assertNotIn("NETRC", env)
                self.assertNotIn("GIT_CONFIG_PARAMETERS", env)
                return subprocess.CompletedProcess(argv, 1, "", "synthetic stop")
            with patch.object(SMOKE.platform, "system", return_value="Darwin"), \
                    patch.dict(SMOKE.os.environ, inherited), \
                    patch.object(SMOKE.subprocess, "run", side_effect=inspect), redirect_stdout(io.StringIO()):
                self.assertEqual(SMOKE.main(["--tag", SYNTHETIC_TAG, "--commit", SYNTHETIC_SHA,
                                             "--output", str(output)]), 1)

    def test_allowlist_and_git_policy_are_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = SMOKE.isolated_environment(root, self.tools)
            keys = {"HOME", "CFFIXED_USER_HOME", "CURL_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
                    "XDG_DATA_HOME", "XDG_STATE_HOME", "TMPDIR", "PATH", "LANG", "LC_ALL",
                    "DEVELOPER_DIR", "SDKROOT", "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_SYSTEM",
                    "GIT_CONFIG_GLOBAL", "GIT_CONFIG_COUNT", "GIT_EXEC_PATH", "GIT_TERMINAL_PROMPT",
                    "GIT_ASKPASS", "SSH_ASKPASS"}
            keys.update(f"GIT_CONFIG_{part}_{index}" for part in ("KEY", "VALUE") for index in range(9))
            self.assertEqual(set(env), keys)
            overrides = {env[f"GIT_CONFIG_KEY_{i}"]: env[f"GIT_CONFIG_VALUE_{i}"] for i in range(9)}
            self.assertEqual(overrides["credential.helper"], "")
            self.assertEqual(overrides["credential.interactive"], "false")
            self.assertEqual(overrides["http.extraHeader"], "")
            self.assertEqual(overrides["protocol.allow"], "never")
            self.assertEqual(overrides["protocol.https.allow"], "always")
            self.assertEqual(env["GIT_EXEC_PATH"], str(self.tools.git_exec))
            self.assertEqual(env["DEVELOPER_DIR"], str(self.tools.developer))
            self.assertEqual(env["SDKROOT"], str(self.tools.sdk))
            self.assertEqual(env["PATH"].split(SMOKE.os.pathsep),
                             ["/usr/bin", "/bin", "/usr/sbin", "/sbin", str(self.tools.swift.parent)])
            for name in ("HOME", "CFFIXED_USER_HOME", "CURL_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
                         "XDG_DATA_HOME", "XDG_STATE_HOME", "TMPDIR"):
                self.assertTrue(Path(env[name]).resolve().is_relative_to(root.resolve()))
            self.assertEqual((root / "home/.netrc").read_bytes(), b"")
            self.assertEqual(Path(env["GIT_CONFIG_GLOBAL"]).read_bytes(), b"")
            self.assertEqual(list((root / "home/.ssh").iterdir()), [])

    def test_nested_swift_to_git_environment_contract_with_offline_standins(self):
        # Real Python children stand in for Swift and its Git child; neither real tool runs.
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            poison = base / "personal-home"
            poison.mkdir()
            (poison / ".netrc").write_text("synthetic personal netrc fixture\n")
            (poison / ".gitconfig").write_text("[credential]\nhelper=synthetic-helper\n")
            (poison / ".ssh").mkdir()
            (poison / ".ssh/config").write_text("synthetic fixture, no key\n")
            root = base / "isolated"
            root.mkdir()
            inherited = {"HOME": str(poison), "CURL_HOME": str(poison), "NETRC": str(poison / ".netrc"),
                         "PATH": str(poison / "bin"), "GIT_CONFIG_COUNT": "1",
                         "GIT_CONFIG_KEY_0": "credential.helper", "GIT_CONFIG_VALUE_0": "synthetic-helper",
                         "GIT_CONFIG_PARAMETERS": "synthetic injected configuration", "GIT_TRACE": str(poison / "trace"),
                         "GIT_TRACE_CURL": "1", "GIT_TRACE2_EVENT": str(poison / "trace2"),
                         "GIT_EXEC_PATH": str(poison / "git-core"), "SSH_AUTH_SOCK": str(poison / "agent"),
                         "SWIFT_EXEC": str(poison / "swift"), "SDKROOT": str(poison / "sdk"),
                         "DEVELOPER_DIR": str(poison / "developer"), "DYLD_INSERT_LIBRARIES": str(poison / "inject"),
                         "HTTP_PROXY": "synthetic", "GITHUB_TOKEN": "synthetic"}
            with patch.dict(SMOKE.os.environ, inherited):
                env = SMOKE.isolated_environment(root, self.tools)
            fake_git = base / "git_standin.py"
            fake_git.write_text('''import json, os, pathlib, sys
home = pathlib.Path(os.environ["HOME"])
assert (home / ".netrc").read_bytes() == b""
assert (home / ".gitconfig").read_bytes() == b""
assert list((home / ".ssh").iterdir()) == []
assert pathlib.Path(os.environ["GIT_CONFIG_GLOBAL"]).read_bytes() == b""
assert os.environ["GIT_CONFIG_NOSYSTEM"] == "1"
assert os.environ["GIT_TERMINAL_PROMPT"] == "0"
policy = {os.environ[f"GIT_CONFIG_KEY_{i}"]: os.environ[f"GIT_CONFIG_VALUE_{i}"]
          for i in range(int(os.environ["GIT_CONFIG_COUNT"]))}
assert policy["credential.helper"] == "" and policy["credential.interactive"] == "false"
assert policy["protocol.allow"] == "never" and policy["protocol.https.allow"] == "always"
for key in ("NETRC", "GIT_CONFIG_PARAMETERS", "GIT_TRACE", "GIT_TRACE_CURL", "GIT_TRACE2_EVENT",
            "SSH_AUTH_SOCK", "SWIFT_EXEC", "DYLD_INSERT_LIBRARIES", "HTTP_PROXY", "GITHUB_TOKEN"):
    assert key not in os.environ, key
pathlib.Path(sys.argv[1]).write_text(json.dumps(dict(os.environ)))
''', encoding="utf-8")
            fake_swift = base / "swift_standin.py"
            fake_swift.write_text('''import subprocess, sys
subprocess.run([sys.executable, sys.argv[1], sys.argv[2]], check=True)
''', encoding="utf-8")
            report = base / "child.json"
            completed = subprocess.run([sys.executable, str(fake_swift), str(fake_git), str(report)],
                                       env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            child = json.loads(report.read_text())
            for key in env:
                self.assertEqual(child[key], env[key], key)
            self.assertNotIn(str(poison), child["HOME"])
            self.assertNotIn(str(poison), child["PATH"])
            self.assertFalse((poison / "trace").exists())
            self.assertFalse((poison / "trace2").exists())
            self.assertEqual((poison / ".netrc").read_text(), "synthetic personal netrc fixture\n")

    def test_unapproved_developer_root_and_escape_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            developer = Path(directory) / "developer"
            developer.mkdir()
            outside = Path(directory) / "outside-swift"
            outside.write_text("synthetic, never executed")
            with self.assertRaises(ValueError):
                REAL_RESOLVER(developer)
            def resolved(candidate, **kwargs):
                return outside if candidate == developer / "usr/bin/swift" else candidate
            with patch.dict(SMOKE.APPROVED_DEVELOPERS, {developer: ("usr/bin/swift", "sdk")}, clear=True), \
                    patch.object(Path, "resolve", autospec=True, side_effect=resolved), self.assertRaises(ValueError):
                REAL_RESOLVER(developer)

    def test_tag_and_sha_argument_bounds(self):
        for tag in (SYNTHETIC_TAG, "v" + SYNTHETIC_TAG, "0.0.0", "2.0.0-rc.1+fixture"):
            self.assertEqual(SMOKE.release_tag(tag), tag)
        for tag in ("main", "", "--all", "1.2", "01.2.3", "1.2.3-01", "1.2.3\n", '1.2.3"'):
            with self.subTest(tag=tag), self.assertRaises(argparse.ArgumentTypeError):
                SMOKE.release_tag(tag)
        for sha in ("HEAD", "a" * 39, "g" * 40):
            with self.assertRaises(argparse.ArgumentTypeError):
                SMOKE.commit_sha(sha)

    def test_lightweight_and_annotated_tag_target(self):
        ref = "refs/tags/" + SYNTHETIC_TAG
        SMOKE.check_remote_tag(SYNTHETIC_SHA + "\t" + ref + "\n", SYNTHETIC_TAG, SYNTHETIC_SHA)
        SMOKE.check_remote_tag("b" * 40 + "\t" + ref + "\n" + SYNTHETIC_SHA + "\t" + ref + "^{}\n",
                               SYNTHETIC_TAG, SYNTHETIC_SHA)
        for output in ("", "b" * 40 + "\t" + ref + "\n", SYNTHETIC_SHA + "\trefs/heads/main\n"):
            with self.assertRaises(ValueError):
                SMOKE.check_remote_tag(output, SYNTHETIC_TAG, SYNTHETIC_SHA)

    def test_resolved_pin_rejects_wrong_source_version_commit_or_extra_dependency(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Package.resolved"
            pin = {"identity": "martygraphics", "kind": "remoteSourceControl", "location": SMOKE.PUBLIC_URL,
                   "state": {"version": SYNTHETIC_TAG, "revision": SYNTHETIC_SHA}}
            def write(value):
                path.write_text(json.dumps(value), encoding="utf-8")
            for schema in (2, 3):
                write({"version": schema, "pins": [pin]})
                SMOKE.check_pin(path, SYNTHETIC_TAG, SYNTHETIC_SHA)
            for field, value in (("identity", "other"), ("kind", "local"), ("location", "file:///fixture")):
                write({"version": 3, "pins": [{**pin, field: value}]})
                with self.assertRaises(ValueError):
                    SMOKE.check_pin(path, SYNTHETIC_TAG, SYNTHETIC_SHA)
            for state in ({"version": "0.0.0-fixture", "revision": SYNTHETIC_SHA},
                          {"version": SYNTHETIC_TAG, "revision": "b" * 40}):
                write({"version": 3, "pins": [{**pin, "state": state}]})
                with self.assertRaises(ValueError):
                    SMOKE.check_pin(path, SYNTHETIC_TAG, SYNTHETIC_SHA)
            write({"version": 3, "pins": [pin, pin]})
            with self.assertRaises(ValueError):
                SMOKE.check_pin(path, SYNTHETIC_TAG, SYNTHETIC_SHA)

    def test_rejects_non_mac_before_network_or_output_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "new"
            with patch.object(SMOKE.platform, "system", return_value="Windows"), \
                    patch.object(SMOKE.subprocess, "run") as command, \
                    redirect_stderr(io.StringIO()), \
                    self.assertRaises(SystemExit):
                SMOKE.main(["--tag", SYNTHETIC_TAG, "--commit", SYNTHETIC_SHA, "--output", str(output)])
            command.assert_not_called()
            self.assertFalse(output.exists())

    def test_refuses_existing_or_checkout_output(self):
        with tempfile.TemporaryDirectory() as directory:
            for output in (Path(directory), SMOKE.REPO / "must-not-create"):
                with patch.object(SMOKE.subprocess, "run") as command, \
                        redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    SMOKE.main(["--tag", SYNTHETIC_TAG, "--commit", SYNTHETIC_SHA, "--output", str(output)])
                command.assert_not_called()

    def test_failed_fetch_keeps_failure_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "new"
            failed = subprocess.CompletedProcess([], 1, "", "synthetic fetch failure")
            with patch.object(SMOKE.platform, "system", return_value="Darwin"), \
                    patch.object(SMOKE.subprocess, "run", return_value=failed), redirect_stdout(io.StringIO()):
                code = SMOKE.main(["--tag", SYNTHETIC_TAG, "--commit", SYNTHETIC_SHA, "--output", str(output)])
            self.assertEqual(code, 1)
            receipt = json.loads((output / "receipt.json").read_text())
            self.assertEqual(receipt["status"], "FAIL")
            self.assertEqual(receipt["commands"][0]["exit"], 1)
            self.assertFalse((output / "Package.swift").exists())

    def test_absent_tag_does_not_reach_swift(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "new"
            empty = subprocess.CompletedProcess([], 0, "", "")
            with patch.object(SMOKE.platform, "system", return_value="Darwin"), \
                    patch.object(SMOKE.subprocess, "run", return_value=empty) as command, redirect_stdout(io.StringIO()):
                code = SMOKE.main(["--tag", SYNTHETIC_TAG, "--commit", SYNTHETIC_SHA, "--output", str(output)])
            self.assertEqual(code, 1)
            self.assertEqual(command.call_count, 1)
            self.assertEqual(json.loads((output / "receipt.json").read_text())["status"], "FAIL")
            self.assertFalse((output / "Package.swift").exists())

    def test_timeout_keeps_a_failed_command_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "new"
            timeout = subprocess.TimeoutExpired(["git"], 600, output=b"synthetic partial output")
            with patch.object(SMOKE.platform, "system", return_value="Darwin"), \
                    patch.object(SMOKE.subprocess, "run", side_effect=timeout), redirect_stdout(io.StringIO()):
                code = SMOKE.main(["--tag", SYNTHETIC_TAG, "--commit", SYNTHETIC_SHA, "--output", str(output)])
            receipt = json.loads((output / "receipt.json").read_text())
            self.assertEqual(code, 1)
            self.assertEqual(receipt["status"], "FAIL")
            self.assertEqual(receipt["commands"][0]["exit"], 124)

    def test_wrong_fetched_checkout_never_builds(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "new"
            def simulated(argv, **kwargs):
                stdout = "synthetic toolchain"
                if "ls-remote" in argv:
                    stdout = SYNTHETIC_SHA + "\trefs/tags/" + SYNTHETIC_TAG + "\n"
                elif "resolve" in argv:
                    pin = {"identity": "martygraphics", "kind": "remoteSourceControl", "location": SMOKE.PUBLIC_URL,
                           "state": {"version": SYNTHETIC_TAG, "revision": SYNTHETIC_SHA}}
                    (output / "Package.resolved").write_text(json.dumps({"version": 3, "pins": [pin]}))
                elif "rev-parse" in argv:
                    stdout = "b" * 40
                return subprocess.CompletedProcess(argv, 0, stdout, "")
            with patch.object(SMOKE.platform, "system", return_value="Darwin"), \
                    patch.object(SMOKE.subprocess, "run", side_effect=simulated) as command, redirect_stdout(io.StringIO()):
                code = SMOKE.main(["--tag", SYNTHETIC_TAG, "--commit", SYNTHETIC_SHA, "--output", str(output)])
            self.assertEqual(code, 1)
            self.assertFalse(any(Path(call.args[0][0]).name == "swift" and call.args[0][1] == "build"
                                 for call in command.call_args_list))
            self.assertEqual(json.loads((output / "receipt.json").read_text())["status"], "FAIL")

    def test_synthetic_flow_locks_resolution_and_excludes_publishing_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "new"
            def simulated(argv, **kwargs):
                self.assertNotIn("GITHUB_TOKEN", kwargs["env"])
                self.assertNotIn("GH_TOKEN", kwargs["env"])
                self.assertIn(argv[0], (str(self.tools.git), str(self.tools.swift)))
                self.assertTrue(Path(kwargs["env"]["HOME"]).is_relative_to(output))
                self.assertEqual(kwargs["env"]["GIT_CONFIG_VALUE_0"], "")
                self.assertEqual(kwargs["env"]["GIT_EXEC_PATH"], str(self.tools.git_exec))
                self.assertNotIn("GIT_TRACE", kwargs["env"])
                stdout = "synthetic toolchain/output"
                if "ls-remote" in argv:
                    stdout = SYNTHETIC_SHA + "\trefs/tags/v" + SYNTHETIC_TAG + "\n"
                elif "resolve" in argv:
                    pin = {"identity": "martygraphics", "kind": "remoteSourceControl", "location": SMOKE.PUBLIC_URL,
                           "state": {"version": SYNTHETIC_TAG, "revision": SYNTHETIC_SHA}}
                    (output / "Package.resolved").write_text(json.dumps({"version": 3, "pins": [pin]}))
                elif "rev-parse" in argv:
                    stdout = SYNTHETIC_SHA
                return subprocess.CompletedProcess(argv, 0, stdout, "")
            with patch.object(SMOKE.platform, "system", return_value="Darwin"), \
                    patch.dict(SMOKE.os.environ, {"GH_TOKEN": "synthetic", "GITHUB_TOKEN": "synthetic"}), \
                    patch.object(SMOKE.subprocess, "run", side_effect=simulated) as command, redirect_stdout(io.StringIO()):
                code = SMOKE.main(["--tag", "v" + SYNTHETIC_TAG, "--commit", SYNTHETIC_SHA, "--output", str(output)])
            self.assertEqual(code, 0)  # Simulated commands only; this is not remote/native acceptance.
            receipt = json.loads((output / "receipt.json").read_text())
            self.assertEqual(receipt["status"], "PASS")
            commands = [call.args[0] for call in command.call_args_list]
            build = next(argv for argv in commands if Path(argv[0]).name == "swift" and argv[1] == "build")
            run = next(argv for argv in commands if Path(argv[0]).name == "swift" and argv[1] == "run")
            self.assertIn("--force-resolved-versions", build)
            self.assertIn("--force-resolved-versions", run)
            self.assertIn("--skip-build", run)
            self.assertEqual(len([argv for argv in commands if "ls-remote" in argv]), 2)
            self.assertIn('exact: "' + SYNTHETIC_TAG + '"', (output / "Package.swift").read_text())
            self.assertEqual(set(receipt["consumerFiles"]), {"Package.swift", "Package.resolved", "Sources/MGRemoteSmoke/main.swift"})


if __name__ == "__main__":
    unittest.main()
