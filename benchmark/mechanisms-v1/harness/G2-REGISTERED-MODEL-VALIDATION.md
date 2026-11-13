<!-- SPDX-License-Identifier: Apache-2.0 -->
# Registered G2 model correction: offline validation

Status: VERIFIED local synthetic/loader evidence, 2026-11-13 UTC; live acceptance PENDING.
Source baseline: `5ff24e627339d99156fda4507da6c783fb878957`.
Sources: `gemini_adapter.py`, `grading_runner.py`, `native/gemini_probe.mjs`,
`tests/test_gemini_adapter.py`, A-18 and the pinned installed Gemini CLI 0.68.0.
Host: Linux laptop; Python 3.12.16, NumPy 2.5.4, Node v26.13.0.

The registered model is `gemini-4-argon` in adapter defaults, command arguments,
isolated environment/settings, dispatch guard expectations, result checks and
grading-runner records. The real installed `loadSettings().merged` / native
Config probe resolves exactly that ID in all eight combinations of
`useGemini3_1`, `useCustomTools` and `hasAccessToPreview`, with HIGH thinking.
Argon is unlisted in the bundled catalog; this does not establish server
availability. No Argon model-family/capability metadata is invented.

The proposed preview fallback is DISABLED: the owner-approval amendment flag
remains None. Tests reject it before state/auth/process work and reject unknown
IDs or missing human quota confirmation. An in-memory synthetic approval tests
selection through argv, settings, environment, result validation and the
private receipt; it does not add approval to any repository record. Synthetic
success/refusal/uncertain cases record the tested Argon ID and cannot retry in
the same work directory. The existing dispatch and one-generation-POST guard
regressions still exercise only synthetic lifecycle/transport behavior.

Reproduction on this host (temporary files deliberately outside `/tmp` and Git):

```sh
export TMPDIR=/home/collincraig/Projects/martygraphics-g2-evidence/tmp
export CODEX_NATIVE_BINARY=/home/collincraig/.local/share/mise/installs/codex/0.167.2/bin/codex
export GEMINI_NATIVE_BINARY=/home/collincraig/.local/share/martygraphics-gemini-cli-0.68.0/node_modules/.bin/gemini
G2_TEST_PYTHON=/home/collincraig/.local/share/martygraphics-pr76-reviewfix-py312/bin/python
"$G2_TEST_PYTHON" -m unittest discover -s benchmark/mechanisms-v1/harness/tests -v
"$G2_TEST_PYTHON" -m unittest discover -s tools/tests -v
"$G2_TEST_PYTHON" benchmark/mechanisms-v1/harness/gemini_adapter.py check \
  --binary "$GEMINI_NATIVE_BINARY" \
  --work /home/collincraig/Projects/martygraphics-g2-evidence/native-check
```

The native check unshares network, copies no auth and makes no model request.
Its result records `selectedModel=gemini-4-argon`, eight Argon resolutions,
`thinkingLevel=HIGH`, zero tools, empty user memory and exact synthetic text/PNG.
The installed package is unchanged.

Initial full discovery used the laptop's newer default Codex and ran 255 tests:
229 passed, 24 skipped, one error and one failure. Both failures were the
existing G1 version guard (`CLI version changed; review invocation and isolation
again`), not G2. Setting `CODEX_NATIVE_BINARY` to installed pinned 0.167.2 resolved
all three G1 native tests (3 passed, 36.769 s). The complete harness was rerun
with that explicit pin; its final result is below.

Historical macOS evidence is cited, not rerun: `arm2/SYNTHETIC-VALIDATION.md`
(2026-11-13 response-policy full suite), #72 merged at
`9e95ad3d69a54bce75b1a86d5b136734fb3ddb84` on 2026-11-12, and #75 merged at
`5ff24e627339d99156fda4507da6c783fb878957` on 2026-11-13.
`DRY-BICYCLE.FACTCHECK-2.md` supplies the historical second check PASS (19 PASS,
0 FIX); no new research or model review was performed.

NOT RUN: real model-access-check, model calls/paid APIs, network to
Google/OpenAI/Anthropic, owner sign-in/auth-check or credential inspection,
genuine post-auth/remote-admin acceptance, live multimodal/resume acceptance,
registered benchmark or section 2.4 dry run, macOS renderer/native-media tests
on this Linux host, full app/engine builds, and the whole-tree manifest checker.
The latter would open protected registered inputs. Neither registered question
file was opened, parsed, searched or hashed; both paths were excluded from the
fresh sparse checkout. Existing synthetic tests also install a read-denial
hook. LOCK.json and PROTOCOL.md are unchanged; RUN-LOCK stays DRAFT and its
existing file pins are unchanged. FILES.json is checked only for changed paths,
unchanged-entry equality/order and appended new paths.

Final results (2026-11-13 UTC, pinned CLIs):

| Check | Result |
| --- | --- |
| Full harness discovery | 255 tests: 231 passed, 24 skipped, zero errors/failures; 199.567 s |
| Focused G2 discovery | 25 passed, zero skips; 27.390 s |
| Tools discovery | 52 passed, zero skips; 0.564 s |
| Shipped quota-free native check | PASS; all eight conditions select Argon; HIGH; network=false; authCopied=false |

The 24 skips are 21 macOS WebKit renderer methods and 3 Apple native-media
methods. Native Linux G1 and all 6 installed-Gemini tests ran. No skipped test
is counted as a pass.

Evidence SHA-256 (logs retained on the implementation host):

| Evidence | SHA-256 |
| --- | --- |
| `harness-pinned-tests.log` | `f07baf457366b740a1028f6c42a689b7dc67e38bf943700c3dc2bf691dae4133` |
| `g2-tests.log` | `db8108c8ed04507805069eee41240b6f2b4baddd5e8a61fd46c22bd2d335de55` |
| `tools-tests.log` | `9b600a43e213a533b49ac97e82909cf703a06a1afea68a9862e39151ac66b890` |
| `g1-pinned-tests.log` | `4b1915ba5edd9bfb44af79be45f435b5cbab859c7667b016f34c1a48afeeb2e4` |
| `native-check/NATIVE-CHECK.json` | `f19e647b389eb8352d4465a6096be6a1424f60c9e409b5235f32aaed102a20ce` |
| `harness-tests.log` | `abb3c39263a74a2737d69454fa2de15569439d5d0ebf69f23014c9f0d2f4950d` |
