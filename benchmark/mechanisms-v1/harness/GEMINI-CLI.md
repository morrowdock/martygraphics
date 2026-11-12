# G2 Gemini CLI route

Status: **PROPOSED implementation; owner-approved route change on 2026-11-12.
Not run-ready.** Checked: 2026-11-12 UTC. Base:
`7332c125b83c94fd93acfbd1e77645d978e6ce87`. See A-16 in
[AMENDMENTS.md](../AMENDMENTS.md). No benchmark packet, rubric or synthetic
prompt was sent to a model. No OAuth flow was started.

## Installation and pins (VERIFIED)

Official package: `@google/gemini-cli@0.68.0`, repository
https://github.com/google-gemini/gemini-cli. Installed in user space, without
sudo, with:

```sh
npm install --prefix "$HOME/.local/share/martygraphics-gemini-cli-0.68.0" \
  --save-exact @google/gemini-cli@0.68.0
```

The entry point is
`~/.local/share/martygraphics-gemini-cli-0.68.0/node_modules/.bin/gemini`.
It resolves to the package's `bundle/gemini.js`. Node is `v26.13.0` on this
implementation host. The adapter mounts the whole pinned package read-only;
copying the entry point alone would break its relative imports. No package
or auth directory is put in Git. Optional keytar install scripts were not
approved or needed for the file-based OAuth route.

| Artifact | SHA-256 |
| --- | --- |
| npm `gemini-cli-0.68.0.tgz` | `325099ddcb56937c27d119e7297bfa8a5e29b529bae3c92fdf3b71a36d5fa006` |
| Installed `bundle/gemini.js` | `fcc38edd4f864c2f5fa582d7d133c19b1a04c697ad3143ab8045f92b77644c68` |
| Installed package tree | `6597de6c1c6ed400d17320b07f1feff7bd20676d270e8092dd55069533709bc4` |
| Node executable | `0adde40d1b7dfa57c8bc83cbc319758c3ec6ebba21363bb2fa752ea6b267ad1b` |
| Package plus Node runtime binding | `67b5048aef821db4682ec9b6fc7cd61b0bfd2fd2df827c82bf41ffce6f968b32` |

The tree digest is SHA-256 of `grading_runner.json_bytes(records)`, where
`records` is a sorted list of `[relative POSIX path, SHA-256]` for every
regular package file. Links and special files are rejected. The runtime
binding hashes `json_bytes({"package": tree_digest, "node": node_digest})`.
This is the G2 receipt's `binarySha256`; the native-check report also names
the separate entry point, package and Node hashes. All are draft host pins.

## Verified interface and source evidence

These are the installed package's own help, documentation and readable bundled
source, pinned by the package hash above. The corresponding public sources are
under https://github.com/google-gemini/gemini-cli/tree/v0.68.0 . No guessed flags
or API calls are used.

| Requirement | Evidence and implementation |
| --- | --- |
| Single non-interactive prompt | `--help`: `--prompt/-p`; stdin is appended if present. We use an explicit prompt and empty stdin. |
| Images | `bundle/docs/reference/commands.md` documents `@file`; `ReadManyFilesTool` and `processSingleFileContent` in `chunk-RCB6BI5H.js` explicitly support named PNGs as `inlineData`. The driver adds each image in sorted packet-relative order. |
| JSON and identity | `bundle/docs/cli/headless.md`: `json` and `stream-json`. We use JSONL `stream-json` to see tool events, plus `--raw-output --accept-raw-output-risk` to preserve reply text without ANSI stripping. Wire data is stored, not rendered. `init.session_id` and `init.model`, assistant message deltas, and final `result.status/stats` are checked. |
| Resume | `bundle/docs/cli/session-management.md` documents a full UUID with `--resume`. Only the saved complete conversation's UUID is used. Session history keeps user content parts, including images (`convertSessionToClientHistory`). No `latest`, index, fork or retry of an outstanding turn. |
| Tools, shell, search | `tools.core=[]` is a real empty allowlist in `Config.createToolRegistry`. An admin-tier TOML rule denies `toolName="*"`, priority 999. No agent shell/file/web/search definitions are allowed. Client-side attachment reading is deliberate, not a model tool. |
| MCP, extensions, skills, hooks | `admin.mcp.enabled=false`, empty `mcpServers`, `admin.extensions.enabled=false`, `--extensions none`, disabled skills, agents and hooks. Host config and extension directories are absent. |
| Memory and custom context | No host home, workspace config, rules, sessions or memory are mounted. Packet names are strictly allowlisted. New homes contain only generated settings/policy and the OAuth file. Auto-memory and directory-tree context are disabled. Resume refuses any Markdown file in the private home. |
| Checkpointing | `general.checkpointing.enabled=false`. Session recording remains available for exact resume; it is separate from file-edit checkpointing. |
| Payment | OAuth personal auth is selected and enforced; API-key/proxy/cloud env is not inherited. `billing.overageStrategy="never"` disables AI-credit overages. |

