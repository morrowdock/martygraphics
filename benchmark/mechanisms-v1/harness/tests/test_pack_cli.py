# SPDX-License-Identifier: Apache-2.0
"""CLI regressions against a temporary benchmark root and original synthetic data."""
import builtins
from contextlib import ExitStack, redirect_stderr
import csv
from datetime import timedelta
import hashlib
import io
import json
from pathlib import Path
import random
import tempfile
import unittest
from unittest.mock import patch

import support as S
import pack
from test_pack_runner import Media, fixture_normalise, make_runs, questions


class CLITest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bench = self.root / "benchmark"
        (self.bench / "harness").mkdir(parents=True)
        self.stack = self.enterContext(ExitStack())
        # Even a regression in main's path selection cannot reach real inputs.
        self.stack.enter_context(patch.object(pack, "__file__", str(self.bench / "harness" / "pack.py")))
        self.stack.enter_context(patch.object(pack, "normalise", fixture_normalise))
        media = Media()
        media.close = lambda: None
        self.stack.enter_context(patch.object(pack, "AppleMedia", return_value=media))
        clock = self.stack.enter_context(patch.object(pack, "datetime"))
        clock.now.return_value = S.BASE + timedelta(days=3)
        _, self.view = questions(1)
        pack.write_json(self.bench / "GRADER-QUESTIONS.json", self.view)
        (self.bench / "RUBRIC.md").write_bytes(b"Synthetic rubric\n")
        self.lock = {"inputs": {name: pack.digest(self.bench / name)
                               for name in ("GRADER-QUESTIONS.json", "RUBRIC.md")}}
        pack.write_json(self.bench / "LOCK.json", self.lock)
        self.seed = self.root / "seed.txt"
        self.seed.write_text(S.SEED.hex())
        self.dry_key = self.root / "dry.json"

    def prepare(self, dry=False, failed=()):
        if dry:
            self.view["questions"][0].update(id="DRY-BICYCLE", question=pack.DRY_RUN_QUESTION)
            pack.write_json(self.dry_key, self.view)
        self.runs, sources = make_runs(self.root, self.view, failed)
        if dry:
            rows = [r for r in csv.DictReader(self.runs.read_text().splitlines()) if r["run"] == "1"]
            order = [("DRY-BICYCLE", 1), ("DRY-BICYCLE", 2)]
            random.Random(20261111).shuffle(order)
            rows.sort(key=lambda r: order.index((r["question"], int(r["arm"]))))
            for i, row in enumerate(rows):
                row.update(startedUTC=(S.BASE + timedelta(minutes=2*i)).isoformat(),
                           endedUTC=(S.BASE + timedelta(minutes=2*i+1)).isoformat())
            with self.runs.open("w", newline="") as stream:
                writer = csv.DictWriter(stream, rows[0].keys())
                writer.writeheader()
                writer.writerows(rows)
            sources = {k: v for k, v in sources.items() if "-r1-" in k}
        self.sources = self.root / "sources.json"
        pack.write_json(self.sources, sources)
        self.out = self.root / "pack"
        self.argv = [str(self.runs), str(self.sources), "--seed", str(self.seed),
                     "--native", "unused-synthetic-media", "--out", str(self.out)]
        if dry:
            self.argv += ["--dry-run-questions", str(self.dry_key)]

    def forbid_registered(self):
        blocked = {self.bench / name for name in ("QUESTIONS.json", "GRADER-QUESTIONS.json")}
        self.attempts = []
        def guard(original):
            def opened(path, *args, **kwargs):
                if not isinstance(path, int) and Path(path).resolve() in blocked:
                    self.attempts.append(str(path))
                    raise PermissionError("synthetic registered input sentinel")
                return original(path, *args, **kwargs)
            return opened
        self.stack.enter_context(patch("builtins.open", guard(builtins.open)))
        self.stack.enter_context(patch("io.open", guard(io.open)))

    def refused(self, message):
        stderr = io.StringIO()
        with redirect_stderr(stderr), self.assertRaises(SystemExit) as error:
            pack.main(self.argv)
        self.assertEqual(error.exception.code, 2)
        self.assertIn(message, stderr.getvalue())
        self.assertFalse(self.out.exists())

    def test_dry_cli_never_opens_registered_inputs(self):
        self.prepare(dry=True)
        self.forbid_registered()
        self.assertEqual(pack.main(self.argv), 0)
        self.assertEqual(self.attempts, [])
        doc = json.loads((self.out / "PRIVATE.json").read_text())
        self.assertEqual(doc["scope"], "dry-run")
        self.assertIs(doc["registeredQuestionFilesRead"], False)
        self.assertEqual(doc["questions"], self.view)
        self.assertEqual(len(doc["calls"]), 3)

    def test_dry_cli_rejects_wrong_id_question_and_private_fields(self):
        self.prepare(dry=True)
        self.forbid_registered()
        q = self.view["questions"][0]
        for field, value, message in (("id", "MECH-01", "DRY-BICYCLE"),
                                      ("id", "DRY-OTHER", "DRY-BICYCLE"),
                                      ("question", "Other synthetic question", "bicycle question"),
                                      ("category", "private", "invalid")):
            with self.subTest(field=field, value=value):
                original = dict(q)
                q[field] = value
                pack.write_json(self.dry_key, self.view)
                self.refused(message)
                q.clear()
                q.update(original)
        self.assertEqual(self.attempts, [])

    def test_dry_cli_still_checks_rubric_hash(self):
        self.prepare(dry=True)
        self.forbid_registered()
        (self.bench / "RUBRIC.md").write_text("Changed synthetic rubric")
        self.refused("registered input hash mismatch: RUBRIC.md")
        self.assertEqual(self.attempts, [])

    def test_dry_cli_refuses_registered_path_and_alias_before_open(self):
        self.prepare(dry=True)
        self.forbid_registered()
        for name in ("QUESTIONS.json", "GRADER-QUESTIONS.json"):
            target = self.bench / name
            alias = self.root / (name + ".link")
            alias.symlink_to(target)
            for path in (target, alias):
                with self.subTest(path=path):
                    self.argv[-1] = str(path)
                    self.refused("dry-run key must not be a registered question file")
        self.assertEqual(self.attempts, [])

    def test_dry_cli_refuses_registered_hard_link(self):
        self.prepare(dry=True)
        alias = self.root / "hard-link.json"
        alias.hardlink_to(self.bench / "GRADER-QUESTIONS.json")
        self.argv[-1] = str(alias)
        self.forbid_registered()
        self.refused("dry-run key must not be a registered question file")
        self.assertEqual(self.attempts, [])

    def test_registered_cli_keeps_hash_refusal(self):
        self.prepare()
        for name in ("GRADER-QUESTIONS.json", "RUBRIC.md"):
            with self.subTest(name=name):
                path = self.bench / name
                original = path.read_bytes()
                path.write_bytes(b"Changed synthetic input")
                self.refused("registered input hash mismatch: " + name)
                path.write_bytes(original)

    def test_registered_cli_matches_baseline_golden_tree(self):
        # SHA-256 of the sorted relative-path -> file-SHA-256 JSON mapping.
        # Captured from main 9c22a5a50cc37ff7717c68f5be5f7a42af1d0c1f,
        # Python 3.12, fixed seed/time, original synthetic fixtures above.
        # Covers every output byte, including private manifest and packet files.
        self.prepare()
        self.assertEqual(pack.main(self.argv), 0)
        tree = json.dumps(pack.tree_hashes(self.out), sort_keys=True).encode()
        self.assertEqual(hashlib.sha256(tree).hexdigest(), "4224f09d3916ff9dce095a3154d8f8d23b387d290486bf7035c55c729d36e453")


if __name__ == "__main__":
    unittest.main()
