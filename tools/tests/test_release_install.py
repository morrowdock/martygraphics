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
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("release_install", Path(__file__).resolve().parents[1] / "verify_release_install.py")
SMOKE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SMOKE)
SYNTHETIC_TAG = "1.2.3-fixture"
SYNTHETIC_SHA = "a" * 40


class ReleaseInstallTests(unittest.TestCase):
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
            self.assertFalse(any(call.args[0][:2] == ["swift", "build"] for call in command.call_args_list))
            self.assertEqual(json.loads((output / "receipt.json").read_text())["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
