# SPDX-License-Identifier: Apache-2.0
"""Check when an earlier native receipt may vouch for a candidate, on real Git fixture repositories."""

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("local_validation_under_test", TOOLS / "validate_local.py")
validate_local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validate_local)
writer_spec = importlib.util.spec_from_file_location("native_receipt_writer_under_test", TOOLS / "write_native_receipt.py")
writer = importlib.util.module_from_spec(writer_spec)
writer_spec.loader.exec_module(writer)

FIXTURE = {
    "Package.swift": 'let package = Package(name: "Fixture", targets: [\n'
                     '    .target(name: "MartyGraphics", resources: [.process("Resources")]),\n'
                     '    .target(name: "Assets", path: "Assets"),\n'
                     '    .testTarget(name: "EngineTests", dependencies: ["MartyGraphics"])])\n',
    "Sources/MartyGraphics/Engine.swift": "let engine = 1\n",
    "Sources/MartyGraphics/Resources/shader.metal": "// shader\n",
    "Assets/palette.json": "{}\n",
    "Assets/NOTES.md": "# Palette notes\n",
    "Tests/EngineTests/EngineTests.swift": 'let reasons = "docs/REASONS.md"\nlet assets = "docs/assets"\n'
                                          'let board = "Examples/Explainers/board.json"\n'
                                          'let cases = "Examples/Solid3D/Fixtures"\nlet changelog = "CHANGELOG.md"\n',
    "Examples/Solid3D/Package.swift": "// Solid3D\n",
    "Examples/Solid3D/Sources/MartySolidCLI/main.swift": "print(1)\n",
    "Examples/Solid3D/README.md": "# Solid3D\n",
    "Examples/Solid3D/Fixtures/cases.json": "{}\n",
    "Examples/Solid3D/Fixtures/README.md": "# Cases\n",
    "Examples/Solid3D/.build/checkouts/Dep/Package.swift": "// build output\n",
    "Examples/Turbofan/Package.swift": 'let package = Package(name: "Turbofan", dependencies: [\n'
                                       '    .package(path: "../.."), .package(path: "../../vendor/LocalKit")])\n',
    "Examples/Turbofan/Sources/TurbofanKit/Kit.swift": "let kit = 1\n",
    "Examples/Turbofan/Tests/TurbofanKitTests/KitTests.swift": "let test = 1\n",
    "Examples/Explainers/board.json": "{}\n",
    "Examples/Explainers/README.md": "# Explainers\n",
    "vendor/LocalKit/Package.swift": "// vendored\n",
    "vendor/LocalKit/Sources/LocalKit/LocalKit.swift": "let local = 1\n",
    "vendor/LocalKit/README.md": "# LocalKit\n",
    "third_party/Unused/Package.swift": "// not a dependency\n",
    "third_party/Unused/README.md": "# Unused\n",
    "tools/SceneValidator/Package.swift": "// validator\n",
    "tools/SceneValidator/Sources/main.swift": "print(2)\n",
    "tools/render-blender/render.py": "print(3)\n",
    "tools/render-blender/README.md": "# Render\n",
    "shared/data.json": "{}\n",
    "docs/fixtures/scene.json": "{}\n",
    "docs/assets/gearbox.json": "{}\n",
    "docs/assets/NOTES.md": "# Asset notes\n",
    "docs/REASONS.md": "# Reasons\n",
    "docs/GUIDE.md": "# Guide\n",
    "README.md": "# Fixture\n",
    "CHANGELOG.md": "# Changelog\n",
}
PACKAGES = [".", "Examples/Solid3D", "Examples/Turbofan", "tools/SceneValidator", "tools/render-blender"]
INPUTS = ["Assets", "CHANGELOG.md", "Examples/Explainers", "Examples/Solid3D/Fixtures", "docs/REASONS.md",
          "docs/assets", "docs/fixtures", "vendor/LocalKit"]


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

    def git(self, *args, stdin=None):
        return subprocess.run(["git", *args], cwd=self.repo, env=self.env, text=True, input=stdin,
                              capture_output=True, check=True).stdout.strip()

    def commit(self, files=(), remove=()):
        """Commit these file contents and removals. Only the named paths are staged."""
        files = dict(files)
        for name, text in files.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(text.encode())
        for name in remove:
            self.git("rm", "-r", "-q", name)
        if files:
            self.git("add", "--", *files)
        return self.commit_index()

    def commit_index(self):
        self.git("commit", "-q", "--allow-empty", "-m", "fixture")
        return self.git("rev-parse", "HEAD")

    def stage_link(self, path, target):
        """Stage a committed symlink without creating it in the working tree."""
        oid = self.git("hash-object", "-w", "--stdin", stdin=target)
        self.git("update-index", "--add", "--cacheinfo", "120000,%s,%s" % (oid, path))

    def rename(self, old, new):
        """Rename a file or folder in the index only, so a case-only rename works on any file system."""
        for line in self.git("ls-files", "-s", "--", old).splitlines():
            meta, path = line.split("\t")
            mode, oid, _ = meta.split()
            self.git("update-index", "--force-remove", "--", path)
            self.git("update-index", "--add", "--cacheinfo", "%s,%s,%s" % (mode, oid, new + path[len(old):]))
        return self.commit_index()

    def reuse(self, head, receipt=None, source=None):
        receipt = {p: 0 for p in PACKAGES} if receipt is None else receipt
        return validate_local.native_reuse(source or self.source, head, receipt, root=self.repo)


