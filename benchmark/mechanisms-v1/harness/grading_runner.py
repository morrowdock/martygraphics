# SPDX-License-Identifier: Apache-2.0
"""Crash-safe section 6 session driver with offline and proposed live adapters.

An adapter sees an anonymous packet, the locked prompt and its own session handle.
It never receives the seed, mapping, run id, other replies or operator directory.
Live use is fail-closed until both CLI isolation contracts are verified.
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
import signal
import subprocess
import sys
import tempfile
import uuid
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


MODELS = {"G1": "gpt-6.1-sol", "G2": "gemini-4-argon"}
VERSIONS = {"G1": "codex-cli 0.167.2", "G2": "0.68.0"}
G2_BLOCKER = (
    "UNVERIFIED G2: Antigravity 1.5.6 documents --print, --model, --effort, "
    "--conversation and --sandbox, but its help does not establish a deny-all "
    "web/tool policy, disabled memory/customizations, image attachment format, "
    "or durable JSON session/result schema. Live dispatch is disabled."
)
DISABLED = (
    "shell_tool", "unified_exec", "apply_patch_freeform", "view_image", "js_repl",
    "code_mode", "code_mode_only", "code_mode_host", "multi_agent", "multi_agent_v2",
    "collab", "apps", "plugins", "sleep_tool", "default_mode_request_user_input",
    "codex_hooks", "plugin_hooks", "memories", "memory_tool", "skill_search",
    "skill_mcp_dependency_install", "web_search", "web_search_cached",
    "web_search_request", "standalone_web_search", "browser_use", "computer_use",
    "image_generation", "imagegenext", "search_tool", "tool_search", "tool_suggest",
    "remote_control", "remote_plugin", "shell_snapshot", "request_permissions_tool",
    "request_rule", "exec_permission_approvals", "experimental_use_unified_exec_tool",
)
CODEX_CONFIG = [
    f'model="{MODELS["G1"]}"', 'sandbox_mode="read-only"',
    'model_catalog_json="/home/grader/codex/grader-model.json"',
    'agents.enabled=false', 'tools.experimental_request_user_input.enabled=false',
    'tools.update_plan.enabled=false',
    'model_reasoning_effort="high"', 'web_search="disabled"',
    'approval_policy="never"', 'project_doc_max_bytes=0',
    'developer_instructions=""', 'mcp_servers={}',
    'memories.use_memories=false', 'memories.generate_memories=false',
    'skills.include_instructions=false', 'features.skip_host_skill_discovery=true',
    'features.omit_skill_descriptions=true', 'check_for_update_on_startup=false',
    'include_environment_context=false', 'include_environment_context_time=false',
    'shell_environment_policy.inherit="none"',
] + [f"features.{name}=false" for name in DISABLED]
CODEX_MODEL_POLICY = {
    "tool_mode": "direct", "multi_agent_version": None,
    "experimental_supported_tools": [], "apply_patch_tool_type": None,
}
ENV = {
    "PATH": "/usr/bin:/bin", "HOME": "/home/grader", "CODEX_HOME": "/home/grader/codex",
    "XDG_CONFIG_HOME": "/home/grader/config", "XDG_DATA_HOME": "/home/grader/data",
    "XDG_CACHE_HOME": "/home/grader/cache", "TMPDIR": "/tmp", "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8", "TZ": "UTC", "NO_COLOR": "1",
}


class Uncertain(ValueError):
    """The request may have reached a provider. Never automatically send it again."""


def utc():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def packet_hashes(packet):
    """Read only an anonymous packet; refuse links, special files and extra names."""
    packet = Path(packet)
    if packet.is_symlink() or not packet.is_dir():
        raise ValueError("packet must be a real directory")
    hashes = {}
    for path in sorted(packet.rglob("*")):
        relative = path.relative_to(packet).as_posix()
        if path.is_symlink():
            raise ValueError("packet symlinks are forbidden")
        if path.is_dir():
            if relative not in {"output", "A", "B", "output/sheets", "A/sheets", "B/sheets"}:
                raise ValueError("unexpected packet directory")
            continue
        if not path.is_file() or not re.fullmatch(
                r"question\.json|RUBRIC\.md|(?:output|A|B)/(?:TEXT\.txt|still-[1-5]\.png|sheets/sheet-[0-9]{2}\.png)",
                relative):
            raise ValueError("unexpected packet file")
        hashes[relative] = digest(path)
    if not {"question.json", "RUBRIC.md"} <= hashes.keys():
        raise ValueError("packet is missing its question or rubric")
    return hashes


def prompt_bytes(packet, message):
    pieces = [message]
    for path in sorted(Path(packet).rglob("*")):
        if path.is_file() and path.suffix in (".json", ".md", ".txt"):
            pieces.append("\n--- " + path.relative_to(packet).as_posix() + " ---\n" +
                          path.read_text(encoding="utf-8"))
    images = [path.relative_to(packet).as_posix() for path in sorted(Path(packet).rglob("*.png"))]
    if images:
        pieces.append("\nAttached images, in order:\n" + "\n".join(images))
    return "\n".join(pieces).encode("utf-8"), images


def codex_argv(images=(), remote_id=None):
    args = ["/tool", "exec"]
    if remote_id is not None:
        args.append("resume")
    args += ["--json", "--color", "never"] if remote_id is None else ["--json"]
    args += ["--strict-config", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check",
             "--output-last-message", "/out/reply.bin"]
    for value in CODEX_CONFIG:
        args += ["-c", value]
    if remote_id is None:
        args += ["--cd", "/packet"]
        for name in images:
            args += ["--image", "/packet/" + name]
    else:
        args.append(remote_id)
    return args + ["-"]


def codex_diagnostic_argv(adapter_argv):
    """Project the exact exec/resume configuration into the offline diagnostic.

    Codex debug rejects --strict-config and has no exec transport/resume flags.
    The sandbox supplies the same empty config/rules boundary and packet cwd.
    All -c values (including model, sandbox and catalog) are retained verbatim.
    """
    args = ["/tool", "debug", "prompt-input"]
    for position, value in enumerate(adapter_argv):
        if value in ("-c", "--image"):
            args += [value, adapter_argv[position + 1]]
    return args


def codex_tool_definitions(raw):
    """Read the native diagnostic, not event output after possible execution."""
    items = json.loads(raw)
    if not isinstance(items, list) or not items:
        raise ValueError("missing native prompt-input diagnostic")
    names = []
    def collect(tools, prefix=""):
        if not isinstance(tools, list):
            raise ValueError("invalid native tool definitions")
        for tool in tools:
            name = prefix + tool.get("name", tool["type"])
            if tool["type"] == "namespace" and tool.get("tools"):
                collect(tool["tools"], name + ".")
            else:
                names.append(name)
    for item in items:
        if item["type"] == "additional_tools":
            collect(item["tools"])
        elif item["type"] != "message":
            raise ValueError("unknown native prompt-input item")
    return sorted(names)


def prepare_codex_policy(sandbox, home, packet, output):
    """Pin bundled model metadata and prove an empty tool set without network."""
    catalog_output = output / "catalog"
    catalog_output.mkdir()
    sandbox.invoke(home, packet, catalog_output, ["/tool", "debug", "models"], b"", 30,
                   network=False)
    models = json.loads((catalog_output / "stdout.bin").read_bytes())["models"]
    selected = [model for model in models if model["slug"] == MODELS["G1"]]
    if len(selected) != 1:
        raise ValueError("expected exactly one bundled G1 model")
    model = dict(selected[0])
    model.update(CODEX_MODEL_POLICY)
    catalog = {"models": [model]}
    durable_json(home / "codex/grader-model.json", catalog)
    diagnostic = output / "tools"
    diagnostic.mkdir()
    sandbox.invoke(home, packet, diagnostic, codex_diagnostic_argv(codex_argv()), b"", 30,
                   network=False)
    tools = codex_tool_definitions((diagnostic / "stdout.bin").read_bytes())
    if tools:
        raise ValueError("G1 model-visible tools must be empty: " + ", ".join(tools))
    return catalog


def antigravity_argv(remote_id=None):
    """Only help-confirmed flags; NOT a claim of a safe or verified transport."""
    args = ["/tool", "--print", "--model", "gemini-4-argon", "--effort", "high",
            "--output-format", "json", "--disable-slash-commands", "--sandbox"]
    if remote_id is not None:
        args += ["--conversation", remote_id]
    return args


class Bubblewrap:
    """Expose runtime files, one packet and one private home, never the host home.

    Provider HTTPS needs network access. Model web and execution tools are disabled
    separately. This is not an assertion that provider HTTPS is disconnected.
    """
    def __init__(self, binary, executable="bwrap"):
        self.binary = Path(shutil.which(str(binary)) or binary).resolve(strict=True)
        self.executable = shutil.which(executable)
        if not self.executable:
            raise ValueError("Linux bubblewrap is required; no unsandboxed fallback")

    def command(self, home, packet, output, args, *, network=True):
        argv = [self.executable, "--die-with-parent", "--new-session", "--unshare-all"]
        if network:
            argv.append("--share-net")
        argv += ["--cap-drop", "ALL", "--clearenv"]
        for name in ("/usr", "/bin", "/lib", "/lib64"):
            if Path(name).exists():
                argv += ["--ro-bind", name, name]
        for name in ("/etc/resolv.conf", "/etc/hosts", "/etc/ssl/certs"):
            if Path(name).exists():
                argv += ["--ro-bind", name, name]
        argv += ["--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
                 "--ro-bind", str(self.binary), "/tool",
                 "--bind", str(home), "/home/grader", "--ro-bind", str(packet), "/packet",
                 "--bind", str(output), "/out", "--chdir", "/packet"]
        for name, value in sorted(ENV.items()):
            argv += ["--setenv", name, value]
        return argv + ["--"] + list(args)

    def invoke(self, home, packet, output, args, message, timeout, *, network=True):
        argv = self.command(home, packet, output, args, network=network)
        with (output / "stdout.bin").open("xb") as stdout, (output / "stderr.bin").open("xb") as stderr:
            process = subprocess.Popen(argv, cwd=packet, env=ENV, stdin=subprocess.PIPE,
                                       stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                process.communicate(message, timeout=timeout)
            except BaseException:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                raise
            finally:
                for stream in (stdout, stderr):
                    stream.flush()
                    os.fsync(stream.fileno())
                sync_directory(output)
        if process.returncode:
            raise Uncertain("CLI exited without a complete reply; see private stderr.bin")


def codex_result(output, expected_id=None):
    remote_id = None
    completed = False
    messages = []
    for line in (output / "stdout.bin").read_bytes().splitlines():
        event = json.loads(line)
        kind = event.get("type")
        if kind == "thread.started":
            if remote_id is not None:
                raise Uncertain("multiple sessions in CLI output")
            remote_id = str(uuid.UUID(event["thread_id"]))
        elif kind in ("item.started", "item.updated", "item.completed"):
            item = event["item"]
            if item.get("type") not in ("agent_message", "reasoning"):
                raise Uncertain("unexpected tool use; isolation acceptance failed")
            if kind == "item.completed" and item["type"] == "agent_message":
                messages.append(item["text"])
        elif kind == "turn.completed":
            if completed:
                raise Uncertain("multiple turns in one request")
            completed = True
        elif kind != "turn.started":
            raise Uncertain("unknown or failed CLI event; operator recovery required")
    if not completed or not remote_id or not messages or (expected_id and remote_id != expected_id):
        raise Uncertain("missing completion or exact session identity")
    raw = (output / "reply.bin").read_bytes()
    if not raw or raw not in (messages[-1].encode("utf-8"), (messages[-1] + "\n").encode("utf-8")):
        raise Uncertain("final reply file differs from CLI event")
    return remote_id, raw


def home_hashes(home, *, sync=False):
    hashes = {}
    for path in sorted(home.rglob("*")):
        if path.is_symlink() or (not path.is_file() and not path.is_dir()):
            raise Uncertain("unexpected special file in isolated CLI home")
        if path.is_file():
            if sync:
                with path.open("rb") as stream:
                    os.fsync(stream.fileno())
            hashes[path.relative_to(home).as_posix()] = digest(path)
    if sync:
        for path in sorted([home] + [p for p in home.rglob("*") if p.is_dir()], reverse=True):
            sync_directory(path)
    return hashes


class CodexAdapter:
    grader = "G1"

    def __init__(self, root, binary, *, auth=None, timeout=300):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if self.root.stat().st_mode & 0o077:
            raise ValueError("adapter state directory must be private (mode 0700)")
        self.sandbox = Bubblewrap(binary)
        self.auth = Path(auth).resolve(strict=True) if auth else None
        self.timeout = timeout
        if timeout <= 0:
            raise ValueError("timeout must be positive")
        self.binary_hash = self.binary_digest()

    def binary_digest(self):
        return digest(self.sandbox.binary)

    def policy_digest(self):
        return policy_hash()

    def initialize_home(self, home):
        (home / "codex").mkdir(mode=0o700)
        durable_json(home / "codex/grader-model.json", self.catalog)
        if self.auth:
            auth = home / "codex/auth.json"
            durable_bytes(auth, self.auth.read_bytes())
            auth.chmod(0o600)

    def transport(self, payload, images, remote_id, output):
        return codex_argv(images, remote_id), payload

    def result(self, output, expected_id):
        return codex_result(output, expected_id)

    def preflight(self):
        """Native version/catalog/tool checks, no network or model request."""
        with tempfile.TemporaryDirectory(dir=self.root) as temp:
            root = Path(temp)
            for name in ("home", "packet", "out"):
                (root / name).mkdir()
            (root / "home/codex").mkdir()
            self.sandbox.invoke(root / "home", root / "packet", root / "out",
                                ["/tool", "--version"], b"", 15, network=False)
            version = (root / "out/stdout.bin").read_text().strip()
            if version != VERSIONS[self.grader]:
                raise ValueError("CLI version changed; review invocation and isolation again")
            self.catalog = prepare_codex_policy(self.sandbox, root / "home", root / "packet",
                                                root / "out")
        return version

    def open(self, grader, kind, packet, *, session_id):
        if grader != self.grader or kind not in ("score", "preference", "guess"):
            raise ValueError("wrong grader or call kind")
        if not re.fullmatch(r"[0-9a-f]{64}", session_id):
            raise ValueError("expected opaque session id")
        hashes = packet_hashes(packet)
        self.preflight()
        path = self.root / session_id
        path.mkdir(mode=0o700)
        sync_directory(self.root)
        home = path / "home"
        home.mkdir(mode=0o700)
        self.initialize_home(home)
        shutil.copytree(packet, path / "packet")
        if packet_hashes(path / "packet") != hashes:
            raise ValueError("packet changed while copying")
        home_hashes(path / "packet", sync=True)
        state = {"kind": "mechanisms-v1.live-session/1", "sessionId": session_id,
                 "grader": grader, "callKind": kind, "packetHashes": hashes,
                 "model": MODELS[grader], "effort": "high", "toolVersion": VERSIONS[grader],
                 "binarySha256": self.binary_hash, "policySha256": self.policy_digest(),
                 "startedUTC": utc(), "remoteSessionId": None, "replies": [], "phase": "ready",
                 "homeHashes": home_hashes(home, sync=True)}
        durable_json(path / "state.json", state)
        sync_directory(path)
        return LiveSession(self, path)

    def resume(self, grader, kind, packet, *, session_id, received):
        if not re.fullmatch(r"[0-9a-f]{64}", session_id):
            raise ValueError("expected opaque session id")
        path = self.root / session_id
        state = json.loads((path / "state.json").read_text())
        if (state["grader"], state["callKind"], state["sessionId"], state["packetHashes"],
                state["binarySha256"], state["policySha256"]) != (
                grader, kind, session_id, packet_hashes(packet), self.binary_hash, self.policy_digest()):
            raise Uncertain("session binding changed; operator recovery required")
        if state["phase"] != "ready" or len(state["replies"]) != received:
            raise Uncertain("uncertain request or reply count; never resend")
        if received and not state["remoteSessionId"]:
            raise Uncertain("no exact session id to resume")
        if home_hashes(path / "home") != state["homeHashes"]:
            raise Uncertain("exact session storage changed")
        for number, receipt in enumerate(state["replies"], 1):
            output = path / str(number)
            if receipt.get("inputSha256") and digest(output / "input.txt") != receipt["inputSha256"]:
                raise Uncertain("durable adapter input changed")
            if json.loads((output / "receipt.json").read_text()) != receipt or \
                    (output / "reply.bin").read_bytes() != bytes.fromhex(receipt["rawHex"]) or \
                    digest(output / "stdout.bin") != receipt["stdoutSha256"] or \
                    digest(output / "stderr.bin") != receipt["stderrSha256"]:
                raise Uncertain("durable adapter receipt changed")
        return LiveSession(self, path)


class LiveSession:
    def __init__(self, adapter, path):
        self.adapter = adapter
        self.path = path

    def reply(self, message):
        with (self.path / "LOCK").open("a+b") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise Uncertain("session already active") from error
            return self._reply(message)

    def _reply(self, message):
        path = self.path
        state = json.loads((path / "state.json").read_text())
        if state["phase"] != "ready":
            raise Uncertain("uncertain request; never resend")
        if len(state["replies"]) >= 2:
            raise ValueError("section 6 permits only one fix-up per session")
        if packet_hashes(path / "packet") != state["packetHashes"]:
            raise ValueError("session packet changed")
        if self.adapter.binary_digest() != state["binarySha256"]:
            raise ValueError("CLI binary changed")
        if home_hashes(path / "home") != state["homeHashes"]:
            raise Uncertain("exact session storage changed")
        if state["replies"]:
            if not message.startswith("The reply is invalid"):
                raise ValueError("only a parse-error fix-up may resume this session")
            payload, images = message.encode("utf-8"), []
        else:
            payload, images = prompt_bytes(path / "packet", message)
        output = path / str(len(state["replies"]) + 1)
        output.mkdir(mode=0o700)
        sync_directory(path)
        args, payload = self.adapter.transport(payload, images, state["remoteSessionId"], output)
        request = {"sessionId": state["sessionId"], "remoteSessionId": state["remoteSessionId"],
                   "startedUTC": utc(), "toolVersion": state["toolVersion"],
                   "argv": self.adapter.sandbox.command(path / "home", path / "packet", output, args),
                   "env": getattr(self.adapter.sandbox, "env", ENV), "stdinSha256": hashlib.sha256(payload).hexdigest()}
        if (output / "input.txt").exists():
            request["inputSha256"] = digest(output / "input.txt")
        durable_json(output / "request.json", request)
        state["phase"] = "sending"
        durable_json(path / "state.json", state)
        try:
            self.adapter.sandbox.invoke(path / "home", path / "packet", output, args,
                                        payload, self.adapter.timeout)
            received = utc()
            remote_id, raw = self.adapter.result(output, state["remoteSessionId"])
            if state["remoteSessionId"] is None:
                registry = self.adapter.root / "remote-ids"
                registry.mkdir(mode=0o700, exist_ok=True)
                with (registry / remote_id).open("xb") as claim:
                    claim.write(state["sessionId"].encode("ascii"))
                    claim.flush()
                    os.fsync(claim.fileno())
                sync_directory(registry)
                sync_directory(self.adapter.root)
            if received < request["startedUTC"]:
                raise Uncertain("clock moved backwards")
            receipt = {"sessionId": state["sessionId"], "remoteSessionId": remote_id,
                       "startedUTC": request["startedUTC"], "receivedUTC": received,
                       "toolVersion": state["toolVersion"], "binarySha256": state["binarySha256"],
                       "rawHex": raw.hex(), "stdoutSha256": digest(output / "stdout.bin"),
                       "stderrSha256": digest(output / "stderr.bin")}
            if "inputSha256" in request:
                receipt["inputSha256"] = request["inputSha256"]
            durable_bytes(output / "reply.bin", raw)
            durable_json(output / "receipt.json", receipt)
            state["homeHashes"] = home_hashes(path / "home", sync=True)
            state["remoteSessionId"] = remote_id
            state["replies"].append(receipt)
            state["phase"] = "ready"
            durable_json(path / "state.json", state)
            return raw
        except Exception as error:
            state["phase"] = "uncertain"
            durable_json(path / "state.json", state)
            durable_json(output / "uncertain.json", {
                "sessionId": state["sessionId"], "remoteSessionId": state["remoteSessionId"],
                "startedUTC": request["startedUTC"], "receivedUTC": None, "stoppedUTC": utc(),
                "toolVersion": state["toolVersion"], "errorType": type(error).__name__,
                "status": "uncertain; partial wire output is not a completed reply",
            })
            raise Uncertain("uncertain CLI request; retained bytes need operator recovery") from error

    def close(self):
        """Keep this session's home for an exact, completed-turn fix-up only."""


