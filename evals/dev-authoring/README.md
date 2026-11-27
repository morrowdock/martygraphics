# Dev authoring eval (describe → scene)

A development eval for how well an author model turns a plain-language teaching request into a
**mechanically correct** MartyGraphics scene. It is separate from the registered mechanisms benchmark: it
uses none of that benchmark's question, grader-question or acceptance files, and its 40 requests are new.

- [requests.json](requests.json): 40 original requests (12 physics, 10 math, 10 CS, 8 ML kit). The author
  sees only this file and the guidance.
- [specs.json](specs.json): one machine-checkable spec per request (expected items, numeric relations, step
  order), with the semantics fixed in [SPEC-CONTRACT.md](SPEC-CONTRACT.md).
- [FREEZE.json](FREEZE.json): SHA-256 of those three files, committed before any scene was authored.

## Protocol

1. Freeze requests, specs and contract (one commit, before any authoring).
2. **Baseline pass.** For each request the author writes attempt 1 using only the
   [baseline guidance](guidance/baseline/MANIFEST.json): the grammar inventory (`MGGrammar.document()`),
   the protocol and ML docs, their worked examples and the existing validator messages. On a refusal the
   author repairs with that message, at most 3 repairs (attempts 2–4).
3. Grade every final output against its spec.
4. Improve the guidance and the validator messages.
5. **Improved pass.** Author all 40 again from scratch with the improved guidance, without opening the
   baseline outputs. Same repair limit; lint warnings may trigger a repair, but count against the same limit.
6. Grade, and compare.

A request is mechanically correct when its final output is valid and passes every check. Partial credit is
reported separately.

## Tools

| Path | Role |
| --- | --- |
| [vendor/tools/scene_v1_check.py](vendor/tools/scene_v1_check.py) | Copied unchanged from `D:\work\mg-scene-schema-20261126\tools\scene_v1_check.py` (branch `feat/scene-v1-json-schema` at `8882d38`, file last changed in `0940539`), with its draft schema ([vendor/docs/schemas](vendor/docs/schemas/scene-v1.draft.schema.json), last changed in `29f7600`). It is the core scene validator for this eval. Swift `MGParser` stays authoritative. |
| [tools/ml_check.py](tools/ml_check.py) | Draft Python mirror of `MGMLKit.check` (no PNG kinds). |
| [tools/grammar_doc.py](tools/grammar_doc.py) | Mirrors `MGGrammar.document()` (no Swift toolchain on the authoring host). |
| [tools/attempt.py](tools/attempt.py) | Validates an author's latest attempt and logs the message: `baseline` prints today's messages, `improved` adds the fix hint and the lint. At most 1 + 3 attempts. |
| [tools/hints.py](tools/hints.py) | Python mirror of `MGRepairHint` and `MGMLReason.hint` ([drift test](../../tools/tests/test_repair_hints.py)). |
| [tools/grade.py](tools/grade.py) | Grades a run against the specs with the engine's conventions; writes `results/RUN.json`. |
| [tools/test_grader.py](tools/test_grader.py) | 29 mutation cases: injected mistakes must fail their check. |

Results: [RESULTS.md](RESULTS.md). Outputs and logs: `runs/baseline`, `runs/improved` (with the filled
[checklists](runs/improved/CHECKLISTS.md)).

```sh
python tools/attempt.py improved P01      # check runs/improved/P01/attempt-N.json
python tools/grade.py improved            # grade all 40
python -m unittest discover -s tools -p "test_*.py"
```

## Independent author run

1. Give the author one request at a time from `requests.json` and one guidance bundle: the files in
   [guidance/baseline](guidance/baseline/MANIFEST.json) or [guidance/improved](guidance/improved/MANIFEST.json). Never
   give it `specs.json`, `SPEC-CONTRACT.md` or another run's outputs.
2. Save its JSON as `runs/<run>/<id>/attempt-1.json` and run `tools/attempt.py <run> <id>`. A run name that
   starts with `baseline` (for example `baseline-codex-1`) prints the baseline messages; any other name (for example
   `improved-codex-1`) prints the fix hints and the lint. On a refusal, send the printed message back and save
   `attempt-2.json`, up to `attempt-4.json`. With the improved bundle, lint warnings may also be sent back, within
   the same limit.
3. Grade with `tools/grade.py <run>`. Use a new run name per author and repetition.

## Limits

The author and the grader designer were the same model in the first run, so the result can be biased toward the
author. The specs were frozen before authoring to limit that, but an independent author is still needed. See
[RESULTS.md](RESULTS.md#limits-stated-plainly).
