# SPDX-License-Identifier: Apache-2.0
"""Offline-capable section 6 session driver. Ships ONLY RecordedAdapter.

An adapter sees an anonymous packet, the locked prompt and its own session handle.
It never receives the seed, mapping, run id, other replies or operator directory.
Production model adapters are deliberately not included. See PACKING.md.
"""
import argparse
import fcntl
import hashlib
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
    def open(self, grader: str, kind: str, packet: Path, *, session_id: str) -> Session:
        """Open and durably bind a fresh isolated session to this opaque id."""
        ...

    def resume(self, grader: str, kind: str, packet: Path, *, session_id: str,
               received: int) -> Session:
        """Reattach the SAME session; never resend prompts or create a replacement.

        received is the number of durable replies. Fail if the adapter cannot
        establish this exact conversation and reply count. No model call here.
        """
        ...


def session_key(grader, kind, token, number):
    return hashlib.sha256(f"{grader}:{kind}:{token}:{number}".encode()).hexdigest()


class RecordedAdapter:
    """Offline replay indexed by opaque session id, including process restarts.

    Entries are {grader, kind, token, replies: [text, ...]}. Supply the same full
    file on resume. No processes, models or network; resume skips durable replies.
    """
    def __init__(self, entries):
        self.entries = {}
        self.messages = []
        counts = {}
        for entry in entries:
            key = entry["grader"], entry["kind"], entry["token"]
            counts[key] = counts.get(key, 0) + 1
            self.entries[session_key(*key, counts[key])] = entry

    def open(self, grader, kind, packet, *, session_id):
        return self.resume(grader, kind, packet, session_id=session_id, received=0)

    def resume(self, grader, kind, packet, *, session_id, received):
        entry = self.entries[session_id]
        if (entry["grader"], entry["kind"]) != (grader, kind):
            raise ValueError("recorded session does not match requested grader and kind")
        replies = iter(entry["replies"][received:])
        messages = self.messages
        class Replay:
            def reply(self, message):
                if not message.startswith("The reply is invalid"):
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


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def durable_bytes(path, raw):
    """Atomic replace plus fsync. Abandoned temp files cannot block recovery."""
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(raw)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def json_bytes(doc):
    return (json.dumps(doc, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def durable_json(path, doc):
    durable_bytes(path, json_bytes(doc))


def load_pack(root, *, allow_released=False):
    doc = json.loads((root / "PRIVATE.json").read_text(encoding="utf-8"))
    if doc.get("kind") != "mechanisms-v1.pack/1":
        raise ValueError("not a completed pack")
    seed = blinding.parse_seed(doc["seed"])
    if (root / "BLINDING-COMMITMENT.txt").read_text().strip() != blinding.commitment(seed):
        raise ValueError("commitment mismatch")
    if (root / "BLINDING-SEED.txt").exists() and not allow_released:
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


def run(root, adapter, publication, prompts, clock=pack.utc, *, _checkpoint=lambda stage: None):
    """Resume durable attempts; stop on uncertain adapter calls, never resend them.

    RUNNER-STATE.json is the write-ahead state; RECORD.json remains the scoring
    format. A receipt atomically binds exact reply bytes to their receivedUTC.
    The private checkpoint hook is only for synthetic interruption tests.
    """
    root = Path(root).resolve()
    doc, seed, questions, calls, packed = load_pack(root, allow_released=True)
    if set(prompts) != {"score", "preference", "guess"}:
        raise ValueError("all three prompts are required")
    claim = root / "RUNNER-STARTED"
    proof_path = root / "PUBLICATION.json"
    # Failed verification creates no claim. A stored proof is reused, never
    # replaced with a later observation that would postdate existing attempts.
    if claim.exists() and proof_path.exists():
        proof = json.loads(proof_path.read_text())
    else:
        proof = publication.verify(blinding.commitment(seed), packed, clock)
    pushed = score.parse_time(proof["observedUTC"], "publication observation")
    if pushed < packed or proof["commitment"] != blinding.commitment(seed):
        raise ValueError("invalid publication proof")
    _checkpoint("before-claim")
    # flock releases on process death; the durable claim is not a stale mutex.
    with claim.open("a+b") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("grading is active in another process") from error
        # Re-read under the lock in case another starter has just finished.
        if proof_path.exists():
            proof = json.loads(proof_path.read_text())
            pushed = score.parse_time(proof["observedUTC"], "publication observation")
            if pushed < packed or proof["commitment"] != blinding.commitment(seed):
                raise ValueError("invalid publication proof")
        else:
            durable_json(proof_path, proof)
        sync_directory(root)
        _checkpoint("after-claim")
        return _run_locked(root, adapter, prompts, clock, doc, seed, questions,
                           calls, pushed, _checkpoint)


def _run_locked(root, adapter, prompts, clock, doc, seed, questions, calls, pushed, checkpoint):
    state_path = root / "RUNNER-STATE.json"
    record_path = root / "RECORD.json"
    binding = {"pack": pack.digest(root / "PRIVATE.json"),
               "prompts": hashlib.sha256(json_bytes(prompts)).hexdigest(),
               "publication": pack.digest(root / "PUBLICATION.json")}
    if state_path.exists():
        state = json.loads(state_path.read_text())
        if state["binding"] != binding:
            raise ValueError("pack, prompts or publication changed across resume")
    else:
        if record_path.exists() or (root / "replies").exists() or (root / "BLINDING-SEED.txt").exists():
            raise ValueError("legacy or unjournaled grading requires operator recovery")
        state = {"binding": binding, "record": {
            "kind": "mechanisms-v1.record/1", "commitmentPushedUTC": pushed.isoformat(),
            "withdrawnModels": [], "humanGraders": [], "calls": []},
            "active": None, "completed": False, "previousRecordHash": None}
        durable_json(state_path, state)
    record = state["record"]
    if record["commitmentPushedUTC"] != pushed.isoformat():
        raise ValueError("record publication time differs from proof")

    def mirror():
        expected = hashlib.sha256(json_bytes(record)).hexdigest()
        if record_path.exists() and pack.digest(record_path) not in (expected, state["previousRecordHash"]):
            raise ValueError("RECORD.json differs from journal; operator recovery required")
        durable_json(record_path, record)

    def save():
        state["previousRecordHash"] = pack.digest(record_path) if record_path.exists() else None
        durable_json(state_path, state)
        mirror()

    mirror()
    previous = pushed
    # Check all restored times, including accepted preferences, before any call.
    for entry in record["calls"]:
        for session in entry["sessions"]:
            for stamp in [session["startedUTC"]] + [r["receivedUTC"] for r in session["replies"]]:
                now = score.parse_time(stamp, "restored grading timestamp")
                if now < previous:
                    raise ValueError("restored grading clock moved backwards")
                previous = now

    def tick():
        nonlocal previous
        now = clock()
        if now.tzinfo is None or now < previous:
            raise ValueError("clock moved backwards or has no timezone")
        previous = now
        return now.isoformat()

    def check_clock():
        nonlocal previous
        now = clock()
        if now.tzinfo is None or now < previous:
            raise ValueError("clock moved backwards or has no timezone")
        previous = now

    def reconcile():
        nonlocal previous
        active = state["active"]
        if active is None or active["phase"] != "sending":
            return
        receipt_path = root / active["file"].replace(".txt", ".receipt.json")
        if not receipt_path.exists():
            raise ValueError("uncertain request without durable reply; operator recovery required")
        receipt = json.loads(receipt_path.read_text())
        if receipt["sessionId"] != active["sessionId"] or receipt["file"] != active["file"]:
            raise ValueError("reply receipt identity mismatch; operator recovery required")
        raw = bytes.fromhex(receipt["rawHex"])
        received = score.parse_time(receipt["receivedUTC"], "reply receipt")
        if received < previous:
            raise ValueError("reply receipt predates session or stored preference")
        path = root / active["file"]
        if path.exists() and path.read_bytes() != raw:
            raise ValueError("saved reply differs from receipt; operator recovery required")
        durable_bytes(path, raw)
        checkpoint("after-reply-file")
        session = record["calls"][active["call"]]["sessions"][-1]
        session["replies"].append({"file": active["file"], "receivedUTC": receipt["receivedUTC"]})
        previous = received
        active["phase"] = "ready"
        save()

    reconcile()
    if state["active"] and state["active"]["phase"] == "opening":
        raise ValueError("uncertain session open; operator recovery required")
    if (root / "BLINDING-SEED.txt").exists() and not state["completed"]:
        raise ValueError("seed released before completed journal")
    cursor = 0

    def drive(grader, call, kind):
        nonlocal cursor
        index = cursor
        cursor += 1
        identity = {"grader": grader, "kind": kind, "id": call["id"]}
        if index < len(record["calls"]):
            entry = record["calls"][index]
            if {k: entry[k] for k in identity} != identity:
                raise ValueError("record call order differs from prescribed order")
        else:
            entry = dict(identity, sessions=[])
            record["calls"].append(entry)
        validity, problems = [], []
        for number, session in enumerate(entry["sessions"], 1):
            results = []
            for attempt, reply in enumerate(session["replies"], 1):
                expected_file = f"replies/{grader}/{kind}/{call['id']}/{number}-{attempt}.txt"
                if reply["file"] != expected_file:
                    raise ValueError("record reply path differs from prescribed attempt")
                raw = (root / expected_file).read_bytes()
                receipt = json.loads((root / expected_file).with_suffix(".receipt.json").read_text())
                if (receipt["sessionId"] != session_key(grader, kind, call["token"], number) or
                        receipt["file"] != expected_file or receipt["receivedUTC"] != reply["receivedUTC"] or
                        bytes.fromhex(receipt["rawHex"]) != raw):
                    raise ValueError("recorded reply differs from receipt; operator recovery required")
                _, problems = form.check_text(kind, raw,
                                              questions[call["question"]], call["token"])
                results.append(not problems)
            if results:
                validity.append(results)
        while True:
            step = form.next_step(validity)
            if step in ("accept", "missing"):
                return step
            if state["completed"]:
                raise ValueError("completed journal contains unfinished attempts")
            if step not in ("new-session", "fix-up") or (step == "fix-up" and not validity):
                raise ValueError("unexpected state before opening session")
            active = state["active"]
            pending_empty = (active and active["call"] == index and
                             not entry["sessions"][-1]["replies"])
            if step == "new-session" and not pending_empty:
                session = {"startedUTC": tick(), "replies": []}
                entry["sessions"].append(session)
                state["active"] = {"call": index, "phase": "prepared", "sessionId": session_key(
                    grader, kind, call["token"], len(entry["sessions"]))}
                save()
            else:
                session = entry["sessions"][-1]
            active = state["active"]
            if not active or active["call"] != index:
                raise ValueError("session journal does not match pending call")
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
                check_clock()
                if active["phase"] == "prepared":
                    checkpoint("before-open")
                    active["phase"] = "opening"
                    save()
                    handle = adapter.open(grader, kind, packet, session_id=active["sessionId"])
                    active["phase"] = "ready"
                    save()
                    validity.append([])
                else:
                    handle = adapter.resume(grader, kind, packet, session_id=active["sessionId"],
                                            received=len(session["replies"]))
                    if not session["replies"]:
                        validity.append([])
                try:
                    while True:
                        message = ("The reply is invalid:\n" + "\n".join(problems)) if session["replies"] else \
                                  prompts[kind].replace("{token}", call["token"])
                        relative = Path("replies") / grader / kind / call["id"] / ("%d-%d.txt" % (
                            len(entry["sessions"]), len(session["replies"]) + 1))
                        path = root / relative
                        path.parent.mkdir(parents=True, exist_ok=True)
                        for parent in path.parents:
                            if not parent.is_relative_to(root):
                                break
                            sync_directory(parent)
                        check_clock()
                        checkpoint("before-send")
                        active.update(phase="sending", file=relative.as_posix())
                        save()
                        raw = handle.reply(message)
                        checkpoint("after-send")
                        if not isinstance(raw, bytes):
                            raise ValueError("adapter must return exact reply bytes")
                        # Timestamp and bytes share ONE atomic receipt. Never infer
                        # receipt time from mtime or use the later recovery clock.
                        try:
                            received = tick()
                        except ValueError:
                            # Keep bytes for audit, but do not invent a valid
                            # timestamp. This remains an uncertain request.
                            durable_bytes(path, raw)
                            raise
                        receipt = {"sessionId": active["sessionId"], "file": active["file"],
                                   "receivedUTC": received, "rawHex": raw.hex()}
                        durable_json(path.with_suffix(".receipt.json"), receipt)
                        checkpoint("after-receipt")
                        reconcile()
                        checkpoint("after-record")
                        _, problems = form.check_text(kind, raw, questions[call["question"]], call["token"])
                        validity[-1].append(not problems)
                        step = form.next_step(validity)
                        if step != "fix-up":
                            break
                finally:
                    handle.close()

    for grader in score.GRADERS:
        for call in pack.call_order(seed, grader, calls):
            result = drive(grader, call, call["kind"])
            if call["kind"] == "preference" and result == "accept":
                drive(grader, call, "guess")
    if cursor != len(record["calls"]):
        raise ValueError("extra calls in grading record")
    state.update(completed=True, active=None)
    save()
    # Completion is durable before release, so a crash here can finish release
    # without opening a session. A completed invocation is an idempotent read.
    released = root / "BLINDING-SEED.txt"
    if released.exists() and released.read_text().strip() != seed.hex():
        raise ValueError("released seed differs from pack")
    durable_bytes(released, (seed.hex() + "\n").encode("ascii"))
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
        doc, _, _, _, _ = load_pack(args.pack, allow_released=True)
        run(args.pack, RecordedAdapter(json.loads(args.recorded.read_text())),
            PublicCommitment(args.public_branch, dry_run=doc["scope"] == "dry-run"), prompts)
    except (ValueError, OSError, subprocess.SubprocessError, StopIteration) as error:
        parser.exit(2, str(error) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