class NativeReuseTests(FixtureRepo):
    def test_unchanged_native_tree_passes(self):
        head = self.commit({"README.md": "# Changed\n", "Examples/Solid3D/README.md": "# Changed\n",
                            "tools/render-blender/README.md": "# x\n", "docs/GUIDE.md": "# Changed\n",
                            "third_party/Unused/README.md": "# Changed\n", "third_party/Unused/Package.swift": "//\n"})
        result = self.reuse(head)
        self.assertEqual((result["packages"], result["inputs"]), (PACKAGES, INPUTS))
        self.assertEqual((result["changed"], result["links"], result["status"]), ([], [], "PASS"))

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
        self.assertEqual(result["missing"], ["Examples/NewKit"])
        self.assertEqual(result["status"], "FAIL")

    def test_removed_package_fails(self):
        result = self.reuse(self.commit(remove=["Examples/Turbofan"]))
        self.assertNotIn("Examples/Turbofan", result["packages"])
        self.assertEqual(result["changed"], ["Examples/Turbofan/Package.swift",
                                             "Examples/Turbofan/Sources/TurbofanKit/Kit.swift",
                                             "Examples/Turbofan/Tests/TurbofanKitTests/KitTests.swift"])
        self.assertEqual(result["unexpected"], ["Examples/Turbofan"])
        self.assertEqual(result["status"], "FAIL")

    def test_every_native_byte_counts(self):
        for name in ["Package.swift", "Sources/MartyGraphics/Engine.swift", "Tests/EngineTests/EngineTests.swift",
                     "Sources/MartyGraphics/Resources/shader.metal", "Sources/MartyGraphics/Resources/NOTES.md",
                     "Examples/Turbofan/Sources/TurbofanKit/Kit.swift", "Examples/Explainers/board.json",
                     "Examples/Explainers/new.json", "tools/SceneValidator/Sources/main.swift",
                     "tools/render-blender/render.py", "docs/fixtures/scene.json", "docs/assets/gearbox.json",
                     "docs/REASONS.md", "Examples/Solid3D/Sources/MartySolidCLI/Notes.md", "CHANGELOG.md",
                     "Examples/Solid3D/.build/checkouts/Dep/Package.swift"]:
            with self.subTest(name=name):
                head = self.commit({name: "changed " + name + "\n"})
                self.assertEqual(self.reuse(head)["changed"], [name])
                self.git("reset", "-q", "--hard", self.source)

    def test_markdown_and_inputs_outside_sources_and_tests(self):
        """Referenced folders cover all their files, Markdown too; so do root-package target folders declared
        outside Sources/ and Tests/ and local dependencies, even vendored ones and ones inside a package."""
        for name in ["docs/assets/NOTES.md", "Examples/Explainers/README.md", "Examples/Solid3D/Fixtures/README.md",
                     "Examples/Solid3D/Fixtures/cases.json", "Assets/NOTES.md", "Assets/palette.json",
                     "vendor/LocalKit/README.md", "vendor/LocalKit/Sources/LocalKit/LocalKit.swift"]:
            for change in ("changed", "added", "deleted"):
                with self.subTest(name=name, change=change):
                    if change == "deleted":
                        head, expected = self.commit(remove=[name]), name
                    else:
                        expected = name if change == "changed" else name.rpartition("/")[0] + "/Added.md"
                        head = self.commit({expected: "# " + change + "\n"})
                    result = self.reuse(head)
                    self.assertEqual((result["changed"], result["status"]), ([expected], "FAIL"))
                    self.git("reset", "-q", "--hard", self.source)

    def test_discovery_reads_the_pinned_trees_not_the_working_tree(self):
        (self.repo / "Sources/MartyGraphics/Engine.swift").unlink()
        (self.repo / "Tests/EngineTests/EngineTests.swift").write_text('let guide = "docs/GUIDE.md"\n')
        head = self.commit({"docs/GUIDE.md": "# Changed\n"})
        result = self.reuse(head)
        self.assertNotIn("docs/GUIDE.md", result["inputs"])
        self.assertEqual((result["changed"], result["status"]), ([], "PASS"))

    def test_literals_of_both_trees_count(self):
        head = self.commit({"Tests/EngineTests/EngineTests.swift": "let none = 0\n", "docs/REASONS.md": "# New\n"})
        self.assertEqual(self.reuse(head)["changed"], ["Tests/EngineTests/EngineTests.swift", "docs/REASONS.md"])

    def test_renames(self):
        cases = [("Sources/MartyGraphics/Engine.swift", "Sources/MartyGraphics/Core.swift",
                  ["Sources/MartyGraphics/Core.swift", "Sources/MartyGraphics/Engine.swift"]),
                 ("Sources/MartyGraphics/Engine.swift", "Sources/MartyGraphics/engine.swift",
                  ["Sources/MartyGraphics/Engine.swift", "Sources/MartyGraphics/engine.swift"]),
                 ("docs/GUIDE.md", "docs/assets/GUIDE.md", ["docs/assets/GUIDE.md"]),
                 ("docs/assets/gearbox.json", "docs/gearbox.json", ["docs/assets/gearbox.json"]),
                 ("docs/assets", "docs/Assets", ["docs/assets/NOTES.md", "docs/assets/gearbox.json"]),
                 ("vendor/LocalKit/README.md", "vendor/LocalKit/readme.md",
                  ["vendor/LocalKit/README.md", "vendor/LocalKit/readme.md"])]
        for old, new, changed in cases:
            with self.subTest(old=old, new=new):
                result = self.reuse(self.rename(old, new))
                self.assertEqual((result["changed"], result["status"]), (changed, "FAIL"))
                self.git("reset", "-q", "--hard", self.source)

    def test_case_only_package_rename(self):
        result = self.reuse(self.rename("Examples/Turbofan", "Examples/turbofan"))
        self.assertEqual((result["missing"], result["unexpected"]), (["Examples/turbofan"], ["Examples/Turbofan"]))
        self.assertEqual(len(result["changed"]), 6)

    def test_receipt_must_name_exactly_the_present_packages(self):
        head = self.commit({"README.md": "# Changed\n"})
        missing = {p: 0 for p in PACKAGES if p != "tools/render-blender"}
        self.assertEqual(self.reuse(head, missing)["missing"], ["tools/render-blender"])
        failed = dict({p: 0 for p in PACKAGES}, **{"Examples/Solid3D": 1})
        result = self.reuse(head, failed)
        self.assertEqual((result["failed"], result["status"]), (["Examples/Solid3D"], "FAIL"))
        for extra, code in [("../outside", 1), ("../outside", 0), ("/abs/Examples/Solid3D", 0),
                            ("./Examples/Solid3D", 0), ("vendor/LocalKit", 0)]:
            with self.subTest(extra=extra, code=code):
                result = self.reuse(head, dict({p: 0 for p in PACKAGES}, **{extra: code}))
                self.assertEqual((result["unexpected"], result["missing"]), ([extra], []))
                self.assertEqual((result["failed"], result["status"]), ([extra] if code else [], "FAIL"))
        renamed = dict({p: 0 for p in PACKAGES if p != "Examples/Solid3D"}, **{"/abs/Examples/Solid3D": 0})
        result = self.reuse(head, renamed)
        self.assertEqual((result["missing"], result["unexpected"]), (["Examples/Solid3D"], ["/abs/Examples/Solid3D"]))

    def test_native_receipt_format(self):
        path = self.repo.parent / (self.repo.name + "-native.json")
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        good = {"source": self.source.upper(), "packages": [{"path": ".", "exit": 0}, {"path": "Examples/Solid3D", "exit": 1}]}
        path.write_text(json.dumps(good))
        self.assertEqual(validate_local.read_native_receipt(path, self.source), {".": 0, "Examples/Solid3D": 1})
        for bad in [dict(good, source="0" * 40), dict(good, packages=["."]), {"source": self.source},
                    dict(good, packages=[{"path": ".", "exit": 0}, {"path": ".", "exit": 0}]),
                    dict(good, packages=[{"path": ".", "exit": "0"}]),
                    dict(good, packages=[{"path": ".", "exit": True}])]:
            with self.subTest(bad=bad):
                path.write_text(json.dumps(bad))
                with self.assertRaises(ValueError):
                    validate_local.read_native_receipt(path, self.source)