Configuration references: `bundle/docs/reference/configuration.md` and
`bundle/docs/reference/policy-engine.md`. Implementation references:
`bundle/gemini-Q2FNZWQG.js` (`loadCliConfig`, headless output),
`bundle/chunk-UWDUE2FI.js` (`handleAtCommand`, extension selection), and
`bundle/chunk-RCB6BI5H.js` (core config, policy, model resolution, file reads,
OAuth storage and session history). These are local filenames within the
pinned npm package, not project files.

**Important source finding:** `setGeminiMdFilename` adds to the existing list.
Neither an empty array nor a custom name disables `GEMINI.md`. No such claim
is made here. Empty memory depends on the filesystem boundary. The native
probe verifies discovery against that boundary, including an unmounted
synthetic memory file. Its negative test places a synthetic `GEMINI.md` in
the private home and confirms rejection.

## Model and thinking (VERIFIED locally; account access PENDING)

`gemini-4-argon` does not appear in the shipped model definitions or signed-out
catalog. The closest shipped Pro candidate is **`gemini-3.1-pro-preview`**.
This changes the model identity as well as the CLI route; it is not an alias
or a claim of equivalence. The adapter and draft pins select that exact ID.
The bundled model config uses `thinkingLevel: "HIGH"`; an explicit custom
override retains it. This is the documented mapping for registered "thinking
high", not evidence that Argon's behavior is reproduced.

Signed-out `models list --output-format json` shows stable model choices,
including `gemini-2.5-pro` and `gemini-3.5-flash`. It hides the 3.1 Pro preview
without account launch/access metadata. The library probe separately verifies
that the 3.1 Pro preview definition exists, is multimodal, and is marked as a
preview in the untouched package. A local listing cannot prove subscription
access. No claim of `gemini-4-argon` availability is made.

The CLI otherwise downgrades a preview model to Auto/2.5 when preview access
is absent and can select a fallback chain. The adapter enables documented
dynamic model configuration, gives this ID an identity resolution, sets its
**local routing** `isPreview` bit to false, and empties the `preview` and
`default` fallback chains. The native probe checks resolution with and without
preview access. The original package definition stays unchanged and still says
preview. This local routing override does not grant provider access or make
the model GA: an unavailable model must fail. Init and final per-model usage
must name only the selected model. Any other model makes the turn uncertain.
These behavior changes need review before run 1.

## Isolation, input and durable state

`GeminiAdapter` implements the merged `Adapter.open/resume` interface and uses
G1's write-ahead state, process-group timeout kill, fsynced wire output, reply
bytes, receipts, private session registry and no-resend recovery. `open` makes
a new private home per call and sends nothing. The first `reply` sends the
packet. A completed first reply may receive one parse-error fix-up, with only
the error text and the exact saved UUID. Unknown/tool/error events, malformed
envelopes, wrong model/session, crashes, timeout and incomplete streams are
uncertain. Malformed grade text is preserved for the merged validator.

Bubblewrap starts from an empty root, clears env and mounts the same minimal
system runtime/TLS/DNS files as G1, the Gemini package and Node read-only,
one packet read-only, one private home and only the current turn's output.
`/input/input.txt` is a read-only bind of the caller's text for this turn.
There is no unsandboxed fallback. Live provider HTTPS is available; offline
checks use `--unshare-all` without `--share-net`.

