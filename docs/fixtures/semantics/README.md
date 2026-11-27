# Semantic fixtures (portability step 1)

[Portability map](../../PORTABILITY-MAP.md) · [Proposal](../../PORTABILITY-PROPOSAL.md) · [Runner](../../../tools/semantic_fixtures.py)

Original synthetic inputs that record what the current Swift engine is expected to do.
They come before any file moves, as
[step 1 of the portability proposal](../../PORTABILITY-PROPOSAL.md#a-bounded-proposal) asks.
They support a later core/adapter comparison. They are **not** parity evidence: no Swift ran
when they were written. Expected values come from reading the Swift sources at this commit.
No Windows, Linux or browser support is claimed.

## Layout

Each `NAME.expected.json` names one input. The input is a sibling file (`NAME.scene.json`,
`NAME.stream.json`, `NAME.cases.json`) or inline bytes (`{"utf8": …}` or `{"hex": …}`, with
optional `padToBytes` space padding). Inline bytes cover inputs that need exact byte spelling
or contain malformed scene JSON. A `NAME.patches.json` beside a scene lists the patches applied
to it in order.

| Folder | Fixtures | Covers |
| --- | ---: | --- |
| `parser/` | 43 | 7 accept, 33 reject and 3 open cases: closed keys, kinds, version and dim, counts and lengths, world bounds, text, markup and placeholder rules, references and cycles (also after cumulative step edits), camera, nesting depth, non-JSON, non-UTF-8 and oversize input |
| `numeric/` | 5 | `MGPhysics.format` cases, number cells stored as display text, and the cell length and magnitude limits |
| `templates/` | 14 | Items and steps that `two_pointers` and `bst` resolve to, `hide`/`over`, and template parameter refusals. Two of these refusals are visible only to Swift |
| `patches/` | 1 | A 13-patch transaction sequence: accepted patches, a failed update that rolls back a valid first op, a stale revision, references, closed envelopes, unknown ops, immutable keys, step range, op count and bad JSON |
| `streams/` | 5 | Preview growth and strict `finish()`, including a stream that previewed and then failed |
| `timeline/` | 3 | `move` easing and vector following, step visibility with cumulative edits, patch blending of angles and points, and the spring curve |

## Expectation format

`format` is `mg-semantics-expected/1`. Top-level and per-expectation keys are closed. The
runner refuses unknown keys. Each expectation has:

- `check`: `outcome` (accept, or reject with the reason code), `preflight` (the Python draft
  checker's own verdict), `resolved` (a subset of the resolved `MGScene`), `format`, `patches`,
  `patches.resolved`, `stream.previews`, `stream.finish`, `timeline.items`, `timeline.frame`,
  `timeline.cycle` or `timeline.blend`.
- `python`: what this repository can check without Swift.
  - `checked`: the draft preflight [`tools/scene_v1_check.py`](../../../tools/scene_v1_check.py) reproduces the expectation.
  - `model`: a small Python model of one Swift function in the runner reproduces it.
  - `observed`: the behavior is **undecided**. `expect` is `undetermined` and `observed`
    records the Python result without endorsing it.
  - `none`: only Swift can check it.
- `swift`: `pending-mac` for every Swift-facing expectation (`not-applicable` for `preflight`).
  The runner refuses any other value. A future Mac run must change the format to record
  evidence, so this corpus cannot claim parity by accident.

`resolved` and `timeline.*` values are subsets: only the listed fields are expected. Item
lists are in scene order. `pts` are `[x, y]` or `[x, y, z]` world points. Compare coordinates
and computed doubles with a tolerance of 1e-9, or the `tolerance` given. Compare everything
else exactly.

## Running on a machine without Swift

```sh
python3 tools/semantic_fixtures.py -v
python3 -m unittest discover -s tools/tests -v
```

The runner uses only the Python standard library. It exits 1 on a mismatch, a malformed
expectation or an input without an expected-result file. Its summary counts what Python
reproduced and what still needs Swift.

The draft preflight and its schema
([`docs/schemas/scene-v1.draft.schema.json`](../../schemas/scene-v1.draft.schema.json)) are
byte-identical copies from the local `feat/scene-v1-json-schema` branch at commit `c2269d7`.
Their schema notes, Swift parity evidence and own tests stay on that branch. The preflight test
needs fixtures that exist only there. Swift's `MGParser` remains the acceptance authority.

## What needs a Mac

Every Swift-facing expectation stays `pending-mac` until a Swift run records it. Python cannot
reach these at all (`python: none`): resolved items and steps, template expansion (including the
`template.build` and `over.ref` refusals), stream previews, and all `MGTimeline` samples.
The open cases need a decision before any second decoder or text classifier exists:

- duplicate object keys (the Python preflight refuses them; a browser `JSON.parse` keeps the last value);
- a UTF-8 byte-order mark;
- U+2028 in plain text. The Python preflight refuses Zl/Zp. `MGParser` refuses only
  `CharacterSet.controlCharacters`, so a static reading suggests Swift accepts it.

A suggested Mac pass: parse every `.scene.json` and inline input with `MGParser.scene(data:)`,
apply each `.patches.json` with `MGPatch.parse` and `MGScene.applying`, feed each stream's
chunks to `MGStreamParser`, and sample `MGTimeline` as each expectation describes. Then
compare. `ProgrammaticVideoTests` also feeds every `.json` under `docs/fixtures` to
the default parser and to the parser with programmatic video disabled. It compares their
results, including matching rejections, for each file.