class ManifestAndSymlinkTests(FixtureRepo):
    def test_dependency_outside_the_repository_refuses_reuse(self):
        for path in ["../../../outside/Kit", "/opt/fixture-kit"]:
            with self.subTest(path=path):
                manifest = 'let package = Package(name: "Turbofan", dependencies: [.package(path: "%s")])\n' % path
                source = self.commit({"Examples/Turbofan/Package.swift": manifest})
                result = self.reuse(self.commit({"README.md": "# x\n"}), source=source)
                self.assertEqual(result["links"], ["Examples/Turbofan: %s (dependency outside the repository)" % path])
                self.assertEqual((result["changed"], result["status"]), ([], "FAIL"))
                self.git("reset", "-q", "--hard", self.source)

    def linked_source(self, links):
        for path, target in links.items():
            self.stage_link(path, target)
        return self.commit_index()

    def test_covered_symlink_covers_its_tracked_target(self):
        source = self.linked_source({"Tests/EngineTests/Shared": "../../shared",
                                     "Tests/EngineTests/Data.json": "../../links/data.json",
                                     "links/data.json": "../docs/GUIDE.md"})
        result = self.reuse(self.commit({"README.md": "# x\n"}), source=source)
        self.assertEqual((result["changed"], result["links"], result["status"]), ([], [], "PASS"))
        self.assertTrue({"shared", "links/data.json", "docs/GUIDE.md"} <= set(result["inputs"]))
        for name in ["shared/data.json", "shared/new.json", "docs/GUIDE.md", "links/data.json"]:
            with self.subTest(name=name):
                if name == "links/data.json":
                    self.stage_link(name, "../README.md")
                    head = self.commit_index()
                else:
                    head = self.commit({name: "changed\n"})
                result = self.reuse(head, source=source)
                self.assertEqual((result["changed"], result["status"]), ([name], "FAIL"))
                self.git("reset", "-q", source)  # index only: the links are never created on disk

    def test_changed_link_target_fails(self):
        source = self.linked_source({"Tests/EngineTests/Shared": "../../shared"})
        self.stage_link("Tests/EngineTests/Shared", "../../docs")
        result = self.reuse(self.commit_index(), source=source)
        self.assertEqual(result["changed"], ["Tests/EngineTests/Shared"])
        self.assertIn("docs", result["inputs"])

    def test_external_or_unresolved_covered_link_refuses_reuse(self):
        for target, reason in [("/opt/fixture-data", "external"), ("../../../outside", "external"),
                               ("../../missing/data.json", "unresolved"), ("../../README.md/x", "unresolved")]:
            with self.subTest(target=target):
                source = self.linked_source({"Tests/EngineTests/Data": target})
                result = self.reuse(self.commit({"README.md": "# x\n"}), source=source)
                self.assertEqual(result["links"], ["Tests/EngineTests/Data -> %s (%s at head)" % (target, reason),
                                                   "Tests/EngineTests/Data -> %s (%s at source)" % (target, reason)])
                self.assertEqual(result["status"], "FAIL")
                self.git("reset", "-q", "--hard", self.source)

    def test_link_loop_is_unresolved(self):
        source = self.linked_source({"Tests/EngineTests/A": "B", "Tests/EngineTests/B": "A"})
        result = self.reuse(source, source=source)
        self.assertEqual(len(result["links"]), 4)
        self.assertEqual(result["status"], "FAIL")

    def test_version_specific_manifest_names_inputs(self):
        manifest = ('let package = Package(name: "Fixture", targets: [\n'
                    '    .target(name: "MartyGraphics", resources: [.copy("../../Bundled/table.json")])])\n')
        plain = self.commit({"Bundled/table.json": "{}\n"})
        result = self.reuse(self.commit({"Bundled/table.json": "[]\n"}), source=plain)
        self.assertEqual((result["changed"], result["status"]), ([], "PASS"))
        source = self.commit({"Package@swift-6.0.swift": manifest})
        result = self.reuse(self.commit({"Bundled/table.json": "[1]\n"}), source=source)
        self.assertIn("Bundled/table.json", result["inputs"])
        self.assertEqual((result["changed"], result["status"]), (["Bundled/table.json"], "FAIL"))

    def test_symlinked_manifest_is_read_in_the_links_package(self):
        manifest = ('let package = Package(name: "Demo", targets: [\n'
                    '    .target(name: "Demo", path: "../../Shared")])\n')
        self.commit({"Examples/Demo/Package.swift": "// demo\n", "Examples/Demo/Sources/Demo/Demo.swift": "1\n",
                     "templates/Demo.manifest.swift": manifest, "Shared/table.json": "{}\n"})
        self.stage_link("Examples/Demo/Package@swift-6.0.swift", "../../templates/Demo.manifest.swift")
        source = self.commit_index()
        receipt = dict({p: 0 for p in PACKAGES}, **{"Examples/Demo": 0})
        result = self.reuse(self.commit({"README.md": "# x\n"}), receipt, source=source)
        self.assertTrue({"Shared", "templates/Demo.manifest.swift"} <= set(result["inputs"]))
        self.assertEqual((result["links"], result["status"]), ([], "PASS"))
        for name in ["Shared/table.json", "Shared/new.json", "templates/Demo.manifest.swift"]:
            with self.subTest(name=name):
                result = self.reuse(self.commit({name: "changed\n"}), receipt, source=source)
                self.assertEqual((result["changed"], result["status"]), ([name], "FAIL"))
                self.git("reset", "-q", source)  # index only: the link is never created on disk

    def test_swift_symlink_is_scanned_as_its_target(self):
        self.commit({"shared/paths.txt": 'let guide = "docs/GUIDE.md"\n'})
        self.stage_link("notes/Paths.swift", "../shared/paths.txt")
        source = self.commit_index()
        result = self.reuse(self.commit({"docs/GUIDE.md": "# Changed\n"}), source=source)
        self.assertIn("docs/GUIDE.md", result["inputs"])
        self.assertEqual((result["changed"], result["status"]), (["docs/GUIDE.md"], "FAIL"))

    def test_submodule_refuses_reuse(self):
        for path in ["Examples/Solid3D/Deps/Lib", "docs/assets/sub", "external/Lib"]:
            with self.subTest(path=path):
                self.git("update-index", "--add", "--cacheinfo", "160000,%s,%s" % (self.source, path))
                source = self.commit_index()
                result = self.reuse(self.commit({"README.md": "# x\n"}), source=source)
                self.assertEqual(result["links"], ["%s (submodule; its files are not in the tree at %s)" % (path, label)
                                                   for label in ("head", "source")])
                self.assertEqual(result["status"], "FAIL")
                self.git("reset", "-q", self.source)

    def test_uncovered_link_is_documentation(self):
        source = self.linked_source({"docs/GUIDE-link.md": "/opt/elsewhere"})
        result = self.reuse(self.commit({"README.md": "# x\n"}), source=source)
        self.assertEqual((result["links"], result["status"]), ([], "PASS"))


