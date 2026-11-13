# SPDX-License-Identifier: Apache-2.0
"""Sections 7-9. Private staging, native media IO, deterministic anonymous packets.

The CLI accepts a completed runs.csv and a sources JSON object keyed by output id.
Native IO uses Apple's frameworks; all selection, masking and packet decisions are
here. See PACKING.md for the trust boundary and the proposed rounding/order rules.
"""
import argparse
from contextlib import nullcontext
from contextvars import ContextVar
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import random
import selectors
import re
import shutil
import statistics
import stat
import struct
import subprocess
import sys
import tempfile
import zlib

import blinding
import score

WIDTH, HEIGHT, FPS = 1280, 800, 30
DRY_RUN_QUESTION = "How does a bicycle's chain and sprockets change how hard you pedal?"
# Passed unchanged to Vision's NSRegularExpression; boxes are for the entire match.
PATTERNS = {
    "P1": r"(?i)\bRendered by\b[^\r\n]*",
    "B1": r"(?i)(?<!\w)(?:MartyGraphics|Marty|three\.js|threejs|WebGL|Claude)(?!\w)",
    "F1": r"(?i)(?<!\S)\S+\.(?:json|html)(?=\s|$)",
}


_INPUT_GUARD = ContextVar("pack_input_guard", default=None)


class DryRunInputGuard:
    """Metadata-only refusal for Python IO and explicitly checked native inputs."""

    def __init__(self, bench):
        self.registered = tuple(bench / name for name in ("QUESTIONS.json", "GRADER-QUESTIONS.json"))
        self.opened_paths = set()
        self.opened_inodes = set()
        self.registered_paths = set()
        self.registered_inodes = set()

    def __enter__(self):
        self.token = _INPUT_GUARD.set(self)
        return self

    def __exit__(self, *exc):
        _INPUT_GUARD.reset(self.token)

    def check(self, path, *, opening=False):
        try:
            return self._check(path, opening=opening)
        except (RuntimeError, OSError) as error:
            raise ValueError("cannot safely resolve dry-run input: " + str(path) + ": " + str(error)) from error

    def _check(self, path, *, opening=False):
        for registered in self.registered:
            self.registered_paths.update((registered.absolute(), registered.resolve()))
            try:
                info = registered.stat()
            except FileNotFoundError:
                continue
            self.registered_inodes.add((info.st_dev, info.st_ino))
        if isinstance(path, int):
            resolved, info = None, os.fstat(path)
        else:
            path = Path(os.fsdecode(path))
            resolved = path.resolve()
            if path.absolute() in self.registered_paths or resolved in self.registered_paths:
                raise ValueError("dry-run input must not be a registered question file: " + str(path))
            try:
                info = path.lstat()
                if stat.S_ISLNK(info.st_mode):
                    info = path.stat()
            except FileNotFoundError:
                info = None
        identity = (info.st_dev, info.st_ino) if info is not None else None
        if identity in self.registered_inodes:
            raise ValueError("dry-run input must not be a registered question file: " + str(path))
        if opening:
            self.opened_paths.add(resolved)
            self.opened_inodes.add(identity)
        return info

    def tree(self, path, seen=None):
        info = self.check(path)
        if info is None or not stat.S_ISDIR(info.st_mode):
            return
        seen = set() if seen is None else seen
        identity = (info.st_dev, info.st_ino)
        if identity in seen:
            return
        seen.add(identity)
        with os.scandir(path) as entries:
            for entry in entries:
                self.tree(entry.path, seen)

    def media_inputs(self, request):
        for path in ([request["path"]] if "path" in request else []) + list(request.get("paths", [])):
            self.tree(path)

    def receipt(self):
        if _INPUT_GUARD.get() is not self:
            raise ValueError("dry-run receipt requires an active input guard")
        return bool(self.opened_paths & self.registered_paths or self.opened_inodes & self.registered_inodes)


def guard_input_event(event, arguments):
    guard = _INPUT_GUARD.get()
    if guard is not None:
        if event in ("open", "os.scandir", "os.listdir"):
            guard.check(arguments[0] if arguments[0] is not None else ".", opening=event == "open")
        elif event == "subprocess.Popen":
            guard.tree(arguments[0])