class AntigravityAdapter:
    """Documented invocation proposal; deliberately no unsafe execution switch."""
    def preflight(self):
        raise ValueError(G2_BLOCKER)

    def open(self, grader, kind, packet, *, session_id):
        self.preflight()

    def resume(self, grader, kind, packet, *, session_id, received):
        raise Uncertain(G2_BLOCKER + " Exact reattachment cannot be established.")


class LiveAdapter:
    def __init__(self, root, binary, *, auth=None, timeout=300, gemini_bin=None, gemini_auth=None):
        from gemini_adapter import GeminiAdapter
        if gemini_bin is None:
            raise ValueError("--gemini-bin is required for G2")
        self.adapters = {"G1": CodexAdapter(root, binary, auth=auth, timeout=timeout),
                         "G2": GeminiAdapter(Path(root) / "g2", gemini_bin, auth=gemini_auth, timeout=timeout)}

    def preflight(self):
        self.adapters["G2"].preflight()
        self.adapters["G1"].preflight()

    def open(self, grader, kind, packet, *, session_id):
        return self.adapters[grader].open(grader, kind, packet, session_id=session_id)

    def resume(self, grader, kind, packet, *, session_id, received):
        return self.adapters[grader].resume(grader, kind, packet, session_id=session_id, received=received)


