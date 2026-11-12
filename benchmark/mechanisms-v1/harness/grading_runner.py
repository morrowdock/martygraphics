# SPDX-License-Identifier: Apache-2.0
"""Offline-capable section 6 session driver. Ships ONLY RecordedAdapter.

An adapter sees an anonymous packet, the locked prompt and its own session handle.
It never receives the seed, mapping, run id, other replies or operator directory.
Production model adapters are deliberately not included. See PACKING.md.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Protocol

import blinding
import pack
import rubric_form as form
import score


class Session(Protocol):
    def reply(self, message: str) -> bytes: ...
    def close(self) -> None: ...


class Adapter(Protocol):
    def open(self, grader: str, kind: str, packet: Path) -> Session:
        """Fresh isolated session. No previous conversation, network, or other files."""
        ...


class RecordedAdapter:
    """Replay bytes only, in requested order. No processes, models or network.

    Entries are {grader, kind, token, replies: [text, ...]}. Each entry is one
    session; a second reply is read only when the validator asks for a fix-up.
    """
    def __init__(self, entries):
        self.entries = iter(entries)
        self.messages = []

    def open(self, grader, kind, packet):
        entry = next(self.entries)
        if (entry["grader"], entry["kind"]) != (grader, kind):
            raise ValueError("recorded session does not match requested grader and kind")
        replies = iter(entry["replies"])
        messages = self.messages
        class Replay:
            def reply(self, message):
                if not messages or not message.startswith("The reply is invalid"):
                    if kind != "guess" and entry["token"] not in message:
                        raise ValueError("recorded session token mismatch")
                messages.append(message)
                value = next(replies)
                return value if isinstance(value, bytes) else value.encode("utf-8")
            def close(self):
                pass
        return Replay()


class PublicCommitment:
    """Observe the actual public branch, never accept an operator push-time flag.

    Read-only HTTPS fetch into a fresh bare repo. The time after the fetch is a
    conservative upper bound for publication; every session starts later.
    No push, auth helper, model call or API key is used.
    """
    def __init__(self, branch, *, dry_run=False):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_/-]*", branch) or ".." in branch or "//" in branch:
            raise ValueError("invalid public branch")
        self.branch = branch
        self.results = "benchmark/mechanisms-v1/results/" + ("dry-run/" if dry_run else "")

    def verify(self, commitment, not_before, clock):
        with tempfile.TemporaryDirectory() as temp:
            env = {"PATH": os.defpath, "HOME": temp, "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0"}
            def git(*args):
                return subprocess.run(["git", "-C", temp, *args], env=env, check=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120).stdout
            git("init", "--bare", "-q")
            git("-c", "credential.helper=", "fetch", "--depth=1", "--no-tags",
                "https://github.com/morrowdock/martygraphics.git", "refs/heads/" + self.branch)
            path = self.results + "BLINDING-COMMITMENT.txt"
            if git("show", "FETCH_HEAD:" + path).decode("ascii").strip() != commitment:
                raise ValueError("public commitment does not match the packed seed")
            names = git("ls-tree", "-r", "--name-only", "FETCH_HEAD").decode().splitlines()
            if any(p in {self.results + name for name in ("BLINDING-SEED.txt", "PRIVATE.json", "output-tokens.csv", "pair-sides.csv")}
                   for p in names):
                raise ValueError("seed or arm mapping is public before grading")
            observed = clock()
            if observed < not_before:
                raise ValueError("publication observation predates packing or generation")
            return {"observedUTC": observed.isoformat(), "commit": git("rev-parse", "FETCH_HEAD").decode().strip(),
                    "branch": self.branch, "path": path, "commitment": commitment}


def durable_json(path, doc):
    """Atomic replace plus fsync file and directory, before any dependent call."""
    temporary = path.with_suffix(".tmp")
    with temporary.open("x", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(temporary, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def load_pack(root):
    doc = json.loads((root / "PRIVATE.json").read_text(encoding="utf-8"))
    if doc.get("kind") != "mechanisms-v1.pack/1":
        raise ValueError("not a completed pack")
    seed = blinding.parse_seed(doc["seed"])
    if (root / "BLINDING-COMMITMENT.txt").read_text().strip() != blinding.commitment(seed):
        raise ValueError("commitment mismatch")
    if (root / "BLINDING-SEED.txt").exists():
        raise ValueError("seed already released; cannot grade again")
    questions = pack.check_questions(doc["questions"])
    if doc.get("scope") not in ("primary", "dry-run"):
        raise ValueError("pack scope must be primary or dry-run")
    runs = pack.complete_runs(root / "runs.csv", questions, dry_run=doc["scope"] == "dry-run")
    if pack.digest(root / "runs.csv") != doc["runsSha256"] or any(
            pack.digest(root / p) != h for p, h in doc["mappingHashes"].items()):
        raise ValueError("run table or mappings changed after packing")
    # Reconstruct identities instead of trusting private call labels or ordering.
    calls = []
    for run in runs.values():
        q, r, a = run["question"], run["run"], run["arm"]
        if run["status"] == "rendered":
            calls.append({"kind": "score", "id": run["id"], "question": q,
                          "token": blinding.output_token(seed, q, r, a)})
        if a == 1 and score.both_rendered(runs, q, r):
            calls.append({"kind": "preference", "id": score.pair_id(q, r), "question": q,
                          "token": blinding.pair_token(seed, q, r)})
    sort = lambda rows: sorted(rows, key=lambda c: (c["kind"], c["id"]))
    if sort(doc["calls"]) != sort(calls):
        raise ValueError("call set does not match rendered design")
    output_rows = score.read_csv(root / "output-tokens.csv", ["output", "token"])
    expected_outputs = [{"output": c["id"], "token": c["token"]} for c in calls if c["kind"] == "score"]
    pair_rows = score.read_csv(root / "pair-sides.csv", ["pair", "token", "A"])
    expected_pairs = [{"pair": c["id"], "token": c["token"],
                       "A": str(blinding.arm_shown_as_a(seed, c["question"], int(c["id"].rpartition("-r")[2])))}
                      for c in calls if c["kind"] == "preference"]
    if sorted(output_rows, key=lambda r: r["output"]) != sorted(expected_outputs, key=lambda r: r["output"]) or \
       sorted(pair_rows, key=lambda r: r["pair"]) != sorted(expected_pairs, key=lambda r: r["pair"]):
        raise ValueError("published mappings do not match seed and design")
    if doc["orders"] != {g: [c["token"] for c in pack.call_order(seed, g, calls)] for g in score.GRADERS}:
        raise ValueError("call permutation mismatch")
    if pack.tree_hashes(root / "packets") != doc["packetHashes"]:
        raise ValueError("packet tree changed after packing")
    # An allowlist prevents manifest edits from admitting additional evidence.
    expected_files = set()
    for call in calls:
        token = call["token"]
        folder = root / "packets" / token
        if json.loads((folder / "question.json").read_text()) != questions[call["question"]]:
            raise ValueError("question changed in packet")
        expected_files.update(token + "/" + f for f in ("question.json", "RUBRIC.md"))
        for label in (("output",) if call["kind"] == "score" else ("A", "B")):
            sheets = sorted((folder / label / "sheets").glob("*.png"))
            if not 4 <= len(sheets) <= 24 or [p.name for p in sheets] != ["sheet-%02d.png" % i for i in range(1, len(sheets) + 1)]:
                raise ValueError("invalid sheet sequence")
            names = ["TEXT.txt"] + ["still-%d.png" % i for i in range(1, 6)]
            expected_files.update(token + "/" + label + "/" + n for n in names)
            expected_files.update(token + "/" + label + "/sheets/" + p.name for p in sheets)
    if set(doc["packetHashes"]) != expected_files:
        raise ValueError("packet contains missing or extra files")
    packed = score.parse_time(doc["packedUTC"], "packedUTC")
    if packed < max(r["ended"] for r in runs.values()):
        raise ValueError("pack predates generation")
    return doc, seed, questions, calls, packed


def run(root, adapter, publication, prompts, clock=pack.utc):
    """Single-use run. Fail closed on IO, adapter or clock errors; never auto-rerun.

    A crash leaves RECORD.json incomplete for audit. Restart is refused because a
    session may already have received a prompt. Recovery requires separate review.
    """
    root = Path(root).resolve()
    doc, seed, questions, calls, packed = load_pack(root)
    if set(prompts) != {"score", "preference", "guess"}:
        raise ValueError("all three prompts are required")
    if (root / "RECORD.json").exists() or (root / "RUNNER-STARTED").exists():
        raise ValueError("grading already started; no automatic resume or rerun")
    # Exclusive claim is retained on failures, including a failed publication check.
    with (root / "RUNNER-STARTED").open("x") as f:
        f.write("single-use grading claim\n")
    proof = publication.verify(blinding.commitment(seed), packed, clock)
    pushed = score.parse_time(proof["observedUTC"], "publication observation")
    if pushed < packed or proof["commitment"] != blinding.commitment(seed):
        raise ValueError("invalid publication proof")
    durable_json(root / "PUBLICATION.json", proof)
    record = {"kind": "mechanisms-v1.record/1", "commitmentPushedUTC": pushed.isoformat(),
              "withdrawnModels": [], "humanGraders": [], "calls": []}
    durable_json(root / "RECORD.json", record)
    previous = pushed
    def tick():
        nonlocal previous
        now = clock()
        if now.tzinfo is None or now < previous:
            raise ValueError("clock moved backwards or has no timezone")
        previous = now
        return now.isoformat()

    def drive(grader, call, kind):
        entry = {"grader": grader, "kind": kind, "id": call["id"], "sessions": []}
        record["calls"].append(entry)
        validity, problems = [], []
        while True:
            step = form.next_step(validity)
            if step in ("accept", "missing"):
                return step
            if step != "new-session":
                raise ValueError("unexpected state before opening session")
            # Only packet bytes enter this new directory; no symlinks, seed or grades.
            with tempfile.TemporaryDirectory(prefix="grader-") as temp:
                packet = Path(temp) / "packet"
                source = root / "packets" / call["token"]
                expected = {p.removeprefix(call["token"] + "/"): h for p, h in doc["packetHashes"].items()
                            if p.startswith(call["token"] + "/")}
                if pack.tree_hashes(source) != expected:
                    raise ValueError("packet changed during grading")
                shutil.copytree(source, packet)
                for p in packet.rglob("*"):
                    if p.is_file():
                        p.chmod(0o444)
                        os.utime(p, (0, 0))
                for p in [packet] + [p for p in packet.rglob("*") if p.is_dir()]:
                    os.utime(p, (0, 0))
                session = {"startedUTC": tick(), "replies": []}
                entry["sessions"].append(session)
                # Persist start BEFORE adapter.open (which might itself start a model).
                durable_json(root / "RECORD.json", record)
                handle = adapter.open(grader, kind, packet)
                validity.append([])
                try:
                    message = prompts[kind].replace("{token}", call["token"])
                    while True:
                        raw = handle.reply(message)
                        if not isinstance(raw, bytes):
                            raise ValueError("adapter must return exact reply bytes")
                        relative = Path("replies") / grader / kind / call["id"] / ("%d-%d.txt" % (
                            len(validity), len(validity[-1]) + 1))
                        path = root / relative
                        path.parent.mkdir(parents=True, exist_ok=True)
                        with path.open("xb") as f:
                            f.write(raw); f.flush(); os.fsync(f.fileno())
                        for parent in path.parents:
                            if not parent.is_relative_to(root):
                                break
                            directory = os.open(parent, os.O_RDONLY)
                            try:
                                os.fsync(directory)
                            finally:
                                os.close(directory)
                        # A clock failure still leaves the exact raw reply for audit.
                        received = tick()
                        session["replies"].append({"file": relative.as_posix(), "receivedUTC": received})
                        # The exact raw reply AND its record are durable before acceptance.
                        durable_json(root / "RECORD.json", record)
                        _, problems = form.check_text(kind, raw, questions[call["question"]], call["token"])
                        validity[-1].append(not problems)
                        step = form.next_step(validity)  # every reply goes through the shared state machine
                        if step != "fix-up":
                            break
                        message = "The reply is invalid:\n" + "\n".join(problems)
                finally:
                    handle.close()

    for grader in score.GRADERS:
        for call in pack.call_order(seed, grader, calls):
            state = drive(grader, call, call["kind"])
            # No public 'guess' entry point. Accepted preference has been fsynced.
            if call["kind"] == "preference" and state == "accept":
                drive(grader, call, "guess")
    # Reveal locally only after every required call completed or exhausted.
    with (root / "BLINDING-SEED.txt").open("x", encoding="ascii") as f:
        f.write(seed.hex() + "\n"); f.flush(); os.fsync(f.fileno())
    return record


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    parser.add_argument("--recorded", type=Path, required=True, help="offline reply sessions; no live adapter is shipped")
    parser.add_argument("--public-branch", required=True, help="read-only public commitment verification")
    args = parser.parse_args(argv)
    bench = Path(__file__).resolve().parent.parent
    lock = json.loads((bench / "LOCK.json").read_text())
    prompts = {}
    for kind in ("score", "preference", "guess"):
        name = "GRADER-" + kind.upper() + ".txt"
        path = bench / "prompts" / name
        if pack.digest(path) != lock["graders"]["prompts"][name]["sha256"]:
            parser.error("registered prompt hash mismatch")
        prompts[kind] = path.read_text(encoding="utf-8")
    try:
        doc, _, _, _, _ = load_pack(args.pack)
        run(args.pack, RecordedAdapter(json.loads(args.recorded.read_text())),
            PublicCommitment(args.public_branch, dry_run=doc["scope"] == "dry-run"), prompts)
    except (ValueError, OSError, subprocess.SubprocessError, StopIteration) as error:
        parser.exit(2, str(error) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
