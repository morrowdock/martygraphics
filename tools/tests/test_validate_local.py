# SPDX-License-Identifier: Apache-2.0
"""Check when an earlier native receipt may vouch for a candidate, on real Git fixture repositories."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("local_validation_under_test", TOOLS / "validate_local.py")
validate_local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validate_local)

FIXTURE = {
    "Package.swift": "// root package\n",
    "Sources/MartyGraphics/Engine.swift": "let engine = 1\n",
    "Tests/EngineTests/EngineTests.swift": 'let reasons = "docs/REASONS.md"\nlet assets = "docs/assets"\n'
                                          'let board = "Examples/Explainers/board.json"\n',
    "Examples/Solid3D/Package.swift": "// Solid3D\n",
    "Examples/Solid3D/Sources/MartySolidCLI/main.swift": "print(1)\n",
    "Examples/Solid3D/README.md": "# Solid3D\n",
    "Examples/Turbofan/Package.swift": "// Turbofan\n",
    "Examples/Turbofan/Sources/TurbofanKit/Kit.swift": "let kit = 1\n",
    "Examples/Explainers/board.json": "{}\n",
    "Examples/Explainers/README.md": "# Explainers\n",
    "tools/SceneValidator/Package.swift": "// validator\n",
    "tools/SceneValidator/Sources/main.swift": "print(2)\n",
    "tools/render-blender/render.py": "print(3)\n",
    "tools/render-blender/README.md": "# Render\n",
    "docs/fixtures/scene.json": "{}\n",
    "docs/assets/gearbox.json": "{}\n",
    "docs/REASONS.md": "# Reasons\n",
    "docs/GUIDE.md": "# Guide\n",
    "README.md": "# Fixture\n",
}
PACKAGES = [".", "Examples/Solid3D", "Examples/Turbofan", "tools/SceneValidator", "tools/render-blender"]


class FixtureRepo(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.repo = Path(temp.name)
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME="Fixture", GIT_COMMITTER_NAME="Fixture",
                        GIT_AUTHOR_EMAIL="fixture@example.invalid", GIT_COMMITTER_EMAIL="fixture@example.invalid")
        self.git("init", "-b", "main")
        self.git("config", "commit.gpgsign", "false")
        self.source = self.commit(FIXTURE)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, env=self.env, text=True,
                                       stderr=subprocess.PIPE).strip()

    def commit(self, files=(), remove=()):
        for name, text in dict(files).items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(text.encode())
        for name in remove:
            self.git("rm", "-r", "-q", name)
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", "fixture")
        return self.git("rev-parse", "HEAD")

    def reuse(self, head, receipt=None):
        receipt = {p: 0 for p in PACKAGES} if receipt is None else receipt
        return validate_local.native_reuse(self.source, head, receipt, root=self.repo)


class NativeReuseTests(FixtureRepo):
    def test_unchanged_native_tree_passes(self):
        head = self.commit({"README.md": "# Changed\n", "Examples/Solid3D/README.md": "# Changed\n",
                            "Examples/Explainers/README.md": "# Changed\n", "tools/render-blender/README.md": "# x\n",
                            "docs/GUIDE.md": "# Changed\n"})
        result = self.reuse(head)
        self.assertEqual(result["packages"], PACKAGES)
        self.assertEqual((result["changed"], result["uncovered"], result["status"]), ([], [], "PASS"))

    def test_changed_solid3d_file_fails(self):
        head = self.commit({"Examples/Solid3D/Sources/MartySolidCLI/main.swift": "print(4)\n"})
        result = self.reuse(head)
        self.assertEqual(result["changed"], ["Examples/Solid3D/Sources/MartySolidCLI/main.swift"])
        self.assertEqual(result["status"], "FAIL")

    def test_new_package_fails(self):
        head = self.commit({"Examples/NewKit/Package.swift": "// new\n", "Examples/NewKit/Sources/Kit/Kit.swift": "1\n"})
        result = self.reuse(head)
        self.assertIn("Examples/NewKit", result["packages"])
        self.assertEqual(result["changed"], ["Examples/NewKit/Package.swift", "Examples/NewKit/Sources/Kit/Kit.swift"])
        self.assertEqual(result["uncovered"], ["Examples/NewKit"])
        self.assertEqual(result["status"], "FAIL")

    def test_removed_package_fails(self):
        result = self.reuse(self.commit(remove=["Examples/Turbofan"]))
        self.assertNotIn("Examples/Turbofan", result["packages"])
        self.assertEqual(result["changed"], ["Examples/Turbofan/Package.swift",
                                             "Examples/Turbofan/Sources/TurbofanKit/Kit.swift"])
        self.assertEqual(result["status"], "FAIL")

    def test_every_native_byte_counts(self):
        for name in ["Package.swift", "Sources/MartyGraphics/Engine.swift", "Tests/EngineTests/EngineTests.swift",
                     "Examples/Turbofan/Sources/TurbofanKit/Kit.swift", "Examples/Explainers/board.json",
                     "Examples/Explainers/new.json", "tools/SceneValidator/Sources/main.swift",
                     "tools/render-blender/render.py", "docs/fixtures/scene.json", "docs/assets/gearbox.json",
                     "docs/REASONS.md", "Examples/Solid3D/Sources/MartySolidCLI/Notes.md"]:
            with self.subTest(name=name):
                head = self.commit({name: "changed " + name + "\n"})
                self.assertEqual(self.reuse(head)["changed"], [name])
                self.git("reset", "-q", "--hard", self.source)

    def test_receipt_must_name_every_present_package(self):
        head = self.commit({"README.md": "# Changed\n"})
        missing = {p: 0 for p in PACKAGES if p != "tools/render-blender"}
        self.assertEqual(self.reuse(head, missing)["uncovered"], ["tools/render-blender"])
        failed = dict({p: 0 for p in PACKAGES}, **{"Examples/Solid3D": 1})
        result = self.reuse(head, failed)
        self.assertEqual((result["uncovered"], result["status"]), (["Examples/Solid3D"], "FAIL"))

    def test_native_receipt_format(self):
        path = self.repo.parent / (self.repo.name + "-native.json")
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        good = {"source": self.source.upper(), "packages": [{"path": ".", "exit": 0}, {"path": "Examples/Solid3D", "exit": 1}]}
        path.write_text(json.dumps(good))
        self.assertEqual(validate_local.read_native_receipt(path, self.source), {".": 0, "Examples/Solid3D": 1})
        for bad in [dict(good, source="0" * 40), dict(good, packages=["."]), {"source": self.source},
                    dict(good, packages=[{"path": ".", "exit": 0}, {"path": ".", "exit": 0}]),
                    dict(good, packages=[{"path": ".", "exit": "0"}])]:
            with self.subTest(bad=bad):
                path.write_text(json.dumps(bad))
                with self.assertRaises(ValueError):
                    validate_local.read_native_receipt(path, self.source)


class LocalValidationRunTests(FixtureRepo):
    """The runner records the reuse decision in its receipt and fails the run when reuse fails."""

    def run_main(self, head, native=True, packages=PACKAGES):
        evidence = tempfile.TemporaryDirectory()
        self.addCleanup(evidence.cleanup)
        receipt = Path(evidence.name) / "receipt.json"
        native_receipt = Path(evidence.name) / "native.json"
        native_receipt.write_text(json.dumps({"source": self.source,
                                              "packages": [{"path": p, "exit": 0} for p in packages]}))
        arguments = ["validate_local.py", "--base", self.source, "--head", head, "--gitleaks", "unused-test-scanner",
                     "--receipt", str(receipt)]
        if native:
            arguments += ["--native-source", self.source, "--native-receipt", str(native_receipt)]
        real_run, hygiene = subprocess.run, []

        def fake_run(command, **kwargs):
            if kwargs.get("stdout") == subprocess.PIPE:  # git() through check_output
                return real_run(command, **kwargs)
            hygiene.append(command)
            return subprocess.CompletedProcess(command, 0)

        with mock.patch.object(validate_local, "ROOT", self.repo), mock.patch.object(sys, "argv", arguments), \
                mock.patch.object(validate_local.subprocess, "run", side_effect=fake_run), \
                mock.patch.object(validate_local.platform, "platform", return_value="synthetic-test-platform"), \
                mock.patch.object(validate_local.socket, "gethostname", return_value="synthetic-test-host"), \
                mock.patch("builtins.print"):
            status = validate_local.main()
        self.assertEqual(len(hygiene), 5)
        self.assertFalse(any(c[:3] == ["git", "diff", "--exit-code"] for c in hygiene))
        return status, json.loads(receipt.read_text())

    def test_unchanged_tree_reuses_receipt(self):
        status, receipt = self.run_main(self.commit({"README.md": "# Changed\n"}))
        self.assertEqual((status, receipt["status"], receipt["nativeReuse"]["status"]), (0, "PASS", "PASS"))
        self.assertEqual(receipt["nativeReuse"]["packages"], PACKAGES)

    def test_changed_solid3d_file_fails_the_run(self):
        status, receipt = self.run_main(self.commit({"Examples/Solid3D/Sources/MartySolidCLI/main.swift": "x\n"}))
        self.assertEqual((status, receipt["status"]), (1, "FAIL"))
        self.assertEqual(receipt["nativeReuse"]["changed"], ["Examples/Solid3D/Sources/MartySolidCLI/main.swift"])

    def test_new_package_fails_the_run(self):
        status, receipt = self.run_main(self.commit({"Examples/NewKit/Package.swift": "// new\n"}))
        self.assertEqual((status, receipt["nativeReuse"]["uncovered"]), (1, ["Examples/NewKit"]))

    def test_receipt_missing_a_package_fails_the_run(self):
        status, receipt = self.run_main(self.commit({"README.md": "# Changed\n"}), packages=PACKAGES[:-1])
        self.assertEqual((status, receipt["nativeReuse"]["uncovered"]), (1, ["tools/render-blender"]))

    def test_without_native_source_no_reuse_is_claimed(self):
        status, receipt = self.run_main(self.commit({"Sources/MartyGraphics/Engine.swift": "x\n"}), native=False)
        self.assertEqual((status, receipt["nativeReuse"]), (0, None))

    def test_native_source_needs_its_receipt(self):
        arguments = ["validate_local.py", "--base", self.source, "--head", self.source, "--gitleaks", "x",
                     "--receipt", "unused.json", "--native-source", self.source]
        with mock.patch.object(sys, "argv", arguments), mock.patch("sys.stderr"), self.assertRaises(SystemExit) as exit:
            validate_local.main()
        self.assertEqual(exit.exception.code, 2)


class RepositoryCoverageTests(unittest.TestCase):
    def test_packages_come_from_this_repository(self):
        paths = validate_local.tree("HEAD")
        packages = validate_local.native_packages(paths)
        self.assertEqual(packages, sorted({p.rpartition("/")[0] or "." for p in paths if p.endswith("/Package.swift")
                                           or p == "Package.swift"} | set(validate_local.NATIVE_TOOLS)))
        for package in [".", "Examples/Solid3D", "Examples/Turbofan", "Examples/LessonDemo", "Examples/KeySwitch3D",
                        "Examples/PathTrace", "Examples/Showcase", "tools/SceneValidator", "tools/render-blender"]:
            self.assertIn(package, packages)
        swift = [(validate_local.ROOT / p).read_text(encoding="utf-8") for p in paths if p.endswith(".swift")]
        inputs = validate_local.native_inputs(paths, swift, packages)
        for name in ["Examples/Explainers", "docs/fixtures"]:
            self.assertIn(name, inputs)

    def test_docs_match_the_check(self):
        docs = {name: (validate_local.ROOT / name).read_text(encoding="utf-8")
                for name in ["docs/LOCAL-VALIDATION.md", "docs/VERIFY-ON-MAC.md"]}
        for name, text in docs.items():
            with self.subTest(name=name):
                self.assertFalse("UnitCircle" in text, "UnitCircle is named")
                for tool in validate_local.NATIVE_TOOLS:
                    self.assertIn(tool, text)
        self.assertIn("--native-receipt", docs["docs/LOCAL-VALIDATION.md"])


if __name__ == "__main__":
    unittest.main()