class DiscoveryTests(unittest.TestCase):
    def test_build_folders_and_vendor_roots_are_not_packages(self):
        paths = ["Package.swift", "Examples/A/Package.swift", ".build/checkouts/X/Package.swift",
                 "Examples/A/.build/checkouts/Y/Package.swift", "vendor/Kit/Package.swift", "vendor/Package.swift",
                 "third_party/Z/Package.swift", "vendored/Kit/Package.swift", "Examples/vendor/Kit/Package.swift",
                 "Examples/A.build/Package.swift"]
        self.assertEqual(validate_local.native_packages(paths), [".", "Examples/A", "Examples/A.build",
                                                                 "Examples/vendor/Kit", "vendored/Kit"])


class NativeReceiptWriterTests(FixtureRepo):
    def write(self, path, run=None):
        calls = []

        def fake_run(command, cwd):
            calls.append(command)
            return subprocess.CompletedProcess(command, (run or (lambda c: 0))(command))

        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            try:
                status = writer.main([str(path)], root=self.repo, run=fake_run)
            except SystemExit as error:
                status = error.code
        return status, calls, err.getvalue()

    def receipt_path(self):
        evidence = tempfile.TemporaryDirectory()
        self.addCleanup(evidence.cleanup)
        return Path(evidence.name) / "native" / "receipt.json"

    def test_writer_uses_the_validator_discovery_and_documented_commands(self):
        self.assertEqual(list(validate_local.head_scope(self.source, self.repo)), PACKAGES)
        path = self.receipt_path()
        status, calls, _ = self.write(path)
        self.assertEqual(status, 0)
        self.assertEqual(calls, [["swift", "build"], ["swift", "test"],
                                 ["swift", "test", "--jobs", "2", "--package-path", "Examples/Solid3D"],
                                 ["swift", "test", "--jobs", "2", "--package-path", "Examples/Turbofan"],
                                 ["swift", "test", "--jobs", "2", "--package-path", "tools/SceneValidator"],
                                 ["swift", "build", "-c", "release", "--jobs", "2", "--package-path", "tools/SceneValidator"],
                                 ["tools/render-blender/selftest.sh"]])
        receipt = json.loads(path.read_text())
        self.assertEqual(receipt, {"source": self.source, "packages": [{"path": p, "exit": 0} for p in PACKAGES]})
        reuse = self.reuse(self.source, validate_local.read_native_receipt(path, self.source))
        self.assertEqual(reuse["status"], "PASS")

    def test_showcase_verifies_and_exports_to_a_new_folder_beside_the_receipt(self):
        self.source = self.commit({"Examples/Showcase/Package.swift": "// showcase\n",
                                   "Examples/Showcase/Sources/MartyShowcase/Showcase.swift": "let s = 1\n"})
        path = self.receipt_path()
        export = path.with_name("receipt-showcase-export")
        status, calls, _ = self.write(path)
        self.assertEqual(status, 0)
        showcase = [c for c in calls if "Examples/Showcase" in c]
        self.assertEqual(showcase, [
            ["swift", "build", "--jobs", "2", "--package-path", "Examples/Showcase"],
            ["swift", "run", "--skip-build", "--package-path", "Examples/Showcase", "marty-showcase", "--verify"],
            ["swift", "run", "--skip-build", "--package-path", "Examples/Showcase", "marty-showcase", "--export",
             str(export)]])
        self.assertIn({"path": "Examples/Showcase", "exit": 0}, json.loads(path.read_text())["packages"])
        again = path.with_name("again.json")
        again.with_name("again-showcase-export").mkdir()
        status, calls, err = self.write(again)
        self.assertEqual((status, calls, again.exists()), (2, [], False))
        self.assertIn("showcase export directory", err)

    def test_an_unlisted_package_runs_test_or_build(self):
        with_tests = ["Examples/NewKit/Package.swift", "Examples/NewKit/Tests/KitTests/KitTests.swift"]
        self.assertEqual(validate_local.native_commands("Examples/NewKit", with_tests),
                         [["swift", "test", "--jobs", "2", "--package-path", "Examples/NewKit"]])
        self.assertEqual(validate_local.native_commands("Examples/NewKit", with_tests[:1]),
                         [["swift", "build", "--jobs", "2", "--package-path", "Examples/NewKit"]])

    def test_first_failing_exit_is_recorded_and_fails_the_writer(self):
        path = self.receipt_path()

        def run(command):
            return {"Examples/Turbofan": 3, "tools/SceneValidator": 5}.get(command[-1], 0)

        status, calls, _ = self.write(path, run)
        self.assertEqual(status, 1)
        self.assertNotIn(["swift", "build", "-c", "release", "--jobs", "2", "--package-path", "tools/SceneValidator"], calls)
        exits = {p["path"]: p["exit"] for p in json.loads(path.read_text())["packages"]}
        self.assertEqual(exits, dict({p: 0 for p in PACKAGES}, **{"Examples/Turbofan": 3, "tools/SceneValidator": 5}))

    def test_missing_tool_counts_as_failure(self):
        path = self.receipt_path()

        def run(command):
            if command[0] == "swift":
                raise FileNotFoundError(command[0])
            return 0

        status, _, _ = self.write(path, run)
        exits = {p["path"]: p["exit"] for p in json.loads(path.read_text())["packages"]}
        self.assertEqual((status, exits["."], exits["tools/render-blender"]), (1, 127, 0))

    def test_refuses_a_dirty_checkout(self):
        for change in ("untracked", "modified"):
            with self.subTest(change=change):
                name = "scratch.txt" if change == "untracked" else "README.md"
                (self.repo / name).write_text("dirty\n")
                path = self.receipt_path()
                status, calls, err = self.write(path)
                self.assertEqual((status, calls, path.exists()), (2, [], False))
                self.assertIn("clean", err)
                self.git("reset", "-q", "--hard")
                self.git("clean", "-q", "-f")

    def test_refuses_a_path_inside_the_checkout_relative_or_existing(self):
        existing = self.receipt_path()
        existing.parent.mkdir(parents=True)
        existing.write_text("{}")
        for path in [self.repo / "native.json", self.repo / "docs" / "native.json", Path("native.json"), existing]:
            with self.subTest(path=path):
                status, calls, _ = self.write(path)
                self.assertEqual((status, calls), (2, []))
        self.assertFalse((self.repo / "native.json").exists())
        self.assertEqual(existing.read_text(), "{}")

    def test_refuses_when_the_checks_change_the_checkout(self):
        path = self.receipt_path()

        def run(command):
            (self.repo / "README.md").write_text("changed by a check\n")
            return 0

        status, _, err = self.write(path, run)
        self.assertEqual((status, path.exists()), (2, False))
        self.assertIn("changed the checkout", err)


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
        real_run, hygiene, printed = subprocess.run, [], []

        def fake_run(command, **kwargs):
            if kwargs.get("stdout") == subprocess.PIPE:  # git() through check_output, and cat-file
                return real_run(command, **kwargs)
            hygiene.append(command)
            return subprocess.CompletedProcess(command, 0)

        with mock.patch.object(validate_local, "ROOT", self.repo), mock.patch.object(sys, "argv", arguments), \
                mock.patch.object(validate_local.subprocess, "run", side_effect=fake_run), \
                mock.patch.object(validate_local.platform, "platform", return_value="synthetic-test-platform"), \
                mock.patch.object(validate_local.socket, "gethostname", return_value="synthetic-test-host"), \
                mock.patch("builtins.print", side_effect=lambda *a, **k: printed.append(" ".join(map(str, a)))):
            status = validate_local.main()
        self.assertEqual(len(hygiene), 5)
        self.assertFalse(any(c[:3] == ["git", "diff", "--exit-code"] for c in hygiene))
        self.printed = "\n".join(printed)
        return status, json.loads(receipt.read_text())

    def test_unchanged_tree_reuses_receipt(self):
        status, receipt = self.run_main(self.commit({"README.md": "# Changed\n"}))
        self.assertEqual((status, receipt["status"], receipt["nativeReuse"]["status"]), (0, "PASS", "PASS"))
        self.assertEqual(receipt["nativeReuse"]["packages"], PACKAGES)

    def test_changed_solid3d_file_fails_the_run(self):
        head = self.commit({"Examples/Solid3D/Sources/MartySolidCLI/main.swift": "x\n"})
        status, receipt = self.run_main(head)
        self.assertEqual((status, receipt["status"]), (1, "FAIL"))
        self.assertEqual(receipt["nativeReuse"]["changed"], ["Examples/Solid3D/Sources/MartySolidCLI/main.swift"])
        for text in ["docs/VERIFY-ON-MAC.md", "tools/write_native_receipt.py", "--native-source " + head,
                     "--native-receipt", "Changed native paths: Examples/Solid3D/Sources/MartySolidCLI/main.swift"]:
            self.assertIn(text, self.printed)

    def test_new_package_fails_the_run(self):
        status, receipt = self.run_main(self.commit({"Examples/NewKit/Package.swift": "// new\n"}))
        self.assertEqual((status, receipt["nativeReuse"]["missing"]), (1, ["Examples/NewKit"]))

    def test_receipt_missing_a_package_fails_the_run(self):
        status, receipt = self.run_main(self.commit({"README.md": "# Changed\n"}), packages=PACKAGES[:-1])
        self.assertEqual((status, receipt["nativeReuse"]["missing"]), (1, ["tools/render-blender"]))
        self.assertIn("Packages the receipt does not name: tools/render-blender", self.printed)

    def test_receipt_with_an_extra_failed_entry_fails_the_run(self):
        status, receipt = self.run_main(self.commit({"README.md": "# Changed\n"}), packages=PACKAGES + ["../outside"])
        self.assertEqual((status, receipt["nativeReuse"]["unexpected"]), (1, ["../outside"]))
        self.assertIn("Receipt entries that are not packages at HEAD: ../outside", self.printed)

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
        trees = {"head": validate_local.tree_entries("HEAD")}
        paths = sorted(trees["head"])
        packages = validate_local.native_packages(paths)
        self.assertEqual(packages, sorted({p.rpartition("/")[0] or "." for p in paths if p.endswith("/Package.swift")
                                           or p == "Package.swift"} | set(validate_local.NATIVE_TOOLS)))
        for package in [".", "Examples/Solid3D", "Examples/Turbofan", "Examples/LessonDemo", "Examples/KeySwitch3D",
                        "Examples/PathTrace", "Examples/Showcase", "tools/SceneValidator", "tools/render-blender"]:
            self.assertIn(package, packages)
        scope = validate_local.native_scope(trees, validate_local.scope_blobs(trees, validate_local.ROOT))
        self.assertEqual((scope["packages"], scope["problems"]), (packages, []))
        for name in ["Examples/Explainers", "docs/fixtures", "docs/assets", "CHANGELOG.md"]:
            self.assertIn(name, scope["inputs"])

    def test_docs_match_the_check(self):
        docs = {name: (validate_local.ROOT / name).read_text(encoding="utf-8")
                for name in ["docs/LOCAL-VALIDATION.md", "docs/VERIFY-ON-MAC.md"]}
        for name, text in docs.items():
            with self.subTest(name=name):
                self.assertFalse("UnitCircle" in text, "UnitCircle is named")
                for tool in validate_local.NATIVE_TOOLS:
                    self.assertIn(tool, text)
                command = "python3 tools/write_native_receipt.py /absolute/path/native-receipt.json"
                self.assertTrue(command in text, command)
        self.assertTrue("--native-receipt" in docs["docs/LOCAL-VALIDATION.md"])
        for name in validate_local.VENDOR_ROOTS + (".build", "PACKAGE_COMMANDS", validate_local.EXPORT_DIR):
            self.assertTrue("`%s`" % name in docs["docs/VERIFY-ON-MAC.md"], name)

    def test_documented_commands_are_the_code_commands_for_every_package(self):
        """The `# <package>` command block of docs/VERIFY-ON-MAC.md is PACKAGE_COMMANDS, which covers every package
        of this repository, and each one is what native_commands returns for it."""
        text = (validate_local.ROOT / "docs/VERIFY-ON-MAC.md").read_text(encoding="utf-8")
        block = re.search(r"```sh\n(# \.\n.*?)```", text, re.S).group(1)
        documented, package = {}, None
        for line in block.splitlines():
            if line.startswith("# "):
                package = line[2:]
                documented[package] = []
            else:
                documented[package].append(line)
        self.assertEqual(documented, validate_local.PACKAGE_COMMANDS)
        entries = validate_local.tree_entries("HEAD")
        packages = validate_local.native_packages(entries)
        self.assertEqual(sorted(documented), packages)
        for package in packages:
            with self.subTest(package=package):
                self.assertEqual(validate_local.native_commands(package, entries),
                                 [shlex.split(c) for c in documented[package]])
                if package not in (".",) + validate_local.NATIVE_TOOLS:  # starts with `swift test` iff it has tests
                    self.assertEqual(documented[package][0], validate_local.default_command(package, entries))
        self.assertEqual([c.split()[-2:] for c in documented["Examples/Showcase"][1:]],
                         [["marty-showcase", "--verify"], ["--export", validate_local.EXPORT_DIR]])


if __name__ == "__main__":
    unittest.main()