The CLI's `@` preprocessing could otherwise interpret literal `@` text in a
packet as a path, including an auth path. The driver puts all text into
`input.txt` and constructs only `@/input/input.txt` plus allowlisted PNG paths.
Loaded text is not parsed again for `@` or slash commands. Fix-up has only the
text-file reference. Native file reading normalizes line endings and the
attachment formatter trims surrounding whitespace and adds reference labels.
The driver refuses CR/NUL text, text over 2,000 lines or 2,000 UTF-16 code units
per line, and files over 20 MiB before send to avoid native truncation. Packet
copy bytes, submitted text bytes, wire bytes and returned reply bytes remain
durable; the input file hash is checked on resume.

Runtime state must be outside every Git repository and mode 0700. The only
owner file copied is `~/.gemini/oauth_creds.json` (or explicit `--gemini-auth`),
a private OAuth refresh credential file. Copying occurs only at runtime after
quota-free checks. No settings, accounts file, session tree, API key or token
is printed or placed in receipts/Git. Private home, stderr and wire output
must never be published. Token refresh is confined to the per-session copy.

## What the native check proves

```sh
python benchmark/mechanisms-v1/harness/gemini_adapter.py check \
  --binary "$HOME/.local/share/martygraphics-gemini-cli-0.68.0/node_modules/.bin/gemini" \
  --work /absolute/private/directory/outside/git
```

**VERIFIED, quota-free:** native `--version`, `models list`, and the checked-in
`native/gemini_probe.mjs` run in bubblewrap with no network or auth. The probe
imports the installed core library; it does not replace it. It constructs
Config with the adapter's corresponding settings and directly checks:

- zero registered function definitions and empty discovered user memory;
- exact model resolution and HIGH thinking;
- a synthetic text file and a one-pixel PNG as exact native file content.

Negative native tests expose a shell tool, insert memory, and remove the model
routing override. Each fails the check. No model method, `refreshAuth` or full
`Config.initialize` is invoked. Storage initialization is local only.

**LIMIT:** Gemini 0.68.0 offers no documented offline complete request/tool
configuration dump. `/tools` is an interactive command after CLI auth startup,
not an auth-free diagnostic. Our library probe maps the relevant Config fields
from the documented settings and reviewed `loadCliConfig` code; it does **not**
exercise the full CLI settings loader, post-auth remote admin controls, model
service or final request assembly. It is narrower than G1's native
`debug prompt-input` check. It must not be represented as proof of the complete
post-auth effective request.

The CLI also adds its built-in system prompt and environment context (date,
Linux and the private temporary path). These are not disabled by
`includeDirectoryTree=false`. Thus "empty context" here means no external
user/repository/memory/extension context, not an empty system prompt. Provider
hidden capabilities, subscription access, remote controls, full multimodal
fidelity and real exact-session fix-up remain **PENDING**. RUN-LOCK stays DRAFT.

## Owner sign-in: the only owner action

Auth state on 2026-11-12: **owner action needed**, no local OAuth file found.
Run this one command on this laptop:

```sh
~/.local/share/martygraphics-gemini-cli-0.68.0/node_modules/.bin/gemini
```

Choose **Login with Google**, complete sign-in, then exit without entering a
prompt. Do not choose an API-key or Vertex route. The implementation agent did
not attempt OAuth. A quota-free, local-only check after sign-in is:

```sh
python benchmark/mechanisms-v1/harness/gemini_adapter.py auth-check
```

This reports only whether a private OAuth file has a refresh credential. It
prints no token and makes no network request. It cannot prove the credential
is still valid or that the account can use the selected model.

The existing `grading_runner.py self-test --grader G2 --binary ... --work ...
--dry` now prints the Gemini plan without reading auth or spawning a process.
`--run` would spend subscription quota on two `reply with the word OK` prompts;
it was **not run**. Never pass a benchmark packet or rubric to a model as a
transport check. Production runner integration uses `--gemini-bin` and optional
`--gemini-auth` in addition to the G1 options.
