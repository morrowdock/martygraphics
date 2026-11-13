# SPDX-License-Identifier: Apache-2.0
"""Original synthetic questions, pixels and replies only; no benchmark input read."""
import copy
import csv
from datetime import timedelta
from fractions import Fraction
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import support as S
import pack
import grading_runner as runner


class Clock:
    def __init__(self):
        self.time = S.BASE + timedelta(days=3)
    def __call__(self):
        self.time += timedelta(seconds=1)
        return self.time


class Publication:
    """Test-only substitute for public git IO. Not in the shipped CLI."""
    def verify(self, commitment, not_before, clock):
        return {"observedUTC": clock().isoformat(), "commitment": commitment, "fixture": True}


class Media:
    """Original neutral RGB fixture, no OCR words, no real renderer or video."""
    def __init__(self, counts=None):
        self.counts = counts or {}
        self.frames = []
        self.calls = 0
    def prepare(self, source, arm, work):
        p = work / "frame.rgb"
        p.write_bytes(bytes((80, 90, 100)) * (1280 * 800))
        return [str(p)] * self.counts.get(arm, 1)
    def ocr(self, path):
        self.calls += 1
        return []
    def thumbnail(self, path):
        return bytes((80, 90, 100)) * (256 * 160)
    def video(self, paths, path):
        self.frames.append(len(paths))
        path.write_bytes(b"synthetic video placeholder; never primary grader evidence")


def questions(n):
    key = S.many_questions(n)
    for q in key["questions"]:
        q.update(question="What does the synthetic shape do?", conventional="Synthetic shape")
        for f in q["keyFacts"]:
            f.update(fact="Synthetic fact", acceptedWordings=[])
        for c in q["mechanismChecks"]:
            c.update(kind="synthetic", **{"pass": "Synthetic condition"})
    view = copy.deepcopy(key)
    view["kind"] = "grader-questions/2"
    for q in view["questions"]:
        del q["category"]
    return key, view


def make_runs(root, view, failed=()):
    import random
    slots = sorted((q["id"], a, r) for q in view["questions"] for a in (1, 2) for r in (1, 2, 3))
    random.Random(20261111).shuffle(slots)
    path = root / "runs.csv"
    sources = {}
    with path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["question", "arm", "run", "status", "startedUTC", "endedUTC", "tries", "costUsd"])
        for i, (q, a, r) in enumerate(slots):
            start = S.BASE + timedelta(minutes=i * 2)
            sid = S.score.slot_id(q, a, r)
            status = "failed" if (q, a, r) in failed else "rendered"
            writer.writerow([q, a, r, status, start.isoformat(), (start + timedelta(minutes=1)).isoformat(), 1, 0])
            if status == "rendered":
                sources[sid] = {"kind": "synthetic", "id": sid}
    return path, sources


PROMPTS = {"score": "Synthetic score {token}", "preference": "Synthetic preference {token}", "guess": "Synthetic guess"}


def entries(doc, overrides=None):
    overrides = overrides or {}
    result = []
    for g in S.score.GRADERS:
        for c in pack.call_order(S.SEED, g, doc["calls"]):
            kind, q = c["kind"], c["question"]
            if kind == "score":
                arm = int(c["id"][-1])
                n = 5 if (int(q[1:]) < 15) == (arm == 1) else 1
                valid = S.reply((q, arm, 1), S.prefix(n), output=c["token"])
            else:
                valid = {"question": q, "pair": c["token"], "preference": "tie", "preferenceReason": "Synthetic"}
            attempts = overrides.get((g, kind, c["id"]), [[json.dumps(valid)]])
            for replies in attempts:
                result.append({"grader": g, "kind": kind, "token": c["token"], "replies": replies})
            if kind == "preference" and any(not S.score.form.check_text(kind, text, {"id": q}, c["token"])[1]
                                            for session in attempts for text in session):
                result.append({"grader": g, "kind": "guess", "token": c["token"],
                               "replies": [json.dumps(S.guess("cannot tell"))]})
    return result


def fixture_normalise(frames, target, destination, media):
    """Small ORIGINAL stored media fixture for refusal tests, not the end-to-end test."""
    destination.mkdir()
    (destination / "sheets").mkdir()
    for n in range(1, 6):
        pack.png(destination / ("still-%d.png" % n), b"\0\0\0", 1, 1)
    for n in range(1, 5):
        pack.png(destination / "sheets" / ("sheet-%02d.png" % n), b"\0\0\0", 1, 1)
    (destination / "TEXT.txt").write_text("Synthetic")
    (destination / "video.mp4").write_bytes(b"synthetic")
    return {"TFrames": target}


class PipelineFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.clock = Clock()
        self.key, self.view = questions(1)
        self.runs, self.sources = make_runs(self.root, self.view)

    def build(self, full=False, failed=()):
        if failed:
            self.runs, self.sources = make_runs(self.root, self.view, failed)
        out = self.root / "pack"
        if full:
            pack.build(self.runs, self.sources, self.view, b"Synthetic rubric", S.SEED, out, Media(), self.clock)
        else:
            with patch.object(pack, "normalise", fixture_normalise):
                pack.build(self.runs, self.sources, self.view, b"Synthetic rubric", S.SEED, out, Media(), self.clock)
        return out, json.loads((out / "PRIVATE.json").read_text())

class PipelineTest(PipelineFixture):
    def test_full_twenty_question_pack_grade_analyse_registered_win(self):
        # All media decisions run; only native IO is synthetic. No real questions,
        # outputs, grader text, Apple framework, model or network call is used.
        self.key, self.view = questions(20)
        self.runs, self.sources = make_runs(self.root, self.view)
        out, doc = self.build(full=True)
        self.assertFalse((out / "BLINDING-SEED.txt").exists())
        result = runner.run(out, runner.RecordedAdapter(entries(doc)), Publication(), PROMPTS, self.clock)
        self.assertEqual(len(result["calls"]), 480)
        key = S.score.load_key(S.write_key(self.root, self.key))
        analysis = S.score.analyse(S.score.load_input(out, key), key)
        self.assertEqual(analysis["verdict"], {"verdict": "win", "status": "registered verdict (completed design)"})
        self.assertEqual(analysis["primary"]["signTest"]["p"], Fraction(5425, 131072))
        self.assertEqual(analysis["design"]["callStatus"], {"completed": 480})
        self.assertFalse(analysis["design"]["timingFindings"])
        for g in S.score.GRADERS:
            actual = [c["id"] for c in result["calls"] if c["grader"] == g and c["kind"] != "guess"]
            self.assertEqual(actual, [c["id"] for c in pack.call_order(S.SEED, g, doc["calls"])])
        for path in (out / "packets").rglob("*"):
            self.assertNotIn("arm", path.name)
            self.assertNotEqual(path.name, "video.mp4")
        self.assertEqual((out / "BLINDING-SEED.txt").read_text().strip(), S.SEED.hex())

    def test_fixup_new_sessions_exhaustion_and_guess_gate(self):
        out, doc = self.build()
        score_call = next(c for c in doc["calls"] if c["kind"] == "score")
        pref = next(c for c in doc["calls"] if c["kind"] == "preference")
        valid = json.dumps(S.reply((score_call["question"], 1, 1), output=score_call["token"]))
        overrides = {("G1", "score", score_call["id"]): [[b"\xff", "{}"], ["not json", valid]],
                     ("G2", "score", score_call["id"]): [["{}", "{}"]] * 3,
                     ("G1", "preference", pref["id"]): [["{}", "{}"]] * 3}
        adapter = runner.RecordedAdapter(entries(doc, overrides))
        with patch.object(runner.form, "next_step", wraps=runner.form.next_step) as next_step:
            record = runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        key = S.score.load_key(S.write_key(self.root, self.key))
        loaded = S.score.load_input(out, key)["record"]
        self.assertEqual(loaded["calls"][("G1", "score", score_call["id"])]["status"], "completed")
        self.assertEqual(loaded["calls"][("G2", "score", score_call["id"])]["attempts"], 6)
        self.assertNotIn(("G1", "guess", pref["id"]), loaded["calls"])
        self.assertTrue(any("not UTF-8" in m for m in adapter.messages))
        self.assertGreaterEqual(next_step.call_count, sum(len(s["replies"]) for c in record["calls"] for s in c["sessions"]))
        self.assertEqual((out / "replies" / "G1" / "score" / score_call["id"] / "1-1.txt").read_bytes(), b"\xff")
        self.assertFalse(loaded["timing"])

    def test_preference_is_durable_before_every_guess_session(self):
        out, doc = self.build()
        base = runner.RecordedAdapter(entries(doc))
        opens = []
        class Audit:
            def open(inner, grader, kind, packet, *, session_id):
                record = json.loads((out / "RECORD.json").read_text())
                entry = record["calls"][-1]
                self.assertEqual(entry["kind"], kind)
                self.assertFalse(entry["sessions"][-1]["replies"])
                if kind == "guess":
                    pref = record["calls"][-2]
                    stored = pref["sessions"][-1]["replies"][-1]
                    self.assertTrue((out / stored["file"]).is_file())
                    self.assertGreaterEqual(entry["sessions"][0]["startedUTC"], stored["receivedUTC"])
                files = list(packet.rglob("*"))
                self.assertFalse(any(p.is_symlink() for p in files))
                self.assertFalse(any(p.name in ("PRIVATE.json", "RECORD.json", "video.mp4") for p in files))
                self.assertEqual(list(packet.parent.iterdir()), [packet])
                opens.append((grader, kind))
                return base.open(grader, kind, packet, session_id=session_id)
        runner.run(out, Audit(), Publication(), PROMPTS, self.clock)
        self.assertEqual(len(opens), 24)

    def test_failed_partner_still_scored_no_preference(self):
        out, doc = self.build(failed=[("Q00", 2, 1), ("Q00", 1, 2), ("Q00", 2, 2)])
        self.assertEqual(sum(c["kind"] == "score" for c in doc["calls"]), 3)
        self.assertEqual(sum(c["kind"] == "preference" for c in doc["calls"]), 1)
        runner.run(out, runner.RecordedAdapter(entries(doc)), Publication(), PROMPTS, self.clock)
        key = S.score.load_key(S.write_key(self.root, self.key))
        self.assertFalse(S.score.load_input(out, key)["record"]["timing"])

    def test_pack_rejects_wrong_source_set_and_existing_destination(self):
        with self.assertRaisesRegex(ValueError, "sources"):
            pack.build(self.runs, {}, self.view, b"rubric", S.SEED, self.root / "x", Media(), self.clock)
        out, _ = self.build()
        with self.assertRaises(FileExistsError):
            pack.build(self.runs, self.sources, self.view, b"rubric", S.SEED, out, Media(), self.clock)

    def test_question_private_fields_refused(self):
        for target, field in ((self.view["questions"][0], "category"),
                              (self.view["questions"][0]["keyFacts"][0], "sources"),
                              (self.view["questions"][0]["mechanismChecks"][0], "notes")):
            target[field] = "PRIVATE"
            with self.assertRaises(ValueError): pack.check_questions(self.view)
            del target[field]
        self.view["questions"].append(self.view["questions"][0])
        with self.assertRaises(ValueError): pack.check_questions(self.view)

    def test_bad_runs_refused(self):
        original = self.runs.read_text()
        lines = original.splitlines()
        for value in ("\n".join(lines[:-1]), "\n".join(lines + [lines[1]])):
            self.runs.write_text(value)
            with self.assertRaises(ValueError): pack.complete_runs(self.runs, {"Q00": {}})
        self.runs.write_text(original)
        rows = list(csv.DictReader(lines))
        for field, value in (("endedUTC", "2026-11-01T00:00:00Z"), ("endedUTC", "2026-12-01T00:03:00Z"),
                             ("endedUTC", "2026-12-10T00:00:00Z")):
            edited = copy.deepcopy(rows)
            edited[0][field] = value
            with self.runs.open("w", newline="") as f:
                writer = csv.DictWriter(f, rows[0].keys()); writer.writeheader(); writer.writerows(edited)
            with self.assertRaises(ValueError): pack.complete_runs(self.runs, {"Q00": {}})

    def test_packet_change_stops_before_adapter(self):
        out, doc = self.build()
        path = next((out / "packets").rglob("TEXT.txt"))
        path.write_text("changed")
        adapter = unittest.mock.Mock()
        with self.assertRaisesRegex(ValueError, "changed"):
            runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        adapter.open.assert_not_called()

    def test_modified_private_control_fields_refused(self):
        out, original = self.build()
        edits = [lambda d: d.update(scope="unknown"), lambda d: d.update(kind="bad"), lambda d: d.update(seed="00" * 32),
                 lambda d: d["calls"].pop(), lambda d: d["orders"]["G1"].reverse(),
                 lambda d: d.update(packedUTC="2020-01-01T00:00:00Z"),
                 lambda d: d.update(runsSha256="bad")]
        for edit in edits:
            doc = copy.deepcopy(original); edit(doc)
            pack.write_json(out / "PRIVATE.json", doc)
            with self.subTest(doc=doc.get("kind")), self.assertRaises(ValueError): runner.load_pack(out)
        pack.write_json(out / "PRIVATE.json", original)
        (out / "BLINDING-SEED.txt").write_text(S.SEED.hex())
        with self.assertRaisesRegex(ValueError, "released"): runner.load_pack(out)

    def test_symlink_and_extra_file_even_with_updated_manifest_refused(self):
        out, doc = self.build()
        token = doc["calls"][0]["token"]
        extra = out / "packets" / token / "secret.txt"
        extra.symlink_to(out / "PRIVATE.json")
        with self.assertRaisesRegex(ValueError, "symlink"): runner.load_pack(out)
        extra.unlink(); extra.write_text("unexpected")
        doc["packetHashes"] = pack.tree_hashes(out / "packets")
        pack.write_json(out / "PRIVATE.json", doc)
        with self.assertRaisesRegex(ValueError, "extra"): runner.load_pack(out)

    def test_unpublished_commitment_never_opens_session(self):
        out, doc = self.build()
        pub, adapter = unittest.mock.Mock(), unittest.mock.Mock()
        pub.verify.side_effect = ValueError("not publicly committed")
        with self.assertRaisesRegex(ValueError, "publicly"):
            runner.run(out, adapter, pub, PROMPTS, self.clock)
        adapter.open.assert_not_called()
        self.assertFalse((out / "RUNNER-STARTED").exists())
        runner.run(out, runner.RecordedAdapter(entries(doc)), Publication(), PROMPTS, self.clock)

    def test_clock_regression_stops_before_session(self):
        out, _ = self.build()
        pub, adapter = unittest.mock.Mock(), unittest.mock.Mock()
        pub.verify.return_value = {"observedUTC": (self.clock.time + timedelta(days=1)).isoformat(),
                                   "commitment": S.blinding.commitment(S.SEED)}
        with self.assertRaisesRegex(ValueError, "backwards"):
            runner.run(out, adapter, pub, PROMPTS, self.clock)
        adapter.open.assert_not_called()

    def test_adapter_error_keeps_incomplete_record_no_reveal_or_retry(self):
        out, _ = self.build()
        adapter = unittest.mock.Mock()
        adapter.open.return_value.reply.side_effect = RuntimeError("offline adapter failed")
        with self.assertRaisesRegex(RuntimeError, "failed"):
            runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        self.assertFalse((out / "BLINDING-SEED.txt").exists())
        adapter.open.assert_called_once()
        adapter.open.return_value.close.assert_called_once()
        with self.assertRaisesRegex(ValueError, "uncertain request"):
            runner.run(out, adapter, Publication(), PROMPTS, self.clock)


