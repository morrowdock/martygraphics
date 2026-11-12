# Proposed live grader adapters

Status: **PROPOSED, 2026-11-12. Not run-ready. G2 is UNVERIFIED and blocked.**
Base: `9e95ad3d69a54bce75b1a86d5b136734fb3ddb84`.
Sources: `LOCK.json`, `PROTOCOL.md` sections 6 and 9, `grading_runner.py`, the
local commands below, and the official Codex CLI/config references.

## Verified local interface evidence

The implementation host is Linux. These observations are not run-host pins.
The initial Antigravity mise shim installed its configured 1.5.6 binary when
asked for a version; subsequent queries used that native binary directly.
No login, model-list query, prompt or paid request was made.

| Tool | Local version output | Help checked |
| --- | --- | --- |
| Codex | `codex-cli 0.167.2` | `codex exec --help`, `codex exec resume --help` |
| Antigravity | `1.5.6` | `antigravity --help`, `antigravity help acp` |
| `agy` | Same Antigravity distribution | `agy --help` (same options) |
| bubblewrap | `bubblewrap 0.13.1` | Filesystem sandbox used by fake CLI tests |

The native executables on this host were:

```text
~/.local/share/mise/installs/codex/0.167.2/bin/codex
~/.local/share/mise/installs/antigravity-cli/1.5.6/antigravity
```

Codex documents `exec`, `--model`, `--json`, `--image`,
`--output-last-message`, `--ignore-user-config`, `--ignore-rules`,
`--strict-config`, `--skip-git-repo-check`, and `exec resume <session-id>`.
The fresh command selects `gpt-6.1-sol`, `model_reasoning_effort="high"`, and
`--sandbox read-only`. It reads the prompt from stdin (`-`). Fix-up uses the
exact stored UUID, not `--last`, `fork`, a thread name, or a new session.
Resume is a new turn in a **completed** conversation, not a way to query or
retry an outstanding request. There is no blind recovery send.

Official references checked on 2026-11-12:

- https://developers.openai.com/codex/cli/reference/
- https://developers.openai.com/codex/config-reference/
- https://developers.openai.com/codex/config-schema.json

The schema documents the web, memory, skills and tool feature switches used
in `CODEX_CONFIG`. Live compatibility of their combined effect remains
**pending**. Help and a version query do not verify model availability,
image fidelity, backend settings, session persistence or isolation against
a real model. The adapter uses strict config parsing and fails on unknown
transport events instead of guessing.

## Isolation design and limits

Each `open` creates a new private session directory. The subprocess receives
only a copy of its anonymous packet, the caller's rubric prompt, and its own
CLI home. Text is embedded in stdin with packet-relative labels. All stills
and sheets are attached with `--image` in the printed order. No source tree,
run id, blinding seed, arm mapping, sibling packet, prior grade or operator
directory is mounted. Guess calls have their own sessions. No real prompt or
question is embedded in adapter source or tests.

Bubblewrap creates a new mount/PID/IPC namespace, removes capabilities, and
starts from an empty root. It mounts the native CLI, read-only system runtime
directories, TLS certificates and DNS files, this packet read-only, this
session's home, and this turn's output directory. It clears the environment.
`HOME`, `CODEX_HOME`, XDG paths and temporary files refer to private locations.
Host `/etc/codex`, home configuration, MCP servers, plugins, agent rules and
repository instructions are not mounted. Prompt discovery is also disabled.
The parent environment, proxy settings and API keys are not inherited.

**This is not a network-disconnected process.** Provider HTTPS must work.
Web search, shell, image-view, browser, code execution, agent, memory and
extension features are disabled in the Codex proposal. Images arrive as
attachments, so image-view tools are not needed. Unknown tool events stop
acceptance and leave the request uncertain. Event checking is detection,
not a substitute for preventing a tool from running. The current proposal
does not prove absence of hidden provider capabilities. The CLI can read its
explicit runtime/TLS files outside the task directory; the claim is no host
user/repository access and no enabled agent file/web tools, not literal
inaccessibility of every runtime file. These limits need coordinator review.

Use a native binary, not a shell wrapper that needs an unmounted install tree.
There is no unsandboxed fallback. `--codex-auth` selects one auth-only JSON
file explicitly. It is copied into the private home; no host config or session
directory is copied. Do not commit, attach or publish the home, auth file,
stderr or private adapter state. Do not place them in a repository. An auth
file is not read in dry mode. Credential setup is outside this change.

## G2: exact blocker

The help-confirmed non-interactive proposal is:

```text
antigravity --print --model gemini-4-argon --effort high \
  --output-format json --disable-slash-commands --sandbox
```