def policy_hash():
    return hashlib.sha256(json.dumps([CODEX_CONFIG, ENV, digest(__file__)], sort_keys=True).encode()).hexdigest()


def self_test(args):
    """No benchmark inputs. Dry mode does not execute even --version."""
    if args.grader == "G2":
        from gemini_adapter import self_test as gemini_self_test
        return gemini_self_test(args)
    root = args.work.resolve()
    root.mkdir(mode=0o700)
    sandbox = Bubblewrap(args.binary)
    plans = []
    for number in (1, 2):
        folder = root / str(number)
        for name in ("home/codex", "packet", "out"):
            (folder / name).mkdir(parents=True, mode=0o700)
        command = codex_argv() if args.grader == "G1" else antigravity_argv()
        plans.append({"argv": sandbox.command(folder / "home", folder / "packet", folder / "out", command),
                      "env": ENV, "cwd": str(folder / "packet"), "stdin": "reply with the word OK"})
    if not args.run:
        print(json.dumps({"status": "DRY; no CLI executed", "plans": plans,
                          "blocker": G2_BLOCKER if args.grader == "G2" else None}, indent=2))
        return 0
    if args.grader == "G2":
        raise ValueError(G2_BLOCKER)
    if not args.auth:
        raise ValueError("self-test --run requires an explicit auth-only file")
    ids = []
    sentinel = root / "outside-secret"
    durable_bytes(sentinel, os.urandom(32))
    for number, plan in enumerate(plans, 1):
        folder = root / str(number)
        probe = folder / "probe"
        probe.mkdir()
        sandbox.invoke(folder / "home", folder / "packet", probe,
                       ["/bin/sh", "-c", 'test ! -e "$1" && test ! -e /etc/codex && test ! -e /repo',
                        "probe", str(sentinel)], b"", 15)
        version = folder / "version"
        version.mkdir()
        sandbox.invoke(folder / "home", folder / "packet", version, ["/tool", "--version"], b"", 15)
        if (version / "stdout.bin").read_text().strip() != VERSIONS["G1"]:
            raise ValueError("CLI version changed")
        prepare_codex_policy(sandbox, folder / "home", folder / "packet", version)
        durable_bytes(folder / "home/codex/auth.json", args.auth.read_bytes())
        (folder / "home/codex/auth.json").chmod(0o600)
        started = utc()
        sandbox.invoke(folder / "home", folder / "packet", folder / "out",
                       codex_argv(), plan["stdin"].encode(), args.timeout)
        received = utc()
        remote_id, raw = codex_result(folder / "out")
        if raw.strip() != b"OK" or remote_id in ids:
            raise ValueError("synthetic reply or fresh session check failed")
        ids.append(remote_id)
        durable_json(folder / "out/receipt.json", {"remoteSessionId": remote_id, "rawHex": raw.hex(),
                     "startedUTC": started, "receivedUTC": received, "toolVersion": VERSIONS["G1"]})
    durable_json(root / "SELF-TEST.json", {
        "status": "synthetic smoke passed; coordinator review still required",
        "remoteSessionIds": ids, "binarySha256": digest(args.binary), "policySha256": policy_hash(),
        "checkedUTC": utc(), "noWeb": "web and execution tools disabled; no tool events observed",
        "filesystem": "outside sentinel absent; only explicit runtime and task mounts exposed",
        "limits": "Not proof of provider-side behavior or multimodal fidelity. No benchmark readiness grant."
    })
    print("Synthetic smoke passed. Review SELF-TEST.json; benchmark live mode remains blocked by G2.")
    return 0