class PixelAndOrderTest(unittest.TestCase):
    def test_order_vector_and_input_order_independence(self):
        calls = [{"kind": k, "token": str(i)} for k in ("score", "preference") for i in range(3)]
        result = [(c["kind"], c["token"]) for c in pack.call_order(S.SEED, "G1", calls)]
        self.assertEqual(result, ORDER_VECTOR)
        self.assertEqual(pack.call_order(S.SEED, "G1", calls), pack.call_order(S.SEED, "G1", list(reversed(calls))))
        self.assertNotEqual(pack.call_order(S.SEED, "G1", calls), pack.call_order(S.SEED, "G2", calls))
        for g, rows in (("G3", calls), ("G1", calls + calls[:1]), ("G1", [{"kind": "guess", "token": "1"}])):
            with self.assertRaises(ValueError): pack.call_order(S.SEED, g, rows)

    def test_mask_span_padding_ring_and_limitations(self):
        rgb = bytes((10, 20, 30)) * 100
        raw = bytearray(rgb)
        raw[(4 * 10 + 4) * 3:(4 * 10 + 5) * 3] = b"\xff" * 3
        line = {"text": "Schematic Marty", "matches": [{"rule": "B1", "box": [4, 4, 1, 1]}]}
        self.assertEqual(pack.mask(raw, [line], 0, 10, 10), rgb)
        self.assertEqual(pack.mask(raw, [], 3, 10, 10), raw)
        import re
        for honest in ("Schematic motion", "Solved 4 (animation ratios)", "Not checked", "Arrow lengths are not to scale"):
            self.assertFalse(any(re.search(pattern, honest) for pattern in pack.PATTERNS.values()))
        for text, rule in (("Rendered by some tool (2 lines)", "P1"), ("three.js", "B1"), ("a.json", "F1")):
            self.assertIsNotNone(re.search(pack.PATTERNS[rule], text))
        self.assertIsNone(re.search(pack.PATTERNS["B1"], "Martyish"))

    def test_mask_refusals(self):
        for rule, box, pad in (("X", [1, 1, 1, 1], 0), ("B1", [float("nan"), 1, 1, 1], 0),
                               ("B1", [100, 1, 1, 1], 0), ("B1", [0, 0, 10, 10], 0)):
            with self.assertRaises(ValueError):
                pack.mask(bytes(300), [{"matches": [{"rule": rule, "box": box}]}], pad, 10, 10)
        with self.assertRaisesRegex(ValueError, "size"): pack.mask(b"", [], 3)

    def test_png_has_only_required_chunks(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "x.png"
            pack.png(path, b"\x01\x02\x03", 1, 1)
            raw, at, kinds = path.read_bytes(), 8, []
            while at < len(raw):
                size = struct.unpack_from(">I", raw, at)[0]
                kinds.append(raw[at+4:at+8]); at += size + 12
            self.assertEqual(kinds, [b"IHDR", b"IDAT", b"IEND"])
            with self.assertRaises(ValueError): pack.png(path, b"", 1, 1)

    def test_normalisation_sampling_padding_residual_and_text(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            media = Media()
            frames = media.prepare({}, 1, root)
            seen = []
            def ocr(path):
                seen.append(path.name)
                return [{"text": "Synthetic", "matches": []}]
            media.ocr = ocr
            report = pack.normalise(frames, 330, root / "out", media)
            self.assertEqual((report["LFrames"], report["TFrames"], report["heldFrames"]), (300, 330, 329))
            self.assertEqual(media.frames, [330])
            self.assertEqual((root / "out" / "TEXT.txt").read_text(), "Synthetic\n")
            self.assertEqual(len(list((root / "out" / "sheets").glob("*"))), 5)
            self.assertEqual(len(seen), 330 + 10 + 22) # each frame, two passes per still, 0.5 s transcript
            for frames, target in (([], 300), (["x"], 299), (["x"], 1801)):
                with self.assertRaises(ValueError): pack.normalise(frames, target, root / "bad", media)

    def test_public_branch_validation(self):
        for branch in ("../main", "-x", "a//b", "main:other", "main x"):
            with self.assertRaises(ValueError): runner.PublicCommitment(branch)

    def test_mp4_scrubs_optional_metadata_and_refuses_bad_layout(self):
        def atom(kind, data): return struct.pack(">I4s", len(data) + 8, kind) + data
        entry = bytearray(86); struct.pack_into(">I4s", entry, 0, 86, b"avc1"); entry[50:82] = b"x" * 32
        stsd = atom(b"stsd", bytes(4) + struct.pack(">I", 1) + entry)
        hdlr = atom(b"hdlr", bytes(8) + b"vide" + bytes(12) + b"Encoder")
        moov = atom(b"moov", atom(b"mvhd", bytes(4) + b"x" * 16) + atom(b"udta", b"secret") +
                    atom(b"trak", atom(b"mdia", hdlr + atom(b"minf", atom(b"stbl", stsd)))))
        raw = atom(b"ftyp", b"isom") + moov + atom(b"mdat", b"pixels")
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "v.mp4"; path.write_bytes(raw)
            pack.scrub_mp4(path)
            self.assertEqual(len(path.read_bytes()), len(raw))
            self.assertNotIn(b"secret", path.read_bytes()); self.assertNotIn(b"Encoder", path.read_bytes())
            first = path.read_bytes(); pack.scrub_mp4(path); self.assertEqual(first, path.read_bytes())
            for bad in (b"short", atom(b"mdat", b"pixels") + moov, raw.replace(b"vide", b"soun"), raw.replace(b"avc1", b"hvc1")):
                path.write_bytes(bad)
                with self.assertRaises(ValueError): pack.scrub_mp4(path)


ORDER_VECTOR = [('score', '1'), ('preference', '1'), ('preference', '2'), ('preference', '0'), ('score', '2'), ('score', '0')]  # Seed 000102...1f, order:G1.

class RefusalTest(PipelineFixture):
    def test_seed_clock_empty_source_and_collision_refusals(self):
        for seed, clock, media, message in ((b"short", self.clock, Media(), "seed"),
                    (S.SEED, lambda: S.BASE, Media(), "before generation")):
            with self.assertRaisesRegex(ValueError, message):
                pack.build(self.runs, self.sources, self.view, b"rubric", seed, self.root / "bad", media, clock)
        media = Media()
        media.prepare = lambda *args: []
        with self.assertRaisesRegex(ValueError, "empty rendered"):
            pack.build(self.runs, self.sources, self.view, b"rubric", S.SEED, self.root / "empty", media, self.clock)
        with patch.object(pack, "normalise", fixture_normalise), patch.object(pack.blinding, "output_token", return_value="0" * 12):
            with self.assertRaisesRegex(ValueError, "collision"):
                pack.build(self.runs, self.sources, self.view, b"rubric", S.SEED, self.root / "collision", Media(), self.clock)

    def test_no_new_seed_until_all_normalisation_finishes(self):
        completed = []
        def normalize(*args):
            completed.append(1)
            return fixture_normalise(*args)
        def seed(n):
            self.assertEqual(len(completed), 6)
            self.assertEqual(n, 32)
            return S.SEED
        with patch.object(pack, "normalise", normalize), patch.object(pack.os, "urandom", side_effect=seed):
            pack.build(self.runs, self.sources, self.view, b"rubric", None, self.root / "pack", Media(), self.clock)

    def test_question_and_sheet_changes_refused(self):
        out, doc = self.build()
        folder = out / "packets" / doc["calls"][0]["token"]
        qpath = folder / "question.json"
        original = qpath.read_bytes()
        q = json.loads(original); q["question"] = "Changed"
        pack.write_json(qpath, q)
        doc["packetHashes"] = pack.tree_hashes(out / "packets")
        pack.write_json(out / "PRIVATE.json", doc)
        with self.assertRaisesRegex(ValueError, "question changed"): runner.load_pack(out)
        qpath.write_bytes(original)
        (folder / "output" / "sheets" / "sheet-01.png").unlink()
        doc["packetHashes"] = pack.tree_hashes(out / "packets")
        pack.write_json(out / "PRIVATE.json", doc)
        with self.assertRaisesRegex(ValueError, "sheet sequence"): runner.load_pack(out)

    def test_missing_prompts_and_invalid_publication_proof(self):
        out, _ = self.build()
        adapter = unittest.mock.Mock()
        with self.assertRaisesRegex(ValueError, "prompts"):
            runner.run(out, adapter, Publication(), {}, self.clock)
        pub = unittest.mock.Mock()
        pub.verify.return_value = {"observedUTC": S.BASE.isoformat(), "commitment": "bad"}
        with self.assertRaisesRegex(ValueError, "proof"):
            runner.run(out, adapter, pub, PROMPTS, self.clock)
        adapter.open.assert_not_called()

    def test_non_bytes_adapter_refused(self):
        out, _ = self.build()
        adapter = unittest.mock.Mock()
        adapter.open.return_value.reply.return_value = "not exact bytes"
        with self.assertRaisesRegex(ValueError, "exact reply bytes"):
            runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        self.assertFalse((out / "BLINDING-SEED.txt").exists())

    def test_guess_clock_regression_refused_before_adapter_open(self):
        out, doc = self.build()
        base = runner.RecordedAdapter(entries(doc))
        guess_opened = []
        clock = self.clock
        class Audit:
            def open(inner, g, kind, packet, *, session_id):
                if kind == "guess": guess_opened.append(1)
                handle = base.open(g, kind, packet, session_id=session_id)
                original_close = handle.close
                def close():
                    original_close()
                    if kind == "preference": clock.time -= timedelta(minutes=1)
                handle.close = close
                return handle
        with self.assertRaisesRegex(ValueError, "backwards"):
            runner.run(out, Audit(), Publication(), PROMPTS, clock)
        self.assertEqual(guess_opened, [])
        self.assertFalse((out / "BLINDING-SEED.txt").exists())

    def test_all_failed_design_has_no_grader_calls(self):
        failed = [("Q00", a, r) for a in (1, 2) for r in (1, 2, 3)]
        out, doc = self.build(failed=failed)
        adapter = unittest.mock.Mock()
        result = runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        self.assertEqual(result["calls"], [])
        adapter.open.assert_not_called()

    def test_new_session_gets_no_previous_reply_or_feedback(self):
        out, doc = self.build()
        target = next(c for c in doc["calls"] if c["kind"] == "score")
        plan = entries(doc, {("G1", "score", target["id"]): [["{}", "{}"]] * 3})
        adapter = runner.RecordedAdapter(plan)
        record = runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        call = next(c for c in record["calls"] if (c["grader"], c["kind"], c["id"]) == ("G1", "score", target["id"]))
        self.assertEqual([len(s["replies"]) for s in call["sessions"]], [2, 2, 2])
        self.assertEqual(adapter.messages.count(PROMPTS["score"].replace("{token}", target["token"])), 4) # 3 G1, 1 G2


class MediaBoundaryTest(unittest.TestCase):
    def test_native_adapter_refuses_wrong_arm_and_worker_error(self):
        media = pack.AppleMedia("unused")
        with self.assertRaisesRegex(ValueError, "Arm 1"):
            media.prepare({"kind": "captures"}, 1, Path("unused"))
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "worker"
            path.write_text('#!/usr/bin/env python3\nimport sys\nfor line in sys.stdin:\n print(\'{"error":"synthetic native error"}\', flush=True)\n')
            path.chmod(0o755)
            media = pack.AppleMedia(path)
            try:
                with self.assertRaisesRegex(ValueError, "synthetic native error"):
                    media.ocr(Path("unused"))
            finally: media.close()
            path.write_text('#!/usr/bin/env python3\n')
            media = pack.AppleMedia(path)
            try:
                with self.assertRaisesRegex(ValueError, "stopped"):
                    media.ocr(Path("unused"))
            finally: media.close()

    def test_public_commitment_git_success_and_refusals(self):
        committed = S.blinding.commitment(S.SEED)
        clock = Clock()
        with patch.object(runner.subprocess, "run") as git:
            def answers(value=committed, names=b"", when=None):
                def response(argv, **kwargs):
                    if "show" in argv: out = value.encode()
                    elif "ls-tree" in argv: out = names
                    elif "rev-parse" in argv: out = b"a" * 40
                    else: out = b""
                    return unittest.mock.Mock(stdout=out)
                git.side_effect = response
                return runner.PublicCommitment("review/commitment").verify(committed, when or S.BASE, clock)
            proof = answers()
            self.assertEqual(proof["commitment"], committed)
            self.assertEqual(proof["commit"], "a" * 40)
            with self.assertRaisesRegex(ValueError, "does not match"): answers("0" * 64)
            with self.assertRaisesRegex(ValueError, "public before"):
                answers(names=b"benchmark/mechanisms-v1/results/BLINDING-SEED.txt\n")
            with self.assertRaisesRegex(ValueError, "predates"):
                answers(when=clock.time + timedelta(days=1))

    def test_native_request_timeout(self):
        with patch.object(pack.subprocess, "Popen") as process, patch.object(pack.selectors, "DefaultSelector") as selector:
            process.return_value = unittest.mock.Mock()
            selector.return_value.__enter__.return_value.select.return_value = []
            media = pack.AppleMedia("unused")
            with self.assertRaisesRegex(ValueError, "timed out"):
                media.ocr(Path("unused"))
            process.return_value.wait.assert_called_once()

    def test_still_indices_crop_and_second_pass_residuals(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            # Index-only fake path objects keep this boundary test fast while the
            # full pipeline test uses actual 1280x800 files and PNG writers.
            media = Media()
            p = root / "source.rgb"; p.write_bytes(bytes(1280 * 800 * 3))
            frames = [p] * 1803
            ocr_calls, sheets, stills = [], [], []
            def ocr(path):
                ocr_calls.append(path.name)
                return [{"text": "remaining", "matches": [{"rule": "B1", "box": [20, 20, 2, 2]}]}]
            media.ocr = ocr
            def png(path, *args): stills.append(path.name)
            pads = []
            def mask_pixels(rgb, lines, pad):
                pads.append(pad)
                return rgb
            with patch.object(pack, "mask", mask_pixels), \
                 patch.object(pack, "png", png), \
                 patch.object(pack, "sheet", lambda path, thumbs: sheets.extend(k for k, _ in thumbs)):
                report = pack.normalise(frames, 1800, root / "out", media)
            self.assertTrue(report["cut"])
            self.assertEqual(report["LFrames"], 1800)
            self.assertEqual(media.frames, [1800])
            self.assertEqual(sheets, list(range(0, 1800, 3)))
            self.assertEqual(stills, ["still-%d.png" % i for i in range(1, 6)])
            self.assertEqual(len(report["residualMatches"]), 5)
            self.assertEqual((pads.count(3), pads.count(6)), (1800, 5))
            # First OCR on each raw frame plus OCR for stills/transcript is retained.
            self.assertEqual(ocr_calls.count("source.rgb"), 1800)

    def test_recorded_adapter_wrong_identity_and_reply_token(self):
        adapter = runner.RecordedAdapter([{"grader": "G1", "kind": "score", "token": "known", "replies": ["{}"]}])
        with self.assertRaisesRegex(ValueError, "grader and kind"): adapter.open("G2", "score", Path("unused"), session_id=runner.session_key("G1", "score", "known", 1))
        adapter = runner.RecordedAdapter([{"grader": "G1", "kind": "score", "token": "known", "replies": ["{}"]}])
        handle = adapter.open("G1", "score", Path("unused"), session_id=runner.session_key("G1", "score", "known", 1))
        with self.assertRaisesRegex(ValueError, "token mismatch"): handle.reply("wrong token")

class AdditionalRefusalTest(PipelineFixture):
    def test_packet_changes_during_grading_refused(self):
        out, doc = self.build()
        base = runner.RecordedAdapter(entries(doc))
        class Change:
            def open(inner, g, kind, packet, *, session_id):
                handle = base.open(g, kind, packet, session_id=session_id)
                # Alter every staged packet after the first copied session starts.
                for path in (out / "packets").rglob("TEXT.txt"):
                    path.write_text("changed")
                return handle
        with self.assertRaisesRegex(ValueError, "during grading"):
            runner.run(out, Change(), Publication(), PROMPTS, self.clock)
        self.assertFalse((out / "BLINDING-SEED.txt").exists())

    def test_empty_wrong_question_view_and_thumbnail_refused(self):
        for doc in ({"kind": "private-key", "questions": []}, {"kind": "grader-questions/2", "questions": []}):
            with self.assertRaises(ValueError): pack.check_questions(doc)
        with self.assertRaisesRegex(ValueError, "thumbnail size"):
            pack.sheet(self.root / "x.png", [(0, b"bad")])

    def test_clock_regression_at_pack_completion(self):
        times = iter([self.clock(), S.BASE])
        with patch.object(pack, "normalise", fixture_normalise):
            with self.assertRaisesRegex(ValueError, "before generation"):
                pack.build(self.runs, self.sources, self.view, b"rubric", S.SEED,
                           self.root / "out", Media(), lambda: next(times))
        self.assertFalse((self.root / "out" / "PRIVATE.json").exists())

    def test_mp4_structural_refusals(self):
        def atom(kind, data): return struct.pack(">I4s", len(data) + 8, kind) + data
        variants = [struct.pack(">I4s", 1, b"moov"), struct.pack(">I4s", 100, b"moov"),
                    atom(b"mvhd", b"short"), atom(b"mvhd", b"\2" + bytes(30)), atom(b"hdlr", b"short"),
                    atom(b"stsd", bytes(8)), atom(b"stsd", bytes(4) + struct.pack(">I", 1)),
                    atom(b"stsd", bytes(4) + struct.pack(">I", 1) + bytes(86))]
        for raw in variants:
            path = self.root / "bad.mp4"; path.write_bytes(raw)
            with self.subTest(raw=raw), self.assertRaises(ValueError): pack.scrub_mp4(path)

class RecordGuardTest(PipelineFixture):
    def test_seed_mapping_check_even_if_hash_updated(self):
        out, doc = self.build()
        path = out / "output-tokens.csv"
        path.write_text(path.read_text().replace(doc["calls"][0]["token"], "0" * 12))
        doc["mappingHashes"][path.name] = pack.digest(path)
        pack.write_json(out / "PRIVATE.json", doc)
        with self.assertRaisesRegex(ValueError, "mappings do not match"): runner.load_pack(out)

    def test_unexpected_shared_state_refused(self):
        out, _ = self.build()
        adapter = unittest.mock.Mock()
        with patch.object(runner.form, "next_step", return_value="fix-up"):
            with self.assertRaisesRegex(ValueError, "unexpected state"):
                runner.run(out, adapter, Publication(), PROMPTS, self.clock)
        adapter.open.assert_not_called()

    def test_reply_is_preserved_if_clock_regresses_on_receive(self):
        out, doc = self.build()
        base = runner.RecordedAdapter(entries(doc))
        clock = self.clock
        class Backwards:
            def open(inner, g, kind, packet, *, session_id):
                handle = base.open(g, kind, packet, session_id=session_id)
                original = handle.reply
                def reply(message):
                    raw = original(message)
                    clock.time -= timedelta(minutes=1)
                    return raw
                handle.reply = reply
                return handle
        with self.assertRaisesRegex(ValueError, "backwards"):
            runner.run(out, Backwards(), Publication(), PROMPTS, clock)
        paths = list((out / "replies").rglob("*.txt"))
        self.assertEqual(len(paths), 1)
        self.assertTrue(paths[0].read_bytes().startswith(b"{"))
        self.assertFalse((out / "BLINDING-SEED.txt").exists())

class DryRunTest(PipelineFixture):
    def test_one_pair_dry_run_cannot_be_a_primary_complete_design(self):
        # Synthetic question only; CLI separately restricts real dry runs to §2.4.
        import random
        rows = list(csv.DictReader(self.runs.read_text().splitlines()))
        rows = [r for r in rows if r["run"] == "1"]
        order = [("Q00", 1, 1), ("Q00", 2, 1)]; random.Random(20261111).shuffle(order)
        rows.sort(key=lambda r: order.index((r["question"], int(r["arm"]), int(r["run"]))))
        for i, row in enumerate(rows):
            row["startedUTC"] = (S.BASE + timedelta(minutes=2*i)).isoformat()
            row["endedUTC"] = (S.BASE + timedelta(minutes=2*i+1)).isoformat()
        with self.runs.open("w", newline="") as f:
            writer = csv.DictWriter(f, rows[0].keys()); writer.writeheader(); writer.writerows(rows)
        sources = {k: v for k, v in self.sources.items() if "-r1-" in k}
        with patch.object(pack, "normalise", fixture_normalise):
            out = pack.build(self.runs, sources, self.view, b"rubric", S.SEED, self.root / "pack", Media(), self.clock, dry_run=True)
        doc = json.loads((out / "PRIVATE.json").read_text())
        self.assertEqual(doc["scope"], "dry-run")
        record = runner.run(out, runner.RecordedAdapter(entries(doc)), Publication(), PROMPTS, self.clock)
        self.assertEqual(len(record["calls"]), 8)
        key = S.score.load_key(S.write_key(self.root, self.key))
        data = S.score.load_input(out, key)
        records = S.score.score_runs(data["runs"], data["record"]["grades"]["score"], key)
        self.assertFalse(S.score.design_status(data, key, records)["complete"])
        with self.assertRaises(ValueError): pack.complete_runs(self.runs, {"Q00": {}})
        with self.assertRaisesRegex(ValueError, "exactly one"):
            pack.complete_runs(self.runs, {"Q00": {}, "Q01": {}}, dry_run=True)
        self.assertEqual(runner.PublicCommitment("main", dry_run=True).results, "benchmark/mechanisms-v1/results/dry-run/")


class DryRunViewTest(unittest.TestCase):
    def test_dry_run_key_gate(self):
        _, view = questions(1)
        with patch.object(pack, "DRY_RUN_QUESTION", "Synthetic dry run"):
            with self.assertRaisesRegex(ValueError, "bicycle question"):
                pack.check_dry_run_view(view)
            view["questions"][0]["question"] = "Synthetic dry run"
            with self.assertRaisesRegex(ValueError, "DRY-BICYCLE"):
                pack.check_dry_run_view(view)
            view["questions"][0]["id"] = "DRY-BICYCLE"
            pack.check_dry_run_view(view)
