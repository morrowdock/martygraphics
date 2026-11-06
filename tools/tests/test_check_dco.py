# SPDX-License-Identifier: Apache-2.0
"""Exercise the checker against actual contributor and synthetic merge histories."""

import os
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


CHECKER = Path(__file__).resolve().parents[1] / "check_dco.py"
SIGNOFF = "\n\nSigned-off-by: DCO Test <dco@example.invalid>"


class DCOTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME="DCO Test", GIT_COMMITTER_NAME="DCO Test",
                        GIT_AUTHOR_EMAIL="dco@example.invalid", GIT_COMMITTER_EMAIL="dco@example.invalid")
        self.git("init", "-b", "main")
        self.git("config", "commit.gpgsign", "false")
        self.base = self.commit("base")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, env=self.env,
                                       text=True, stderr=subprocess.PIPE).strip()

    def commit(self, message, signed=True):
        self.git("commit", "--allow-empty", "-m", message + (SIGNOFF if signed else ""))
        return self.git("rev-parse", "HEAD")

    def check(self, base, head):
        return subprocess.run([sys.executable, str(CHECKER), base, head], cwd=self.repo,
                              env=self.env, text=True, capture_output=True)

    def test_signed_contributor(self):
        self.assertEqual(self.check(self.base, self.commit("contribution")).returncode, 0)

    def test_unsigned_contributor(self):
        head = self.commit("contribution", signed=False)
        result = self.check(self.base, head)
        self.assertEqual(result.returncode, 1)
        self.assertIn(head, result.stderr)

    def merge_history(self, signed):
        self.git("checkout", "-b", "contributor")
        contributor = self.commit("contribution")
        self.git("checkout", "main")
        base = self.commit("base advanced")
        self.git("merge", "--no-ff", "contributor", "-m", "merge" + (SIGNOFF if signed else ""))
        return base, contributor, self.git("rev-parse", "HEAD")

    def test_synthetic_checkout_merge_excluded_by_actual_pr_head(self):
        base, contributor, synthetic = self.merge_history(signed=False)
        self.assertEqual(self.git("rev-parse", "HEAD"), synthetic)
        self.assertEqual(self.check(base, contributor).returncode, 0)
        self.assertEqual(self.check(base, synthetic).returncode, 1)

    def test_unsigned_contributor_merge_rejected(self):
        base, _, merge = self.merge_history(signed=False)
        result = self.check(base, merge)
        self.assertEqual(result.returncode, 1)
        self.assertIn(merge, result.stderr)

    def test_signed_contributor_merge_accepted(self):
        base, _, merge = self.merge_history(signed=True)
        self.assertEqual(self.check(base, merge).returncode, 0)

    def test_unsafe_or_unresolved_range_rejected(self):
        for value in ("HEAD", "--all", "a" * 39, "g" * 40, "0" * 40):
            with self.subTest(value=value):
                self.assertEqual(self.check(self.base, value).returncode, 2)
                self.assertEqual(self.check(value, self.base).returncode, 2)


class LocalValidationCoverageTests(unittest.TestCase):
    def check_native_change(self, changed_path):
        checker_path = CHECKER.with_name("validate_local.py")
        spec = importlib.util.spec_from_file_location("local_validation_under_test", checker_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        head = "a" * 40
        commands = []

        def fake_git(*arguments):
            return head.encode() if arguments == ("rev-parse", "HEAD") else b""

        def fake_run(command, **kwargs):
            commands.append(command)
            native_diff = command[:3] == ["git", "diff", "--exit-code"]
            covered = native_diff and any(changed_path == path or changed_path.startswith(path + "/")
                                          for path in command[6:])
            return subprocess.CompletedProcess(command, 1 if covered else 0)

        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "receipt.json"
            arguments = [str(checker_path), "--base", "b" * 40, "--head", head,
                         "--native-source", "c" * 40, "--gitleaks", "unused-test-scanner",
                         "--receipt", str(receipt)]
            with mock.patch.object(sys, "argv", arguments), mock.patch.object(module, "git", side_effect=fake_git), \
                    mock.patch.object(module.subprocess, "run", side_effect=fake_run), \
                    mock.patch.object(module.platform, "platform", return_value="synthetic-test-platform"), \
                    mock.patch.object(module.socket, "gethostname", return_value="synthetic-test-host"), \
                    mock.patch("builtins.print"):
                status = module.main()
            report = json.loads(receipt.read_text())
        native = [command for command in commands if command[:3] == ["git", "diff", "--exit-code"]]
        self.assertEqual(len(native), 1)
        self.assertEqual(native[0][3:6], ["c" * 40, head, "--"])
        return status, report

    def test_each_native_package_is_in_reuse_guard(self):
        for path in ["Sources/MartyGraphics/MGParser.swift", "Tests/EngineTests.swift", "Package.swift",
                     "Examples/Showcase/Package.swift", "Examples/Showcase/Sources/scene.json", "docs/fixtures/scene.json",
                     "Examples/UnitCircle/Package.swift", "Examples/UnitCircle/Sources/scene.json",
                     "tools/SceneValidator/Package.swift", "tools/SceneValidator/Sources/main.swift",
                     "tools/SceneValidator/Tests/ValidatorTests.swift"]:
            with self.subTest(path=path):
                status, receipt = self.check_native_change(path)
                self.assertEqual(status, 1)
                self.assertEqual(receipt["status"], "FAIL")

    def test_documentation_does_not_require_new_native_run(self):
        for path in ["README.md", "Examples/UnitCircle/README.md", "tools/SceneValidator/README.md"]:
            with self.subTest(path=path):
                status, receipt = self.check_native_change(path)
                self.assertEqual(status, 0)
                self.assertEqual(receipt["status"], "PASS")


if __name__ == "__main__":
    unittest.main()