sys.addaudithook(guard_input_event)


def digest(path):
    with open(path, "rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def write_json(path, doc):
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def utc():
    return datetime.now(timezone.utc)


def call_order(seed, grader, calls):
    """A-14 proposal: sorted (kind, anonymous token), then digest-seeded shuffle.

    Guesses are dependent follow-ups, inserted only after a stored preference.
    A grader's primary permutation therefore contains score and preference calls.
    """
    if grader not in score.GRADERS:
        raise ValueError("unknown grader")
    identities = [(c["kind"], c["token"]) for c in calls]
    if len(set(identities)) != len(identities) or any(k not in ("score", "preference") for k, _ in identities):
        raise ValueError("duplicate or unsupported primary call")
    result = sorted(calls, key=lambda c: (c["kind"], c["token"]))
    random.Random(int.from_bytes(blinding._digest(seed, "order:" + grader), "big")).shuffle(result)
    return result


def png(path, rgb, width=WIDTH, height=HEIGHT):
    """New RGB PNG: only IHDR, IDAT, IEND, independent of source metadata."""
    if len(rgb) != width * height * 3:
        raise ValueError("wrong RGB frame size")
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def mask(rgb, observations, padding, width=WIDTH, height=HEIGHT):
    """Top-left pixel boxes, half-open; median per RGB channel on original ring.

    Vision supplies a box for the matched character range, not the whole line.
    Overlapping covers all sample the unmodified image, so OCR order is immaterial.
    """
    if len(rgb) != width * height * 3:
        raise ValueError("wrong RGB frame size")
    covers = []
    for line in observations:
        for match in line["matches"]:
            if match["rule"] not in PATTERNS:
                raise ValueError("unknown mask rule")
            x, y, w, h = match["box"]
            if not all(math.isfinite(v) for v in (x, y, w, h)) or w <= 0 or h <= 0:
                raise ValueError("invalid Vision box")
            x0, y0 = max(0, math.floor(x) - padding), max(0, math.floor(y) - padding)
            x1, y1 = min(width, math.ceil(x + w) + padding), min(height, math.ceil(y + h) + padding)
            if x0 >= x1 or y0 >= y1:
                raise ValueError("Vision box outside frame")
            ring = []
            for yy in range(max(0, y0 - 1), min(height, y1 + 1)):
                for xx in range(max(0, x0 - 1), min(width, x1 + 1)):
                    if xx < x0 or xx >= x1 or yy < y0 or yy >= y1:
                        i = (yy * width + xx) * 3
                        ring.append(rgb[i:i + 3])
            if not ring:
                raise ValueError("mask has no surrounding ring")
            color = bytes(int(statistics.median(p[c] for p in ring)) for c in range(3))
            covers.append((x0, y0, x1, y1, color))
    if not covers:
        return rgb
    out = bytearray(rgb)
    for x0, y0, x1, y1, color in sorted(covers):
        for yy in range(y0, y1):
            out[(yy * width + x0) * 3:(yy * width + x1) * 3] = color * (x1 - x0)
    return bytes(out)


# Fixed bitmap font; labels have no host font or metadata differences.
FONT = dict(zip("0123456789t=. s", [
    "111101101101111", "010110010010111", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111", "010111010010011", "000111000111000",
    "000000000000010", "000000000000000", "011100010001110"]))


def sheet(path, thumbs):
    width, height = 1280, 900  # 160 pixels + 20 pixels for the time, five rows
    canvas = bytearray(b"\xff" * (width * height * 3))
    for cell, (frame, thumb) in enumerate(thumbs):
        if len(thumb) != 256 * 160 * 3:
            raise ValueError("wrong thumbnail size")
        x, y = cell % 5 * 256, cell // 5 * 180
        for row in range(160):
            offset = ((y + row) * width + x) * 3
            canvas[offset:offset + 768] = thumb[row * 768:(row + 1) * 768]
        for pos, char in enumerate("t=%.2f s" % (frame / FPS)):
            for pixel, bit in enumerate(FONT[char]):
                if bit == "1":
                    for dy in (0, 1):
                        for dx in (0, 1):
                            at = ((y + 164 + pixel // 3 * 2 + dy) * width + x + 4 + pos * 8 + pixel % 3 * 2 + dx) * 3
                            canvas[at:at + 3] = b"\0\0\0"
    png(path, canvas, width, height)


def scrub_mp4(path):
    """Erase optional tags and wall-clock dates in place, preserving chunk offsets.

    Native writer supplies one H.264 track and fast-start. Refuse unexpected
    layouts/codecs. Replacing optional atoms by same-sized free atoms avoids
    changing stco/co64 offsets. Only format/codec data remains.
    """
    data = bytearray(path.read_bytes())
    containers = {b"moov", b"trak", b"mdia", b"minf", b"stbl", b"dinf", b"edts"}
    top, codecs, handlers = [], [], []
    def walk(start, end, level=0):
        at = start
        while at < end:
            if end - at < 8:
                raise ValueError("truncated MP4 atom")
            size, kind = struct.unpack_from(">I4s", data, at)
            header = 8
            if size == 1:
                if end - at < 16:
                    raise ValueError("truncated extended MP4 atom")
                size = struct.unpack_from(">Q", data, at + 8)[0]
                header = 16
            if size == 0:
                size = end - at
            if size < header or at + size > end:
                raise ValueError("invalid MP4 atom length")
            body, stop = at + header, at + size
            if level == 0:
                top.append(kind)
            if kind in (b"udta", b"meta", b"free", b"skip", b"wide", b"uuid"):
                data[at+4:at+8] = b"free"
                data[body:stop] = bytes(stop - body)
            elif kind in (b"mvhd", b"tkhd", b"mdhd"):
                if stop - body < 20 or data[body] not in (0, 1):
                    raise ValueError("invalid MP4 timestamp header")
                length = 16 if data[body] == 1 else 8
                data[body+4:body+4+length] = bytes(length)
            elif kind == b"hdlr":
                if stop - body < 24:
                    raise ValueError("invalid MP4 handler")
                handlers.append(bytes(data[body+8:body+12]))
                data[body+24:stop] = bytes(stop - body - 24)
            elif kind == b"stsd":
                if stop - body < 8 or struct.unpack_from(">I", data, body+4)[0] != 1:
                    raise ValueError("MP4 must have one sample description")
                entry = body + 8
                if stop - entry < 86:
                    raise ValueError("truncated video sample entry")
                entry_size, codec = struct.unpack_from(">I4s", data, entry)
                if entry_size != stop - entry:
                    raise ValueError("invalid video sample length")
                codecs.append(codec)
                # ISO VisualSampleEntry compressorname (length byte + 31 bytes).
                data[entry+50:entry+82] = bytes(32)
            elif kind in containers:
                walk(body, stop, level + 1)
            at = stop
    walk(0, len(data))
    if top.count(b"moov") != 1 or b"mdat" not in top or top.index(b"moov") > top.index(b"mdat"):
        raise ValueError("MP4 is not fast-start")
    if codecs != [b"avc1"] or handlers != [b"vide"]:
        raise ValueError("MP4 must be H.264 video only")
    path.write_bytes(data)


class AppleMedia:
    """Persistent native NDJSON worker; no third-party Python dependency.

    Each request has a timeout. Native errors stop packing; no alternative
    OCR/codec or blank-frame substitution is used. Call close() on completion.
    """
    def __init__(self, executable):
        self.executable = str(Path(executable).resolve())
        self.process = None

    def invoke(self, **request):
        guard = _INPUT_GUARD.get()
        if guard is not None:
            guard.tree(self.executable)
            guard.media_inputs(request)
        if self.process is None:
            self.process = subprocess.Popen([self.executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=subprocess.DEVNULL)
        self.process.stdin.write((json.dumps(request) + "\n").encode())
        self.process.stdin.flush()
        # Byte-at-a-time reads would be costly; unbuffered os.read plus a selector
        # bounds the entire response, including a truncated native JSON line.
        import time
        deadline, response = time.monotonic() + 600, bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(self.process.stdout, selectors.EVENT_READ)
            while not response.endswith(b"\n"):
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    self.close()
                    raise ValueError("native media request timed out")
                data = os.read(self.process.stdout.fileno(), 65536)
                if not data:
                    raise ValueError("native media worker stopped")
                response.extend(data)
        result = json.loads(response)
        if "error" in result:
            raise ValueError("native media: " + result["error"])
        return result

    def close(self):
        if self.process is not None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
            self.process.stdout.close()
            self.process = None

    def prepare(self, source, arm, work):
        if source["kind"] != ("video" if arm == 1 else "captures"):
            raise ValueError("Arm 1 needs video; Arm 2 needs original PNG captures")
        request = dict(source)
        request.update(op="prepare", output=str(work))
        return self.invoke(**request)["frames"]

    def ocr(self, path):
        return self.invoke(op="ocr", path=str(path), patterns=PATTERNS)["lines"]

    def thumbnail(self, path):
        result = self.invoke(op="thumbnail", path=str(path))
        import base64
        return base64.b64decode(result["rgb"], validate=True)

    def video(self, paths, path):
        self.invoke(op="encode", paths=[str(p) for p in paths], output=str(path), raw=True)
        scrub_mp4(path)


def normalise(frames, target, destination, media):
    """frames: original decoded 30 fps paths; target: paired length in frames."""
    count = len(frames)
    if count < 1 or not max(300, min(1800, count)) <= target <= 1800:
        raise ValueError("invalid source or paired length")
    length = max(300, min(1800, count))
    destination.mkdir()
    (destination / "sheets").mkdir()
    residual, transcript, previous, thumbs, masked_paths = [], [], None, [], []
    stills = {int(length * f / 10): i for i, f in enumerate((1, 3, 5, 7, 9), 1)}
    last_rgb, last_path, last_thumb = None, None, None
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        for k in range(target):
            original = Path(frames[min(k, count - 1)])
            rgb = original.read_bytes()
            first = mask(rgb, media.ocr(original), 3)
            if first == last_rgb:
                current = last_path
            else:
                current = Path(temp) / ("%04d.rgb" % k)
                current.write_bytes(first)
                last_rgb, last_path, last_thumb = first, current, None
            masked_paths.append(current)
            if k in stills:
                still = Path(temp) / "still.rgb"
                still.write_bytes(mask(first, media.ocr(current), 6))
                remaining = media.ocr(still)
                residual += [{"still": stills[k], "matches": line["matches"]} for line in remaining if line["matches"]]
                png(destination / ("still-%d.png" % stills[k]), still.read_bytes())
            if k % 15 == 0:
                for line in media.ocr(current):
                    text = line["text"]
                    if text and text != previous:
                        transcript.append(text)
                    previous = text
            if k % 3 == 0:
                if last_thumb is None:
                    last_thumb = media.thumbnail(current)
                thumbs.append((k, last_thumb))
                if len(thumbs) == 25 or k + 3 >= target:
                    sheet(destination / "sheets" / ("sheet-%02d.png" % ((k // 3) // 25 + 1)), thumbs)
                    thumbs = []
        media.video(masked_paths, destination / "video.mp4")
    (destination / "TEXT.txt").write_text("\n".join(transcript) + ("\n" if transcript else ""), encoding="utf-8")
    return {"sourceFrames": count, "LFrames": length, "TFrames": target, "cut": count > 1800,
            "heldFrames": target - min(count, 1800), "residualMatches": residual}


def check_questions(doc):
    allowed = {"id", "question", "conventional", "acceptedVariants", "keyFacts", "mechanismChecks"}
    if doc.get("kind") != "grader-questions/2":
        raise ValueError("only the grader question view is allowed")
    questions = {}
    for q in doc["questions"]:
        if set(q) != allowed or not re.fullmatch(r"[A-Za-z0-9-]+", q["id"]) or q["id"] in questions:
            raise ValueError("invalid or duplicate grader question")
        for fact in q["keyFacts"]:
            if set(fact) != {"id", "fact", "core", "appliesTo", "acceptedWordings"}:
                raise ValueError("private or missing fact fields")
        for check in q["mechanismChecks"]:
            if set(check) != {"id", "kind", "pass"}:
                raise ValueError("private or missing check fields")
        questions[q["id"]] = q
    if not questions:
        raise ValueError("empty design")
    return questions


def check_dry_run_view(view):
    questions = check_questions(view)
    if len(questions) != 1 or next(iter(questions.values()))["question"] != DRY_RUN_QUESTION:
        raise ValueError("dry-run key must contain only the section 2.4 bicycle question")
    # Dedicated dry namespace; see A-19 for the non-blinded ID record/trade-off.
    if set(questions) != {"DRY-BICYCLE"}:
        raise ValueError("dry-run question id must be DRY-BICYCLE")


def complete_runs(path, questions, dry_run=False):
    runs = score.read_runs(path, questions)
    if dry_run and len(questions) != 1:
        raise ValueError("dry run needs exactly one question")
    expected = sorted((q, a, r) for q in questions for a in (1, 2) for r in ((1,) if dry_run else (1, 2, 3)))
    random.Random(20261111).shuffle(expected)
    ordered = sorted(runs.values(), key=lambda r: r["started"])
    if [r["id"] for r in ordered] != [score.slot_id(*s) for s in expected]:
        raise ValueError("incomplete design or wrong generation order")
    for i, run in enumerate(ordered):
        if run["ended"] < run["started"] or (run["status"] == "rendered" and run["wallSeconds"] > 3600):
            raise ValueError("invalid run timing")
        if i and (run["started"] <= ordered[i-1]["started"] or run["started"] < ordered[i-1]["ended"]):
            raise ValueError("overlapping generation")
    return runs


def tree_hashes(path):
    entries = list(path.rglob("*"))
    if any(p.is_symlink() for p in entries):
        raise ValueError("symlink in packet tree")
    return {p.relative_to(path).as_posix(): digest(p) for p in sorted(entries) if p.is_file()}


def build(runs_path, sources, question_doc, rubric, seed, destination, media, clock=utc, *, dry_run=False):
    guard = _INPUT_GUARD.get()
    if dry_run and guard is None:
        with DryRunInputGuard(Path(__file__).resolve().parent.parent):
            return build(runs_path, sources, question_doc, rubric, seed, destination, media, clock, dry_run=True)
    if guard is not None:
        guard.tree(runs_path)
        for source in sources.values():
            guard.media_inputs(source)
    questions = check_questions(question_doc)
    runs = complete_runs(runs_path, questions, dry_run)
    rendered = {sid: r for sid, r in runs.items() if r["status"] == "rendered"}
    if set(sources) != set(rendered):
        raise ValueError("sources must equal the rendered outputs")
    if seed is not None and len(seed) != 32:
        raise ValueError("seed must be 32 bytes")
    if clock() < max(r["ended"] for r in runs.values()):
        raise ValueError("packing before generation ends")
    destination = Path(destination)
    destination.mkdir()  # never overwrite a partial or completed pack
    (destination / "packets").mkdir()
    (destination / "artifacts").mkdir()
    (destination / "originals").mkdir()
    shutil.copyfile(runs_path, destination / "runs.csv")
    calls, tokens, sides, reports, seen = [], [], [], {}, set()
    def packet(kind, cid, q, token, folders):
        if token in seen:
            raise ValueError("anonymous token collision")
        seen.add(token)
        out = destination / "packets" / token
        out.mkdir()
        write_json(out / "question.json", questions[q])
        (out / "RUBRIC.md").write_bytes(rubric)
        for label, sid in folders.items():
            shutil.copytree(destination / "artifacts" / sid, out / label,
                            ignore=shutil.ignore_patterns("video.mp4"))
        calls.append({"kind": kind, "id": cid, "question": q, "token": token})
    for q in sorted(questions):
        for r in ((1,) if dry_run else (1, 2, 3)):
            pair = [runs[score.slot_id(q, a, r)] for a in (1, 2)]
            with tempfile.TemporaryDirectory(dir=destination) as temp:
                decoded = {}
                for run in pair:
                    if run["status"] == "rendered":
                        work = Path(temp) / str(run["arm"])
                        work.mkdir()
                        decoded[run["id"]] = media.prepare(sources[run["id"]], run["arm"], work)
                        if guard is not None:
                            for frame in decoded[run["id"]]:
                                guard.tree(frame)
                            guard.tree(work / "intermediate.mp4")
                        if (work / "intermediate.mp4").exists():
                            original = destination / "originals" / run["id"]
                            original.mkdir()
                            shutil.copyfile(work / "intermediate.mp4", original / "intermediate.mp4")
                if any(not frames for frames in decoded.values()):
                    raise ValueError("empty rendered source")
                target = max((max(300, min(1800, len(f))) for f in decoded.values()), default=0)
                for run in pair:
                    sid = run["id"]
                    if sid in decoded:
                        reports[sid] = normalise(decoded[sid], target, destination / "artifacts" / sid, media)
    # All outputs are normalized before a new OS seed is made or any label is assigned.
    # Explicit seeds support deterministic replay and synthetic tests only.
    if seed is None:
        seed = os.urandom(32)
    (destination / "BLINDING-COMMITMENT.txt").write_text(blinding.commitment(seed) + "\n", encoding="ascii")
    for sid, run in sorted(rendered.items()):
        q, r = run["question"], run["run"]
        token = blinding.output_token(seed, q, r, run["arm"])
        tokens.append((sid, token))
        packet("score", sid, q, token, {"output": sid})
    for q in sorted(questions):
        for r in ((1,) if dry_run else (1, 2, 3)):
            if score.both_rendered(runs, q, r):
                token, arm_a = blinding.pair_token(seed, q, r), blinding.arm_shown_as_a(seed, q, r)
                pid = score.pair_id(q, r)
                sides.append((pid, token, arm_a))
                packet("preference", pid, q, token,
                       {"A": score.slot_id(q, arm_a, r), "B": score.slot_id(q, 3 - arm_a, r)})
    for name, header, rows in (("output-tokens.csv", ("output", "token"), tokens),
                               ("pair-sides.csv", ("pair", "token", "A"), sides)):
        with (destination / name).open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(header)
            writer.writerows(sorted(rows))
    finished = clock()
    if finished < max(r["ended"] for r in runs.values()):
        raise ValueError("packing before generation ends")
    # Private until the grading completes. This file is never copied to a session.
    write_json(destination / "PRIVATE.json", {"kind": "mechanisms-v1.pack/1", "scope": "dry-run" if dry_run else "primary", "seed": seed.hex(),
        "packedUTC": finished.isoformat(), "questions": question_doc, "calls": calls,
        "orders": {g: [c["token"] for c in call_order(seed, g, calls)] for g in score.GRADERS},
        "reports": reports, "packetHashes": tree_hashes(destination / "packets"),
        "runsSha256": digest(destination / "runs.csv"),
        "mappingHashes": {p: digest(destination / p) for p in ("output-tokens.csv", "pair-sides.csv")},
        **({"registeredQuestionFilesRead": guard.receipt()} if dry_run else {})})
    return destination


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", type=Path)
    parser.add_argument("sources", type=Path)
    parser.add_argument("--seed", type=Path, help="existing private seed for deterministic replay only; default: new OS seed after normalization")
    parser.add_argument("--native", type=Path, required=True, help="compiled native/media.swift")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--dry-run-questions", type=Path, help="reviewed grader-view key for the registered bicycle dry run only")
    args = parser.parse_args(argv)
    bench = Path(__file__).resolve().parent.parent
    media = None
    try:
        with DryRunInputGuard(bench) if args.dry_run_questions else nullcontext() as guard:
            if guard is not None:
                for path in (bench / "LOCK.json", bench / "RUBRIC.md", args.runs, args.sources,
                             args.seed, args.native, args.dry_run_questions):
                    if path is not None:
                        guard.tree(path)
            lock = json.loads((bench / "LOCK.json").read_text())
            inputs = ("RUBRIC.md",) if args.dry_run_questions else ("GRADER-QUESTIONS.json", "RUBRIC.md")
            for name in inputs:
                if digest(bench / name) != lock["inputs"][name]:
                    parser.error("registered input hash mismatch: " + name)
            media = AppleMedia(args.native)
            view = json.loads((args.dry_run_questions or (bench / "GRADER-QUESTIONS.json")).read_text())
            if args.dry_run_questions:
                check_dry_run_view(view)
            build(args.runs, json.loads(args.sources.read_text()), view,
                  (bench / "RUBRIC.md").read_bytes(), blinding.parse_seed(args.seed.read_text()) if args.seed else None, args.out, media, dry_run=bool(args.dry_run_questions))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(2, str(error) + "\n")
    finally:
        if media is not None:
            media.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