The documented resume selector is `--conversation <id>`, not `--continue`.
However, the local help does not define a safe all-tools/web deny policy,
disabled memory/custom instructions, image input encoding, a JSON result and
session-id schema, or a query-only way to recover an outstanding turn. ACP
help has `--include-default-customizations` and `--process-per-session`, but
those flags do not by themselves establish all required controls.

`AntigravityAdapter.open` and `resume` therefore refuse. The dry planner shows
only documented flags. There is **no unsafe override**, fabricated result
decoder, or substitute Gemini CLI/API. Further work must establish the G2
input/result and isolation contracts, implement them, and pass synthetic
acceptance before enabling this adapter. `--live` preflights G2 first and
stops the entire run without reading the pack or locked prompts. It cannot
spend G1 quota and fail halfway through because G2 was unavailable.

## Synthetic self-test: coordinator only

The following command is quota-free. Use a new private directory outside the
repository for every invocation. It prints exact model argv, a clean env,
the working directories and stdin for two new sessions. It does not execute
the CLI, read credentials or load benchmark files.

```sh
python benchmark/mechanisms-v1/harness/grading_runner.py self-test \
  --grader G1 --binary /absolute/path/to/native/codex \
  --work /private/new/grader-smoke-dry --dry
```

Replace `G1` and the binary with `G2` and Antigravity to inspect the blocked
G2 invocation. That plan is UNVERIFIED, not an executable acceptance test.

After review, the coordinator may run the G1 smoke test with:

```sh
python benchmark/mechanisms-v1/harness/grading_runner.py self-test \
  --grader G1 --binary /absolute/path/to/native/codex \
  --work /private/new/grader-smoke-live \
  --auth /private/auth-only.json --run
```

**This spends quota on two prompts. It was not run against a real CLI.**
Both prompts are exactly `reply with the word OK`, with no packet or rubric.
Before sending, the tool runs a filesystem sentinel probe and `--version`
inside each sandbox. It then checks distinct session UUIDs, exact `OK`
responses, no unexpected tool events, and records times and bytes. It retains
`SELF-TEST.json` and the wire output for review. Tests exercise this path only
with fake executables on PATH. An `OK` response alone is not an isolation
proof. This smoke test cannot grant benchmark readiness, and it does not
test multimodal fidelity. G2 `--run` still refuses without a model call.

## Durable receipts and recovery

The adapter implements the merged `open/resume` interface. `open` allocates
a fresh home but sends no prompt. A write-ahead `request.json` and `sending`
state are fsynced before the CLI starts. Each turn retains `stdout.bin`,
`stderr.bin`, exact `reply.bin`, and `receipt.json` with the opaque runner id,
provider session UUID, start/received UTC, tool version, binary hash and
`rawHex`. The home and reply files are synced before the ready state is
committed. A private UUID registry rejects reuse of a provider session for
another call. No registry or receipt is mounted for the model.

`resume` does no model I/O. It verifies packet/policy/binary/home bindings,
receipt bytes and counts. Only a known complete first turn can receive its
one fix-up, in the same stored conversation. The fix-up sends only the parse
error, not the packet again. Malformed **grade** text is a durable reply for
the existing runner validator. A malformed **CLI envelope**, missing reply,
wrong session id, unexpected tool event, timeout or process failure is
uncertain. A killed parent leaves durable `sending`, which is also uncertain.
No such state can send again. A CLI process group is killed on timeout.

Runner receipts and adapter receipts are independent. If the runner crashes
after send and before its own receipt, it continues to refuse a resend even
if the adapter has a complete receipt. A reviewer can inspect that evidence
and restore the runner receipt with the original bytes and receipt time,
as PACKING.md describes. Never use a later resume time. No automatic receipt
promotion, uncertain-turn replay, deletion/reset command or replacement
attempt is supplied. Partial stdout is evidence, not an accepted grade.

## Validation and remaining gates

Run only synthetic tests:

```sh
python -m unittest discover -s benchmark/mechanisms-v1/harness/tests
python3 -m unittest discover -s tools/tests
```

Use NumPy **2.5.4** for the harness. Fake process tests require bubblewrap.
They exercise success, invalid grades, corrupt envelopes, timeout, process
exit after send, retained receipts, exact resume, packet rejection, filesystem
and env boundaries, runner fix-up, and refusal to resend after a crash.
The old test reads of the two registered keys were replaced with synthetic
metadata. Production keys, prompts and scoring arithmetic are unchanged.

Pending gates: real G1 synthetic acceptance, authoritative tool capability
review, image ordering/fidelity checks, G2 safe contract and implementation,
both exact model/effort settings, reviewed binary and host pins, macOS native
media validation and the registered dry run. RUN-LOCK is still DRAFT.