def self_test_main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["self-test"])
    parser.add_argument("--grader", choices=["G1", "G2"], required=True)
    parser.add_argument("--binary", type=Path, required=True, help="native CLI executable, not a mise shim")
    parser.add_argument("--work", type=Path, required=True, help="new private directory; never inside the repo")
    parser.add_argument("--auth", type=Path, help="explicit auth-only file; never printed or used in dry mode")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--run", action="store_true", help="SPENDS QUOTA: two harmless OK prompts")
    mode.add_argument("--dry", action="store_true", help="default: print exact argv/env, no process starts")
    parser.add_argument("--timeout", type=float, default=300)
    args = parser.parse_args(argv)
    try:
        return self_test(args)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(2, str(error) + "\n")


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv[:1] == ["self-test"]:
        return self_test_main(argv)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    adapters = parser.add_mutually_exclusive_group(required=True)
    adapters.add_argument("--recorded", type=Path, help="offline reply sessions")
    adapters.add_argument("--live", action="store_true", help="proposed live adapters; requires reviewed runtime pins and owner OAuth")
    parser.add_argument("--adapter-state", type=Path, help="private durable CLI state outside packets and repo")
    parser.add_argument("--codex-bin", type=Path, help="native Codex executable, not a shim")
    parser.add_argument("--gemini-bin", type=Path, help="pinned official Gemini CLI bundle/gemini.js")
    parser.add_argument("--gemini-auth", type=Path, help="owner OAuth-only JSON; defaults to ~/.gemini/oauth_creds.json")
    parser.add_argument("--codex-auth", type=Path, help="explicit auth-only file; never inherited from host config")
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--public-branch", required=True, help="read-only public commitment verification")
    args = parser.parse_args(argv)
    if args.live:
        if not args.adapter_state or not args.codex_bin:
            parser.error("--live needs --adapter-state and --codex-bin")
        try:
            adapter = LiveAdapter(args.adapter_state, args.codex_bin, auth=args.codex_auth, timeout=args.timeout,
                                  gemini_bin=args.gemini_bin, gemini_auth=args.gemini_auth)
            adapter.preflight()
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            parser.exit(2, str(error) + "\n")
    else:
        try:
            adapter = RecordedAdapter(json.loads(args.recorded.read_text()))
        except (ValueError, OSError) as error:
            parser.exit(2, str(error) + "\n")
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
        run(args.pack, adapter,
            PublicCommitment(args.public_branch, dry_run=doc["scope"] == "dry-run"), prompts)
    except (ValueError, OSError, subprocess.SubprocessError, StopIteration) as error:
        parser.exit(2, str(error) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
